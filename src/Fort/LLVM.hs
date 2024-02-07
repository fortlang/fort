{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}
module Fort.LLVM (llvmModules, BuildType(..))

where

import Fort.FIL (Register(..), RegisterId(..), Scalar(..), Val(..), Ty(..), TailCallId(..))
import Fort.Utils hiding (Stmt, Extern, UInt, Scalar, Unit)
import Numeric
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Fort.FIL as FIL

data St = St
  { currentBlockId :: BlockId
  , nextBlockId :: BlockId
  , blocks :: Map BlockId Block
  , tailCallBlockIds :: Map TailCallId BlockId
  , tailCallFILBlocks :: Map TailCallId (Map TailCallId FIL.Block)
  } deriving Show

initBlock :: Block
initBlock = Block
  { blockPhis = mempty
  , blockStmts = mempty
  , blockTerminator = NoTerminator
  }

newtype BlockId = BlockId{ unBlockId :: Int } deriving (Show, Eq, Ord, Num, Data)

instance Pretty BlockId where pretty = llvm

data BuildType
  = Exe
  | Obj
  | NoCode
  deriving (Show, Eq)

-- only using IO for debug prints
llvmModules :: [(FilePath, FIL.Prog)] -> IO [(FilePath, (BuildType, Doc ann))]
llvmModules xs =
  sequence [ (fn,) <$> evalStateT (llvmProg x) initSt | (fn, x) <- xs ]

llvmProg :: FIL.Prog -> M (BuildType, Doc ann)
llvmProg x = do
  let funcs = Map.toList x
  defs <- mapM (llvmFuncBlocks . snd) funcs
  let blks = concatMap Map.elems defs
  let strs = zip (strings blks) [0 :: Int ..]
  let nms = mkTok noPosition <$> Map.keys x
  pure (bt, vcat $ llvmDeclares nms strs blks : fmap (llvmDefine strs) (zip funcs defs))
  where
    bt = if
      | "main" `elem` Map.keys x -> Exe
      | Map.null x -> NoCode
      | otherwise -> Obj

llvmDeclares :: [LIdent] -> [(Text, Int)] -> [Block] -> Doc ann
llvmDeclares nms strs m = vcat
  [ vcat (("declare" <+>) <$> calls nms m)
  , vcat (("declare" <+>) <$> intrinsics m)
  , vcat [ llvm nm <+> "= external global" <+> llvm ty | (nm, TyPointer ty) <- externs m ]
  , vcat [ "@.str." <> pretty i <+> "= private unnamed_addr constant" <+> llvmStringConst s | (s, i) <- strs ]
  ]

llvmDefine :: [(Text, Int)] -> ((Text, FIL.Func), Map BlockId Block) -> Doc ann
llvmDefine strs0 ((nm, x), blks) = do
  vcat
    [ "define" <+> llvm (FIL.retTy x) <+> "@" <> pretty nm <> llvmArgs (FIL.args x) <> " {"
    , vcat [ pretty (llvmStringConstName i) <+> "=" <+> "bitcast" <+> llvmStringConstType s <> "*" <+> "@.str." <> pretty i <+> "to i8*" | (s, i) <- strs ]
    , "br label %lbl_0"
    , vcat [ nest 2 $ vsep [llvmBlockId lbl <> ":", llvm blk] | (lbl, blk) <- sortByFst $ Map.toList $ stringsToStringIds (Map.fromList strs) blks ]
    , "}"
    ]
  where
    strs = filter (flip elem (strings $ Map.elems blks) . fst) strs0

llvmFuncBlocks :: FIL.Func -> M (Map BlockId Block)
llvmFuncBlocks x = do
  put initSt
  bid <- freshBlockId
  sequence_ [ freshTailRecDecls a m | FIL.TailRecDecls a m <- universeBi x ]
  llvmBlock bid bid $ FIL.body x
  blks <- Map.filter (not . isEmptyBlock) <$> gets blocks
  pure $ fmap (\blk -> blk{ blockStmts = reverse (blockStmts blk) }) blks

llvmBlock :: BlockId -> BlockId -> FIL.Block -> M ()
llvmBlock targ bid blk = do
  setCurrentBlock bid
  llvmDecls $ FIL.blockDecls blk
  case FIL.blockResult blk of
    FIL.Exit v -> pushTerminator $ Ret v
    FIL.Cont rs -> unless (null rs) $ do
      pushPhis targ rs
      pushTerminator $ Br targ

