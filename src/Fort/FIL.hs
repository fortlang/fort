module Fort.FIL
( module Fort.FIL
, Sz
, RegisterId(..)
, UIdent
, TailCallId(..)
)

where

import Data.Bifunctor
import Fort.Utils hiding (If, Extern, UInt, Let, TailRecDecls, Decl, Scalar, Unit, Stmt)
import Fort.Val (RegisterId, VScalar(..), VStmt(..), VDecl(..), TailCallId(..))
import qualified Data.Map as Map
import qualified Fort.Type as Type
import qualified Fort.Val as Val

filModules :: [(FilePath, Val.Prog)] -> [(FilePath, Prog)]
filModules xs = [ (fn, fmap filFunc prg) | (fn, prg) <- xs ]

type Prog = Map Text Func

filFunc :: Val.Func -> Func
filFunc x = Func
  { retTy = fromTy $ Val.retTy x
  , args = fmap fromVal $ case Val.arg x of
      Val.VUnit -> []
      Val.VTuple vs -> toList vs
      v -> [v]
  , body = fromBlock $ rewriteBi Val.flattenVal $ Val.body x
  }

data Func = Func{ retTy :: Ty, args :: [Val], body :: Block }
  deriving (Show, Data)

instance Pretty Func where
  pretty x = "func" <+> tupled (pretty <$> args x) <+> "->" <+> pretty (retTy x) <+> "=" <+> pretty (body x)

data Block = Block
  { blockDecls :: [Decl]
  , blockResult :: Result
  } deriving (Show, Data)

data Result
  = Cont [Val]
  | Exit Val
  deriving (Show, Data)

data Decl
  = Let [Val] Stmt
  | TailRecDecls TailCallId (Map TailCallId ([Val], Block))
  | TailCall TailCallId [Val]
  deriving (Show, Data)

data Stmt
  = Call LIdent [Val]
  | Switch Val Block [Alt]
  | If Val Block Block
  | CallTailCall TailCallId [Val]
  deriving (Show, Data)

data Alt
  = Alt Scalar Block
  deriving (Show, Data)

data Val
  = Unit
  | Type Ty
  | Scalar Scalar
  deriving (Show, Eq, Data)

data Register = Reg{ registerTy :: Ty, registerId :: RegisterId } deriving (Show, Eq, Data)

data Ty
  = TyUnit
  | TyOpaque
  | TyPointer Ty
  | TyEnum
  | TyString
  | TyChar Sz
  | TyFloat Sz
  | TyInt Sz
  | TyUInt Sz
  | TyBool
  | TyArray Sz Ty
  deriving (Show, Eq, Data)

bitsize :: Ty -> Sz
bitsize x = case x of
  TyPointer _ -> bitsizePointer
  TyEnum -> 32
  TyString -> bitsizePointer
  TyChar a -> a
  TyFloat a -> a
  TyInt a -> a
  TyUInt a -> a
  TyBool -> 1
  _ -> unreachable "unexpected type as input to bitsize" x

isTyUnit :: Ty -> Bool
isTyUnit TyUnit = True
isTyUnit _ = False

class TypeOf a where
  typeOf :: a -> Ty

instance TypeOf Register where
  typeOf = registerTy

instance TypeOf Val where
  typeOf x = case x of
    Unit -> TyUnit
    Scalar a -> typeOf a
    Type _ -> unreachable "unable to take typeOf type value" x

data Scalar
  = String Text
  | Char Char
  | Float Double
  | Int Integer
  | UInt Integer
  | Bool Bool
  | Enum UIdent Integer
  | Undef Ty
  | Extern LIdent Ty
  | Register Register
  deriving (Show, Eq, Data)

instance Pretty Scalar where
  pretty x = case x of
    String a -> pretty $ show a
    Char a -> pretty $ show a
    Float a -> pretty a
    Int a -> pretty a
    UInt a -> pretty a
    Bool a -> pretty a
    Undef t -> "<undef" <+> pretty t <> ">"
    Enum a _ -> "tag" <+> pretty a
    Extern nm _ -> "<extern" <+> pretty nm <+> ">"
    Register r -> pretty r

instance TypeOf Scalar where
  typeOf x = case x of
    String _ -> TyString
    Char _ -> TyChar 8
    Float _ -> TyFloat 64
    Int _ -> TyInt 32
    UInt _ -> TyUInt 32
    Bool _ -> TyBool
    Enum _ _ -> TyEnum
    Undef t -> t
    Extern _ t -> t
    Register a -> typeOf a

fromAlt :: Val.Alt -> Alt
fromAlt x = case x of
  Val.AltScalar a blk -> Alt (fromVScalar a) $ fromBlock blk
  Val.AltDefault{} -> unreachable "fromAlt:default alt not removed" x

fromDecl :: VDecl -> Decl
fromDecl x = case x of
  VLet a b -> Let (fromTuple a) $ fromStmt b
  VTailRecDecls a m -> TailRecDecls a $ fmap (Data.Bifunctor.bimap fromTuple fromBlock) m
  VTailCall a b -> TailCall a $ fromTuple b

fromStmt :: VStmt -> Stmt
fromStmt x = case x of
  VCall v val -> Call v $ fromTuple val
  VSwitch a b cs -> case fromTuple a of
    [va] -> Switch va (fromBlock b) $ fmap fromAlt cs
    vs -> unreachable "expected exactly one switch value" vs
  VIf a bs cs -> If (fromVal a) (fromBlock bs) (fromBlock cs)
  VCallTailCall a b -> CallTailCall a $ fromTuple b

