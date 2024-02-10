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

type Prog = Map AString Func

filFunc :: Val.Func -> Func
filFunc x = Func
  { retTy = fromTy $ Val.retTy x
  , args = fmap fromVal $ case Val.arg x of
      Val.VUnit _ -> []
      Val.VTuple _ vs -> toList vs
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
  = Call AString [Val]
  | Switch Val Block [Alt]
  | If Val Block Block
  | CallTailCall TailCallId [Val]
  deriving (Show, Data)

data Alt
  = Alt Scalar Block
  deriving (Show, Data)

data Val
  = Unit Position
  | Type Position Ty
  | Scalar Position Scalar
  deriving (Show, Data)

instance Positioned Val where
  positionOf x = case x of
    Unit pos -> pos
    Type pos _ -> pos
    Scalar pos _ -> pos

instance Eq Val where
  x == y = case (x, y) of
    (Unit _, Unit _) -> True
    (Type _ a, Type _ b) -> a == b
    (Scalar _ a, Scalar _ b) -> a == b
    _ -> False

data Register = Reg{ registerTy :: Ty, registerId :: RegisterId } deriving (Show, Data)

instance Eq Register where
  x == y = registerId x == registerId y

data Ty
  = TyUnit Position
  | TyOpaque Position
  | TyPointer Position Ty
  | TyEnum Position
  | TyString Position
  | TyChar Position Sz
  | TyFloat Position Sz
  | TyInt Position Sz
  | TyUInt Position Sz
  | TyBool Position
  | TyArray Position Sz Ty
  deriving (Show, Data)

instance Eq Ty where
  x == y = case (x, y) of
    (TyUnit _, TyUnit _) -> True
    (TyOpaque _, TyOpaque _) -> True
    (TyPointer _ a, TyPointer _ b) -> a == b
    (TyEnum _, TyEnum _) -> True
    (TyString _, TyString _) -> True
    (TyChar _ a, TyChar _ b) -> a == b
    (TyFloat _ a, TyFloat _ b) -> a == b
    (TyInt _ a, TyInt _ b) -> a == b
    (TyUInt _ a, TyUInt _ b) -> a == b
    (TyBool _, TyBool _) -> True
    (TyArray _ a b, TyArray _ c d) -> a == c && b == d
    _ -> False

instance Positioned Ty where
  positionOf x = case x of
    TyUnit pos -> pos
    TyOpaque pos -> pos
    TyPointer pos _ -> pos
    TyEnum pos -> pos
    TyString pos -> pos
    TyChar pos _ -> pos
    TyFloat pos _ -> pos
    TyInt pos _ -> pos
    TyUInt pos _ -> pos
    TyBool pos -> pos
    TyArray pos _ _ -> pos

bitsize :: Ty -> Sz
bitsize x = case x of
  TyPointer _ _ -> bitsizePointer
  TyEnum _ -> 32
  TyString _ -> bitsizePointer
  TyChar _ a -> a
  TyFloat _ a -> a
  TyInt _ a -> a
  TyUInt _ a -> a
  TyBool _ -> 1
  _ -> unreachable "unexpected type as input to bitsize" x

isTyUnit :: Ty -> Bool
isTyUnit TyUnit{} = True
isTyUnit _ = False

class TypeOf a where
  typeOf :: a -> Ty

instance TypeOf Register where
  typeOf = registerTy

instance TypeOf Val where
  typeOf x = case x of
    Unit pos -> TyUnit pos
    Scalar _ a -> typeOf a
    Type{} -> unreachable "unable to take typeOf type value" x

data Scalar
  = String Position Text
  | Char Position Char
  | Float Position Double
  | Int Position Integer
  | UInt Position Integer
  | Bool Position Bool
  | Enum Position UIdent Integer
  | Undef Position Ty
  | Extern Position AString Ty
  | Register Position Register
  deriving (Show, Data)

instance Eq Scalar where
  x == y = case (x, y) of
    (String _ a, String _ b) -> a == b
    (Char _ a, Char _ b) -> a == b
    (Float _ a, Float _ b) -> a == b
    (Int _ a, Int _ b) -> a == b
    (UInt _ a, UInt _ b) -> a == b
    (Bool _ a, Bool _ b) -> a == b
    (Enum _ a b, Enum _ c d) -> a == c && b == d
    (Undef _ a, Undef _ b) -> a == b
    (Extern _ a b, Extern _ c d) -> a == c && b == d
    (Register _ a, Register _ b) -> a == b
    _ -> False

instance Positioned Scalar where
  positionOf x = case x of
    String pos _ -> pos
    Char pos _ -> pos
    Float pos _ -> pos
    Int pos _ -> pos
    UInt pos _ -> pos
    Bool pos _ -> pos
    Enum pos _ _ -> pos
    Undef pos _ -> pos
    Extern pos _ _ -> pos
    Register pos _ -> pos

instance Pretty Scalar where
  pretty x = case x of
    String _ a -> pretty $ show a
    Char _ a -> pretty $ show a
    Float _ a -> pretty a
    Int _ a -> pretty a
    UInt _ a -> pretty a
    Bool _ a -> pretty a
    Undef _ t -> "<undef" <+> pretty t <> ">"
    Enum _ a _ -> "tag" <+> pretty a
    Extern _ nm _ -> "<extern" <+> pretty nm <+> ">"
    Register _ r -> pretty r

instance TypeOf Scalar where
  typeOf x = case x of
    String pos _ -> TyString pos
    Char pos _ -> TyChar pos 8
    Float pos _ -> TyFloat pos 64
    Int pos _ -> TyInt pos 32
    UInt pos _ -> TyUInt pos 32
    Bool pos _ -> TyBool pos
    Enum pos _ _ -> TyEnum pos
    Undef _ t -> t
    Extern _ _ t -> t
    Register _ a -> typeOf a

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
  Val.VTuple _ bs -> toList bs
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
  Val.VType pos t -> Type pos $ fromTy t
  Val.VUnit pos -> Unit pos
  Val.VScalar pos a -> Scalar pos $ fromVScalar a
  _ -> unreachable "FIL.hs:fromVal:unexpected value" x

fromVScalar :: VScalar -> Scalar
fromVScalar x = case x of
  VString pos a -> String pos a
  VChar pos a -> Char pos a
  VFloat pos a -> Float pos a
  VInt pos a -> Int pos a
  VUInt pos a -> UInt pos a
  VBool pos a -> Bool pos a
  VEnum pos a b -> Enum pos a b
  VUndef pos t -> Undef pos $ fromTy t
  VExtern pos a b -> Extern pos a $ fromTy b
  VRegister pos a -> Register pos $ fromRegister a
  _ -> unreachable "fromVScalar: scalar not removed" x

fromTy :: Type.Ty -> Ty
fromTy x = case x of
  Type.TyOpaque pos _ -> TyOpaque pos
  Type.TyArray pos sz t -> TyArray pos sz $ fromTy t
  Type.TyPointer pos ty -> TyPointer pos (fromTy ty)
  Type.TyEnum pos _ -> TyEnum pos
  Type.TyString pos -> TyString pos
  Type.TyChar pos sz -> TyChar pos sz
  Type.TyFloat pos sz -> TyFloat pos sz
  Type.TyInt pos sz -> TyInt pos sz
  Type.TyUInt pos sz -> TyUInt pos sz
  Type.TyBool pos -> TyBool pos
  Type.TyUnit pos -> TyUnit pos
  _ -> unreachable "fromTy: type not removed" x

isTyInt :: Ty -> Bool
isTyInt t = case t of
  TyInt{} -> True
  _ -> False

isUIntTy :: Ty -> Bool
isUIntTy x = case x of
  TyUInt{} -> True
  TyChar{} -> True
  TyEnum{} -> True
  TyBool{} -> True
  _ -> False

isIntTy :: Ty -> Bool
isIntTy x = isTyInt x || isUIntTy x

isTyPointer :: Ty -> Bool
isTyPointer t = case t of
  TyPointer{} -> True
  _ -> False

isTyFloat :: Ty -> Bool
isTyFloat t = case t of
  TyFloat{} -> True
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
      [Unit _] -> pretty b
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
    TyOpaque _ -> "<Opaque>"
    TyUnit _ -> "()"
    TyPointer _ t -> "Pointer" <+> f t
    TyArray _ sz t -> "Array" <+> pretty sz <+> f t
    TyEnum _ -> "Enum"
    TyString _ -> "String"
    TyChar _ sz -> "C" <> pretty sz
    TyFloat _ sz -> "F" <> pretty sz
    TyInt _ sz -> "I" <> pretty sz
    TyUInt _ sz -> "U" <> pretty sz
    TyBool _ -> "Bool"
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
    Type _ t -> "`" <> pretty t <> "`"
    Unit _ -> "()"
    Scalar _ a -> pretty a

instance Pretty Register where
  pretty x = pretty (registerId x)