calls :: [LIdent] -> [Block] -> [Doc ann]
calls nms m = [ llvm rt <+> llvm nm <+> tupled (fmap llvm ts) | (rt, nm, ts) <- xs ]
  where
    xs = List.nub [ (FIL.typeOf r, nm, filter (not . FIL.isTyUnit) $ fmap FIL.typeOf vs) | Instr r (Call nm) vs <- universeBi m, nm `List.notElem` nms ]

strings :: [Block] -> [Text]
strings m = List.nub [ s | String s <- universeBi m ]

externs :: [Block] -> [(LIdent, Ty)]
externs m = [ (nm, ty) | Extern nm ty <- List.nub (universeBi m) ]

intrinsics :: [Block] -> [Doc ann]
intrinsics m = [ llvm rt <+> intrinsicName nm rt ts <+> tupled (fmap llvm ts) | (rt, nm, ts) <- xs ]
  where
    xs = List.nub [ (FIL.typeOf r, nm, fmap FIL.typeOf vs) | Instr r (Intrinsic nm) vs <- universeBi m ]

llvmArgs :: [FIL.Val] -> Doc ann
llvmArgs = tupled . fmap llvmTyped

llvmStringConstName :: Int -> Text
llvmStringConstName i = "%str_" <> Text.pack (show i)

stringsToStringIds :: Map Text Int -> Map BlockId Block -> Map BlockId Block
stringsToStringIds strs = transformBi f
  where
    f (String s) = String $ llvmStringConstName $ lookup_ s strs
    f x = x

llvmEscString :: String -> String
llvmEscString s = concatMap llvmEscChar (s ++ "\0")

llvmEscChar :: Char -> String
llvmEscChar c = if
  | c >= ' ' && c <= '~' && c /= '"' && c /= '\\' -> [c]
  | otherwise -> concat $ go hex
  where
  i = fromEnum c
  hex = case showHex i "" of
    cs | even (length cs) -> cs
       | otherwise -> '0' : cs
  go s = case s of
    a : b : rest -> ['\\', a, b ] : go rest
    _ -> []

llvmStringConstType :: Text -> Doc ann
llvmStringConstType s = brackets (pretty (Text.length s + 1) <+> "x i8")

llvmStringConst :: Text -> Doc ann
llvmStringConst s =
  llvmStringConstType s <+> "c" <> dquotes (pretty $ llvmEscString (Text.unpack s)) <> ", align 1"

freshBlockId :: M BlockId
freshBlockId = do
  i <- gets nextBlockId
  modify' $ \st -> st{ nextBlockId = i + 1, blocks = Map.insert i initBlock $ blocks st }
  pure i

freshTailRecDecl :: (TailCallId, ([Val], FIL.Block)) -> M BlockId
freshTailRecDecl (nm, (vs, _)) = do
  bid <- freshBlockId
  initPhis bid vs
  modify' $ \st -> st{ tailCallBlockIds = Map.insert nm bid $ tailCallBlockIds st }
  pure bid

freshTailRecDecls :: TailCallId -> Map TailCallId ([Val], FIL.Block) -> M ()
freshTailRecDecls k m = do
  mapM_ freshTailRecDecl $ Map.toList m
  modify' $ \st -> st{ tailCallFILBlocks = Map.insert k (fmap snd m) $ tailCallFILBlocks st }

llvmTailCallBlock :: BlockId -> (TailCallId, FIL.Block) -> M ()
llvmTailCallBlock retto (nm, blk) = do
  tailcall <- getTailCallBlockId nm
  setCurrentBlock tailcall
  llvmDecls $ FIL.blockDecls blk
  case FIL.blockResult blk of
    FIL.Exit v -> pushTerminator $ Ret v
    FIL.Cont rs -> unless (null rs) $ do
      pushPhis retto rs
      pushTerminator $ Br retto

llvmTailCallBlocks :: BlockId -> TailCallId -> M ()
llvmTailCallBlocks retto nm = do
  tbl <- gets tailCallFILBlocks
  let m = lookup_ nm tbl
  mapM_ (llvmTailCallBlock retto) $ Map.toList m

llvmDecls :: [FIL.Decl] -> M ()
llvmDecls = mapM_ llvmDecl

