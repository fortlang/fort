{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}
module Fort.LLVM (llvmModules, BuildType(..))

where

import Fort.FIL (Register(..), RegisterId(..), Scalar(..), Val(..), Ty(..), TailCallId(..))
import Fort.Utils hiding (Stmt, Extern, UInt, Scalar, Unit)
import Numeric
import Fort.Type (SzFloat(..), SzUInt(..))
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
  pure (bt, vcat $ llvmDeclares nms strs blks : fmap (llvmDefine strs) (zip funcs defs))
  where
    nms = Map.keys x
    bt = if
      | "main" `elem` nms -> Exe
      | Map.null x -> NoCode
      | otherwise -> Obj

llvmDeclares :: [Text] -> [(Text, Int)] -> [Block] -> Doc ann
llvmDeclares nms strs m = vcat
  [ vcat (("declare" <+>) <$> calls nms m)
  , vcat [ globalName nm <+> "= external global" <+> llvm (unTyPointer ty) | (nm, ty) <- externs m ]
  , vcat [ llvm reg <+> "= global" <+> llvm (unTyPointer $ registerTy reg) <+> "zeroinitializer" | reg <- globals m ]
  , vcat [ "@.str." <> pretty i <+> "= private unnamed_addr constant" <+> llvmStringConst s | (s, i) <- strs ]
  ]

unTyPointer :: Ty -> Ty
unTyPointer x = case x of
  TyPointer _ t -> t
  _ -> unreachable "unTyPointer: expected global to have pointer type" x

globals :: [Block] -> [Register]
globals m = List.nubBy (\a b -> registerId a == registerId b) [ reg | Register _ reg <- universeBi m, registerIsGlobal reg ]

llvmDefine :: [(Text, Int)] -> ((Text, FIL.Func), Map BlockId Block) -> Doc ann
llvmDefine strs0 ((nm, x), blks) = do
  vcat
    [ "define" <+> llvm (FIL.retTy x) <+> globalName nm <> llvmArgs (FIL.args x) <> " {"
    , vcat [ pretty (llvmStringConstName i) <+> "=" <+> "bitcast" <+> llvmStringConstType s <> "*" <+> "@.str." <> pretty i <+> "to i8*" | (s, i) <- strs ]
    , "br label %lbl_0"
    , vcat [ nest 2 $ vsep [llvmBlockId lbl <> ":", llvm blk] | (lbl, blk) <- sortByFst $ Map.toList $ stringsToStringIds (Map.fromList strs) blks ]
    , "}"
    ]
  where
    strs = filter (flip elem (strings $ Map.elems blks) . fst) strs0

globalName :: Text -> Doc ann
globalName nm = "@" <> pretty nm

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

calls :: [Text] -> [Block] -> [Doc ann]
calls nms m = [ llvm rt <+> globalName nm <+> tupled (fmap llvm ts) | (rt, nm, ts) <- xs ]
  where
    xs = List.nubBy (\(_, a, _) (_, b, _) -> a == b) [ (FIL.typeOf r, nm, filter (not . FIL.isTyUnit) $ fmap FIL.typeOf vs) | Instr r nm vs <- universeBi m, nm `List.notElem` nms ]

strings :: [Block] -> [Text]
strings m = List.nub [ s | String _ s <- universeBi m ]

externs :: [Block] -> [(Text, Ty)]
externs m = [ (nm, ty) | Extern _ nm ty <- List.nub (universeBi m) ]

llvmArgs :: [FIL.Val] -> Doc ann
llvmArgs = tupled . fmap llvmTyped

llvmStringConstName :: Int -> Text
llvmStringConstName i = "%str_" <> Text.pack (show i)

stringsToStringIds :: Map Text Int -> Map BlockId Block -> Map BlockId Block
stringsToStringIds strs = transformBi f
  where
    f (String pos s) = String pos $ llvmStringConstName $ lookup_ s strs
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

initPhis :: BlockId -> [Val] -> M ()
initPhis bid vs = modifyBlock bid $ \blk -> blk{ blockPhis = fmap (,mempty) vs }

llvmDecl :: FIL.Decl -> M ()
llvmDecl x = case x of
  FIL.Let rs stmt -> case stmt of
    FIL.Call nm vs -> case rs of
      [r] -> modifyCurrentBlock $ \blk -> blk{ blockStmts = Instr r nm vs : blockStmts blk }
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
    _ | length blkPhis /= length vs -> case vs of
      [] -> err101 "llvm phi length mismatch" (noPos targ) noTCHint
      v : _ -> err111 "llvm phi length mismatch" v (noPos targ) noTCHint
    [] -> do
      bid <- gets currentBlockId
      modifyBlock targ $ \blk -> blk
        { blockPhis = [ (rslt, r : rs) | ((rslt, rs), r) <- zip blkPhis (fmap (, bid) vs) ] }
    bs -> errnn1 "llvm phi type mismatch" [ FIL.typeOf r | (r, _) <- bs ] [ FIL.typeOf v | (_, v) <- bs ] noTCHint
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
      TyUnit pos -> "ret" <+> llvm (TyUnit pos)
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
          TyUnit pos -> llvmRHS (TyUnit pos) i vs
          t -> llvm r <+> "=" <+> llvmRHS t i vs

llvmRHS :: Ty -> Text -> [Val] -> Doc ann
llvmRHS t nm vs = "call" <+> llvm t <+> globalName nm <+> tupled [ llvmTyped v | v <- vs, not $ FIL.isTyUnit $ FIL.typeOf v ]

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
  = Instr Val Text [Val]
  deriving (Show, Data)

class LLVM a where
  llvm :: a -> Doc ann

instance LLVM Sz where
  llvm = pretty

instance LLVM Ty where
  llvm x = case x of
    TyPointer _ t -> llvm t <> "*"
    TyString pos -> llvm $ TyPointer pos $ TyChar pos
    TyChar{} -> "i8"
    TyFloat _ F32 -> "float"
    TyFloat _ F64 -> "double"

    TyInt _ sz -> "i" <> pretty sz
    TyUInt _ sz -> "i" <> pretty sz
    TyOpaque pos -> llvm $ TyUInt pos U8 -- opaque types must only be accessed through a pointer so we can pick any type here to stand in for void*
    TyEnum pos -> llvm $ TyUInt pos U32
    TyBool{} -> "i1"
    TyUnit{} -> "void"
    TyArray _ sz t -> "[" <+> pretty sz <+> "x" <+> llvm t <+> "]"

instance LLVM Val where
  llvm x = case x of
    Unit _ -> unreachable "llvm: unit value" x
    Type _ a -> llvm a
    Scalar _ a -> llvm a

instance LLVM Scalar where
  llvm x = case x of
    Char _ a -> pretty $ fromEnum a
    Float _ a -> pretty a
    Int _ a -> pretty a
    UInt _ a -> pretty a
    String _ a -> pretty a -- this has been turned into a register...
    Bool _ a -> if a then "1" else "0"
    Enum _ _ i -> pretty i
    Undef _ _ -> "undef"
    Extern _ nm _ -> globalName nm
    Register _ a -> llvm a

instance LLVM Register where
  llvm x = if
    | registerIsGlobal x -> "@g" <> i
    | otherwise -> "%r" <> i
    where
      i = pretty (unRegisterId $ registerId x)