fromTuple :: Val.Val -> [Val]
fromTuple x = fmap fromVal $ filter (not . Val.isNone) $ case x of
  Val.VTuple bs -> toList bs
  _ -> [x]

fromBlock :: Val.Block -> Block
fromBlock x = go mempty (fromDecl <$> Val.blockDecls x)
  where
    go rs [] = Block
      { blockDecls = reverse rs
      , blockResult = Cont $ fromTuple $ Val.blockResult x
      }
    go rs (d : ds) = case d of
      Let _ (Call nm [v]) | textOf nm == "Prim.exit" -> Block
        { blockDecls = reverse rs
        , blockResult = Exit v
        }
      _ -> go (d : rs) ds

fromRegister :: Val.Register -> Register
fromRegister x = Reg
  { registerTy = fromTy $ Val.registerTy x, registerId = Val.registerId x }

fromVal :: Val.Val -> Val
fromVal x = case x of
  Val.VType t -> Type $ fromTy t
  Val.VUnit -> Unit
  Val.VScalar a -> Scalar $ fromVScalar a
  _ -> unreachable "FIL.hs:fromVal:unexpected value" x

fromVScalar :: VScalar -> Scalar
fromVScalar x = case x of
  VString a -> String a
  VChar a -> Char a
  VFloat a -> Float a
  VInt a -> Int a
  VUInt a -> UInt a
  VBool a -> Bool a
  VEnum a b -> Enum a b
  VUndef t -> Undef $ fromTy t
  VExtern a b -> Extern a $ fromTy b
  VRegister a -> Register $ fromRegister a
  _ -> unreachable "fromVScalar: scalar not removed" x

fromTy :: Type.Ty -> Ty
fromTy x = case x of
  Type.TyOpaque _ -> TyOpaque
  Type.TyArray sz t -> TyArray sz $ fromTy t
  Type.TyPointer ty -> TyPointer (fromTy ty)
  Type.TyEnum _ -> TyEnum
  Type.TyString -> TyString
  Type.TyChar sz -> TyChar sz
  Type.TyFloat sz -> TyFloat sz
  Type.TyInt sz -> TyInt sz
  Type.TyUInt sz -> TyUInt sz
  Type.TyBool -> TyBool
  Type.TyUnit -> TyUnit
  _ -> unreachable "fromTy: type not removed" x

isTyInt :: Ty -> Bool
isTyInt t = case t of
  TyInt _ -> True
  _ -> False

isUIntTy :: Ty -> Bool
isUIntTy x = case x of
  TyUInt _ -> True
  TyChar _ -> True
  TyEnum -> True
  TyBool -> True
  _ -> False

isIntTy :: Ty -> Bool
isIntTy x = isTyInt x || isUIntTy x

isTyPointer :: Ty -> Bool
isTyPointer t = case t of
  TyPointer _ -> True
  _ -> False

isTyFloat :: Ty -> Bool
isTyFloat t = case t of
  TyFloat _ -> True
  _ -> False

ppTuple :: [Doc ann] -> Doc ann
ppTuple xs = case xs of
  [] -> ""
  [x] -> x
  _ -> tupled xs

instance Pretty Decl where
  pretty x = case x of
    TailRecDecls _ m -> "tailrec" <+> vlist ""
      [ pretty a <+> "= \\" <+> ppTuple (fmap pretty bs) <+> "->" <+> pretty c | (a, (bs, c)) <- Map.toList m ]
    Let a b -> case a of
      [Unit] -> pretty b
      _ -> ppTuple (fmap pretty a) <+> "=" <+> pretty b
    TailCall a b -> "tailcall" <+> pretty a <+> ppTuple (fmap pretty b)

instance Pretty Stmt where
  pretty x = case x of
    If a b c -> "if" <+> nest 2 (vcat [ pretty a, "then" <+> pretty b, "else" <+> pretty c ])
    Call a b -> "call" <+> pretty a <+> ppTuple (fmap pretty b)
    CallTailCall a b -> "calltc" <+> pretty a <+> ppTuple (fmap pretty b)
    Switch a blk alts -> "switch" <+> pretty a <+> vlist "of" ("<default> ->" <+> pretty blk : fmap pretty alts)

instance Pretty Result where
  pretty x = case x of
    Cont vs -> ppTuple (fmap pretty vs)
    Exit v -> "Prim.exit" <+> pretty v

instance Pretty Block where
  pretty x = vlist "do" $ fmap pretty (blockDecls x) ++ [pretty $ blockResult x]

instance Pretty Alt where
  pretty x = case x of
    Alt a b -> pretty a <+> "->" <+> pretty b

instance Pretty Ty where
  pretty x = case x of
    TyOpaque -> "<Opaque>"
    TyUnit -> "()"
    TyPointer t -> "Pointer" <+> f t
    TyArray sz t -> "Array" <+> pretty sz <+> f t
    TyEnum  -> "Enum"
    TyString -> "String"
    TyChar sz -> "C" <> pretty sz
    TyFloat sz -> "F" <> pretty sz
    TyInt sz -> "I" <> pretty sz
    TyUInt sz -> "U" <> pretty sz
    TyBool -> "Bool"
    where
      f ty = case ty of
        TyArray{} -> parens (pretty ty)
        TyPointer{} -> parens (pretty ty)
        TyChar{} -> parens (pretty ty)
        TyFloat{} -> parens (pretty ty)
        TyInt{} -> parens (pretty ty)
        TyUInt{} -> parens (pretty ty)
        _ -> pretty ty

instance Pretty Val where
  pretty x = case x of
    Type t -> "`" <> pretty t <> "`"
    Unit -> "()"
    Scalar a -> pretty a

instance Pretty Register where
  pretty x = pretty (registerId x)