data Instr
  = Call LIdent
  | Intrinsic Intrinsic
  | Equ
  | Neq
  | Add
  | Sub
  | Mul
  | Div
  | Rem
  | Gt
  | Lt
  | Gte
  | Lte
  | Shl
  | Shr
  | Or
  | And
  | Xor
  | Load
  | Index
  | Store
  | Neg
  | Alloca
  | Cast
  deriving (Show, Data)

data Intrinsic
  = Abs
  | Sqrt
  | Sin
  | Cos
  | Floor
  | Ceil
  | Truncate
  | Round
  | Memset
  | Memmove
  | Memcpy
  deriving (Show, Data, Eq)

instance Pretty Instr where
  pretty x = case x of
    Call nm -> "Call" <+> pretty nm
    _ -> pretty $ show x

lidentToInstr :: LIdent -> Instr
lidentToInstr nm = case textOf nm of
  "Prim.eq" -> Equ
  "Prim.ne" -> Neq
  "Prim.add" -> Add
  "Prim.sub" -> Sub
  "Prim.mul" -> Mul
  "Prim.div" -> Div
  "Prim.rem" -> Rem
  "Prim.gt" -> Gt
  "Prim.lt" -> Lt
  "Prim.gte" -> Gte
  "Prim.lte" -> Lte
  "Prim.shl" -> Shl
  "Prim.shr" -> Shr
  "Prim.or" -> Or
  "Prim.and" -> And
  "Prim.xor" -> Xor
  "Prim.load" -> Load
  "Prim.index" -> Index
  "Prim.store" -> Store
  "Prim.neg" -> Neg
  "Prim.alloca" -> Alloca
  "Prim.cast" -> Cast
  "Prim.abs" -> Intrinsic Abs
  "Prim.sqrt" -> Intrinsic Sqrt
  "Prim.sin" -> Intrinsic Sin
  "Prim.cos" -> Intrinsic Cos
  "Prim.floor" -> Intrinsic Floor
  "Prim.ceil" -> Intrinsic Ceil
  "Prim.truncate" -> Intrinsic Truncate
  "Prim.round" -> Intrinsic Round
  "Prim.memset" -> Intrinsic Memset
  "Prim.memmove" -> Intrinsic Memmove
  "Prim.memcpy" -> Intrinsic Memcpy
  _ -> Call nm

initPhis :: BlockId -> [Val] -> M ()
initPhis bid vs = modifyBlock bid $ \blk -> blk{ blockPhis = fmap (,mempty) vs }

llvmDecl :: FIL.Decl -> M ()
llvmDecl x = case x of
  FIL.Let rs stmt -> case stmt of
    FIL.Call nm vs -> case rs of
      [r] -> modifyCurrentBlock $ \blk -> blk{ blockStmts = Instr r (lidentToInstr nm) vs : blockStmts blk }
      _ -> unreachable001 "llvmDecl: multiple result values in call" x

    FIL.If a b c -> do
      t <- freshBlockId
      f <- freshBlockId
      pushTerminator $ IfBr a t f

      targ <- freshBlockId
      initPhis targ rs
      llvmBlock targ t b
      llvmBlock targ f c
      setCurrentBlock targ

    FIL.Switch a b cs -> do
      dflt <- freshBlockId
      alts <- sequence [ Alt sclr <$> freshBlockId | FIL.Alt sclr _ <- cs ]
      pushTerminator $ Switch a dflt alts

      targ <- freshBlockId
      initPhis targ rs
      llvmBlock targ dflt b
      sequence_ [ llvmBlock targ bid blk | (Alt _ bid, FIL.Alt _ blk) <- zip alts cs ]
      setCurrentBlock targ

    FIL.CallTailCall nm vs -> do
      llvmDecl $ FIL.TailCall nm vs

      retto <- freshBlockId
      initPhis retto rs
      llvmTailCallBlocks retto nm
      setCurrentBlock retto

  FIL.TailCall nm vs -> do
      tailcall <- getTailCallBlockId nm
      pushPhis tailcall vs
      pushTerminator $ Br tailcall

  FIL.TailRecDecls{} -> pure ()

llvmPhi :: (Val, [(Val, BlockId)]) -> Doc ann
llvmPhi (r, xs) = if
  | any ((/=) r . fst) xs -> phi
  | otherwise -> mempty
  where
    phi = llvm r <+> "= phi" <+> llvm (FIL.typeOf r) <+> hsep (punctuate comma [ brackets (llvm v <> "," <+> llvm bid) | (v, bid) <- xs ])

pushPhis :: BlockId -> [Val] -> M ()
pushPhis targ vs = do
  blkPhis <- blockPhis <$> getBlock targ
  let rslts = fmap fst blkPhis
  case [ a | a <- zip rslts vs, not $ f a ] of
    _ | length blkPhis /= length vs ->
      err101 "llvm phi length mismatch" (noPos targ) noTCHint
    [] -> do
      bid <- gets currentBlockId
      modifyBlock targ $ \blk -> blk
        { blockPhis = [ (rslt, r : rs) | ((rslt, rs), r) <- zip blkPhis (fmap (, bid) vs) ] }
    bs -> errn01 "llvm phi type mismatch" (concat [ [ (noPos (r, FIL.typeOf r)), (noPos (v, FIL.typeOf v)) ] | (r, v) <- bs ]) noTCHint
  where
    f (rslt, v) = FIL.typeOf rslt == FIL.typeOf v

getBlock :: BlockId -> M Block
getBlock bid = lookup_ bid <$> gets blocks

getCurrentBlock :: M Block
getCurrentBlock = gets currentBlockId >>= getBlock

modifyBlock :: BlockId -> (Block -> Block) -> M ()
modifyBlock bid f = do
  blk <- getBlock bid
  modify' $ \st -> st{ blocks = Map.insert bid (f blk) $ blocks st }

modifyCurrentBlock :: (Block -> Block) -> M ()
modifyCurrentBlock f = gets currentBlockId >>= flip modifyBlock f

getTailCallBlockId :: TailCallId -> M BlockId
getTailCallBlockId x = lookup_ x <$> gets tailCallBlockIds

instance LLVM BlockId where
  llvm x = "%" <> llvmBlockId x

llvmBlockId :: BlockId -> Doc ann
llvmBlockId x = "lbl_" <> pretty (unBlockId x)

instance LLVM Block where
  llvm x = vcat $ concat
      [ llvmPhi <$> blockPhis x
      , llvm <$> blockStmts x
      , [llvm $ blockTerminator x]
      ]

instance LLVM Terminator where
  llvm x = case x of
    NoTerminator -> unreachable "llvm: NoTerminator" x
    Br a -> "br" <+> llvmLabel a
    IfBr a b c -> hsep $ punctuate comma ["br" <+> llvmTyped a, llvmLabel b, llvmLabel c ]
    Ret a -> case FIL.typeOf a of
      TyUnit -> "ret" <+> llvm TyUnit
      t -> "ret" <+> llvm t <+> llvm a
    Switch a0 dflt alts -> "switch" <+> f a0 dflt <+> brackets (hsep [ f sclr lbl | Alt sclr lbl <- alts ])
      where
        f a b = llvmTyped a <> "," <+> llvmLabel b

llvmTyped :: (LLVM a, FIL.TypeOf a) => a -> Doc ann
llvmTyped x = llvm (FIL.typeOf x) <+> llvm x

llvmLabel :: BlockId -> Doc ann
llvmLabel x = "label" <+> llvm x

instance LLVM Stmt where
  llvm x = case x of
    Instr r i vs -> cmd
      where
        cmd = case FIL.typeOf r of
          TyUnit -> llvmRHS TyUnit i vs
          t -> llvm r <+> "=" <+> llvmRHS t i vs

instance LLVM LIdent where
  llvm x = "@" <> pretty x

llvmRHS :: Ty -> Instr -> [Val] -> Doc ann
llvmRHS t i vs = cmd
  where
    cmd = case i of
      Equ -> if
        | FIL.isTyFloat ta -> instr "fcmp ueq"
        | otherwise -> instr "icmp eq"
      Neq -> if
        | FIL.isTyFloat ta -> instr "fcmp une"
        | otherwise -> instr "icmp ne"
      Add -> if
        | FIL.isTyFloat ta -> instr "fadd"
        | otherwise -> instr "add"
      Sub -> if
        | FIL.isTyFloat ta -> instr "fsub"
        | otherwise -> instr "sub"
      Mul -> if
        | FIL.isTyFloat ta -> instr "fmul"
        | otherwise -> instr "mul"
      Div -> if
        | FIL.isTyFloat ta -> instr "fdiv"
        | FIL.isTyInt ta -> instr "sdiv"
        | otherwise -> instr "udiv"
      Rem -> if
        | FIL.isTyFloat ta -> instr "frem"
        | FIL.isTyInt ta -> instr "srem"
        | otherwise -> instr "urem"
      Gt -> if
        | FIL.isTyFloat ta -> instr "fcmp ugt"
        | FIL.isTyInt ta -> instr "icmp sgt"
        | otherwise -> instr "icmp ugt"
      Lt -> if
        | FIL.isTyFloat ta -> instr "fcmp ult"
        | FIL.isTyInt ta -> instr "icmp slt"
        | otherwise -> instr "icmp ult"
      Gte -> if
        | FIL.isTyFloat ta -> instr "fcmp uge"
        | FIL.isTyInt ta -> instr "icmp sge"
        | otherwise -> instr "icmp uge"
      Lte -> if
        | FIL.isTyFloat ta -> instr "fcmp ule"
        | FIL.isTyInt ta -> instr "icmp sle"
        | otherwise -> instr "icmp ule"
      Shl -> instr "shl"
      Shr -> if
        | FIL.isTyInt ta -> instr "ashr"
        | otherwise -> instr "lshr"
      Or -> instr "or"
      And -> instr "and"
      Xor -> instr "xor"
      Alloca -> "alloca" <+> llvm a
      Load -> "load" <+> llvm t <> "," <+> llvm ta <+> llvm a
      Index -> case ta of
        TyPointer t' -> "getelementptr inbounds" <+> llvm t' <> "," <+> llvm ta <+> llvm a
          <> "," <+> llvm tb <+> "0"
          <> "," <+> llvm tb <+> llvm b
        _ -> unreachable "llvmRHS: expected index to return a pointer value" t
      Store -> "store" <+> llvm tb <+> llvm b <> "," <+> llvm ta <+> llvm a

      Neg -> instr0 "fneg"
      Cast -> if
        | FIL.isTyFloat ta && FIL.isUIntTy bt -> tyinstr "fptoui"
        | FIL.isTyFloat ta && FIL.isTyInt bt -> tyinstr "fptosi"

        | FIL.isUIntTy ta && FIL.isTyFloat bt -> tyinstr "uitofp"
        | FIL.isTyInt ta && FIL.isTyFloat bt -> tyinstr "sitofp"

        | FIL.isTyPointer ta && FIL.isIntTy bt -> tyinstr "ptrtoint"
        | FIL.isIntTy ta && FIL.isTyPointer bt -> tyinstr "inttoptr"

        | FIL.bitsize ta > FIL.bitsize bt && FIL.isTyFloat ta -> tyinstr "fptrunc"
        | FIL.bitsize ta > FIL.bitsize bt -> tyinstr "trunc"

        | FIL.bitsize ta < FIL.bitsize bt && FIL.isTyFloat ta -> tyinstr "fpext"
        | FIL.bitsize ta < FIL.bitsize bt && FIL.isUIntTy ta -> tyinstr "zext"
        | FIL.bitsize ta < FIL.bitsize bt && FIL.isTyInt ta -> tyinstr "sext"

        | FIL.bitsize ta == FIL.bitsize bt -> tyinstr "bitcast"

        | otherwise -> unreachable "llvmRHS: unexpected types to 'cast'" (ta, bt)

      Intrinsic c -> "call" <+> llvm t <+> intrinsicName c t (fmap FIL.typeOf vs) <> tupled (fmap llvmTyped vs)
      Call nm -> "call" <+> llvm t <+> llvm nm <+> tupled [ llvmTyped v | v <- vs, not $ FIL.isTyUnit $ FIL.typeOf v ]
    instr s = s <+> llvm ta <+> llvm a <> "," <+> llvm b
    instr0 s = s <+> llvm t <+> llvm a
    tyinstr s = s <+> llvm ta <+> llvm a <+> "to" <+> llvm t
    ta = FIL.typeOf a
    tb = FIL.typeOf b
    bt = case b of
      Type ty -> ty
      _ -> unreachable "llvmRHS: expected type value as second argument" b
    a = case vs of
      va : _ -> va
      _ -> unreachable "llvmRHS: expected at least one argument to instruction" vs
    b = case vs of
      _ : vb : _ -> vb
      _ -> unreachable "llvmRHS: expected at least two arguments to instruction" vs

intrinsicName :: Intrinsic -> Ty -> [Ty] -> Doc ann
intrinsicName x rt ts = "@llvm." <> nm <> extra <> "." <> llvm t
  where
    extra = case x of
      Memset -> ".p0" -- BAL: why is inline not working here? (reproduce by running 'opt' on the generated llvm)
      Memmove -> ".inline.p0.p0"
      Memcpy -> ".inline.p0.p0"
      _ -> mempty
    t = case x of
      Memset -> t2
      Memmove -> t2
      Memcpy -> t2
      _ -> rt
    t2 = case ts of
      _ : _ : a : _ -> a
      _ -> unreachable "expected 3 arguments to memset/memmove/memcpy" ts
    nm = case x of
      Abs -> if
        | FIL.isTyFloat rt -> "fabs"
        | otherwise -> "abs"
      Sqrt -> "sqrt"
      Sin -> "sin"
      Cos -> "cos"
      Floor -> "floor"
      Ceil -> "ceil"
      Truncate -> "trunc"
      Round -> "round"
      Memset -> "memset"
      Memmove -> "memmove"
      Memcpy -> "memcpy"

data Terminator
  = Br BlockId
  | IfBr Val BlockId BlockId
  | Ret Val
  | Switch Val BlockId [Alt]
  | NoTerminator
  deriving (Show, Data)

data Alt = Alt Scalar BlockId
  deriving (Show, Data)

initSt :: St
initSt = St
  { currentBlockId = 0
  , nextBlockId = 0
  , blocks = mempty
  , tailCallBlockIds = mempty
  , tailCallFILBlocks = mempty
  }

type M a = StateT St IO a

instance Pretty Terminator where pretty = llvm

pushTerminator :: Terminator -> M ()
pushTerminator x = do
  blkTerm <- blockTerminator <$> getCurrentBlock
  case blkTerm of
    NoTerminator -> modifyCurrentBlock $ \blk -> blk{ blockTerminator = x }
    _ -> unreachable00n "pushTerminator" [blkTerm, x]

data Block = Block
  { blockPhis :: [(Val, [(Val, BlockId)])]
  , blockStmts :: [Stmt]
  , blockTerminator :: Terminator
  } deriving (Show, Data)

isEmptyBlock :: Block -> Bool
isEmptyBlock x = case blockTerminator x of
  NoTerminator -> null (blockPhis x) && null (blockStmts x)
  _ -> False

instance Pretty Block where
  pretty x = vlist "do" $ fmap pretty (blockPhis x) ++ fmap llvm (blockStmts x) ++ [pretty $ blockTerminator x]

setCurrentBlock :: BlockId -> M ()
setCurrentBlock bid = modify' $ \st -> st{ currentBlockId = bid }

data Stmt
  = Instr Val Instr [Val]
  deriving (Show, Data)

class LLVM a where
  llvm :: a -> Doc ann

instance LLVM Sz where
  llvm = pretty

instance LLVM Ty where
  llvm x = case x of
    TyPointer t -> llvm t <> "*"
    TyString{} -> llvm $ TyPointer $ TyChar 8
    TyChar sz -> llvm $ TyUInt sz
    TyFloat 16 -> "half"
    TyFloat 32 -> "float"
    TyFloat 64 -> "double"

    TyInt sz -> "i" <> llvm sz
    TyUInt sz -> llvm $ TyInt sz
    TyOpaque -> llvm $ TyUInt 8 -- opaque types must only be accessed through a pointer so we can pick any type here to stand in for void*
    TyEnum -> llvm $ TyUInt 32
    TyBool -> llvm $ TyUInt 1
    TyUnit -> "void"
    TyArray sz t -> "[" <+> pretty sz <+> "x" <+> llvm t <+> "]"
    _ -> unreachable "llvm: unexpected type" x

instance LLVM Val where
  llvm x = case x of
    Unit -> unreachable "llvm: unit value" x
    Type a -> llvm a
    Scalar a -> llvm a

instance LLVM Scalar where
  llvm x = case x of
    Char a -> pretty $ fromEnum a
    Float a -> pretty $ show a
    Int a -> pretty $ show a
    UInt a -> pretty $ show a
    String a -> pretty a -- this has been turned into a register...
    Bool a -> if a then "1" else "0"
    Enum _ i -> pretty i
    Undef _ -> "undef"
    Extern nm _ -> llvm nm
    Register a -> llvm a

instance LLVM RegisterId where
  llvm x = "%r" <> pretty (unRegisterId x)

instance LLVM Register where
  llvm x = llvm $ registerId x
