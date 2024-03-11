{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}
{-# LANGUAGE PatternSynonyms #-}

module Fort.Val (module Fort.Val)

where

import Data.Int
import Data.Word
import Foreign.Ptr
import Fort.FunctorAST (pattern Char, pattern Int, pattern String)
import Fort.Type hiding (M)
import Fort.Utils
import System.Posix.DynamicLinker
import qualified Data.List.NonEmpty as NE
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

pushDecl :: VDecl -> M ()
pushDecl x = modify' $ \st -> st{ decls = x : decls st }

data OpSt = OpSt
  { prefixOps :: Map PrefixOp LIdent
  , infixOps :: Map InfixOp LIdent
  }

initOpSt :: [Decl] -> OpSt
initOpSt ds = OpSt
  { prefixOps = Map.fromList [ (op, qnToLIdent qn) | PrefixDecl _ op qn <- ds ]
  , infixOps = Map.fromList [ (op, qnToLIdent qn) | InfixDecl _ op (InfixInfo _ qn _ _) <- ds ]
  }

evalIf :: Val -> M Val -> M Val -> M Val
evalIf v t f = case v of
  VScalar _ (VBool _ True) -> t
  VScalar _ (VBool _ False) -> f
  _ -> do
    blkt <- evalBlockM t
    blkf <- evalBlockM f
    (r, [rt, rf]) <- joinVals [blockResult blkt, blockResult blkf]
    pushDecl $ VLet r $ VIf v (blkt{ blockResult = rt }) (blkf{ blockResult = rf })
    pure r

extendSum :: Map UIdent (Maybe Val) -> Map UIdent (Maybe Val) -> M (Map UIdent (Maybe Val))
extendSum bs cs =
  Map.union bs . Map.fromList <$> sequence [ (k, ) <$> f mv | (k, mv) <- Map.toList cs, not (k `Map.member` bs) ]
  where
    f Nothing = pure Nothing
    f (Just v) = Just <$> freshVal (typeOf v)

joinSumDataVals :: (Val -> Val -> M Val) -> Maybe Val -> Maybe Val -> M (Maybe Val)
joinSumDataVals f mx my = case (mx, my) of
  (Nothing, Nothing) -> pure Nothing
  (Just a, Just b) -> Just <$> f a b
  _ -> unreachable00n "unable to join sum data vals" [mx, my]

templateOfSumDataVals :: Maybe Val -> Maybe Val -> M (Maybe Val)
templateOfSumDataVals = joinSumDataVals templateOfVals

templateOfVals :: Val -> Val -> M Val
templateOfVals x y = case (x, y) of
  (XVNone{}, _) -> pure y
  (_, XVNone{}) -> pure x
  _ | compareVals x y == IsEqual -> pure x
  (VRecord pos bs, VRecord _ cs) -> VRecord pos <$> intersectionWithM templateOfVals bs cs
  (VArray pos t bs, VArray _ _ cs) | NE.length bs == NE.length cs -> VArray pos t . NE.fromList <$> zipWithM templateOfVals (toList bs) (toList cs)
  (VTuple pos bs, VTuple _ cs) | length2 bs == length2 cs -> VTuple pos . fromList2 <$> zipWithM templateOfVals (toList bs) (toList cs)
  (VSum pos mb bs, VSum _ mc cs) -> do
    bs' <- extendSum bs cs
    cs' <- extendSum cs bs
    VSum pos <$> templateOfVals mb mc <*> unionWithM templateOfSumDataVals bs' cs'
  (VPtr pos t a, VPtr _ _ b) -> VPtr pos t <$> templateOfVals a b
  (VIndexed pos t sz a, VIndexed _ _ _ b) -> VIndexed pos t sz <$> templateOfVals a b
  -- otherwise x and y are either scalars or registers
  -- (assuming the type checker hasn't been disabled)
  _ | isRegisterVal x && isRegisterVal y -> VScalar posx . XVFreshRegVal posx <$> case (typeOf x, typeOf y) of
    (TyEnum p a, TyEnum _ b) -> pure $ TyEnum p $ Set.union a b
    (tx, ty) | tx == ty -> pure tx
    _ -> err111 "unable to create template for register values" x y noTCHint
  _ -> err111 "unable to create template for values" x y noTCHint
  where
    posx = positionOf x

data Comparison
  = IsEqual
  | IsNotEqual
  | IsUnknown
  deriving (Show, Eq)

compareVals :: Val -> Val -> Comparison
compareVals x y = case (x, y) of
  (VArray _ a bs, VArray _ c ds) | length bs == length ds ->
    joinComparisons (compareEq a c : zipWith compareVals (toList bs) (toList ds))
  (VRecord _ m, VRecord _ n) | isEqualByKeys m n -> joinComparisons $ Map.elems $ Map.intersectionWith compareVals m n
  (VSum _ a m, VSum _ b n) | isEqualByKeys m n ->
    joinComparisons (compareVals a b : Map.elems (Map.intersectionWith compareSumVals m n))
  (VTuple _ bs, VTuple _ cs) | length bs == length cs ->
    joinComparisons (fmap (uncurry compareVals) $ zip (toList bs) (toList cs))
  (VIndexed _ a b c, VIndexed _ d e f) ->
    joinComparisons [compareEq a d, compareEq b e, compareVals c f]
  (VPtr _ a b, VPtr _ c d) -> joinComparisons [compareEq a c, compareVals b d]
  (VUnit _, VUnit _) -> IsEqual
  (VScalar _ a,  VScalar _ b) -> compareScalars a b
  _ -> IsUnknown

compareSumVals :: Maybe Val -> Maybe Val -> Comparison
compareSumVals x y = case (x, y) of
  (Nothing, Nothing) -> IsEqual
  (Just a, Just b) -> compareVals a b
  _ -> IsUnknown

compareEq :: Eq a => a -> a -> Comparison
compareEq x y = if x == y then IsEqual else IsNotEqual

joinComparisons :: [Comparison] -> Comparison
joinComparisons xs = if
  | all (== IsEqual) xs -> IsEqual
  | all (== IsNotEqual) xs -> IsNotEqual
  | otherwise -> IsUnknown

compareScalars :: VScalar -> VScalar -> Comparison
compareScalars x y = case (x, y) of
    (VString _ a, VString _ b) -> compareEq a b
    (VChar _ a, VChar _ b) -> compareEq a b
    (VFloat _ a, VFloat _ b) -> compareEq a b
    (VInt _ a, VInt _ b) -> compareEq a b
    (VUInt _ a, VUInt _ b) -> compareEq a b
    (VBool _ a, VBool _ b) -> compareEq a b
    (VEnum _ a b, VEnum _ c d) -> joinComparisons [ compareEq a c, compareEq b d ]
    (VUndef _ a, VUndef _ b) -> compareEq a b
    (VExtern _ a ta, VExtern _ b tb) -> joinComparisons [compareEq a b, compareEq ta tb]
    (VRegister _ a, VRegister _ b) -> compareEq (registerId a) (registerId b)
    _ -> IsUnknown

instantiateWithFreshRegs :: VScalar -> M VScalar
instantiateWithFreshRegs x = case x of
  XVFreshRegVal _ t -> freshRegisterScalar t
  _ -> pure x

instantiateWithUndef :: VScalar -> VScalar
instantiateWithUndef x = case x of
  XVFreshRegVal pos t -> VUndef pos t
  _ -> x

unionVals :: Val -> Val -> M Val -- left biased union
unionVals x y = case (x, y) of
  (VRecord pos bs, VRecord _ cs) -> VRecord pos <$> intersectionWithM unionVals bs cs
  (VArray pos t bs, VArray _ _ cs) | NE.length bs == NE.length cs -> VArray pos t . NE.fromList <$> zipWithM unionVals (toList bs) (toList cs)
  (VTuple pos bs, VTuple _ cs) | length2 bs == length2 cs -> VTuple pos . fromList2 <$> zipWithM unionVals (toList bs) (toList cs)
  (VSum pos k bs, VSum _ l cs) -> VSum pos <$> unionVals k l <*> unionWithM (joinSumDataVals unionVals) bs cs
  (VPtr pos t a, VPtr _ _ b) -> VPtr pos t <$> unionVals a b
  (VIndexed pos t sz a, VIndexed _ _ _ b) -> VIndexed pos t sz <$> unionVals a b
  (XVNone{}, _) -> pure x -- BAL: should this be pure y?
  (VUnit{}, _) -> pure x
  _ | isRegisterVal x -> pure x
  _ -> unreachable110 "unable to union values" x y

joinVals :: [Val] -> M (Val, [Val])
joinVals vs = do
  rval <- foldM templateOfVals (XVNone pos) vs
  vs' <- sequence [ unionVals v rval | v <- vs ]
  (, ) <$> transformBiM instantiateWithFreshRegs rval <*> pure (fmap (transformBi instantiateWithUndef) vs')
  where
    pos = case vs of
      v : _ -> positionOf v
      _ -> noPosition

evalBlockM :: M Val -> M Block
evalBlockM m = do
  ss0 <- gets decls
  modify' $ \st -> st{ decls = [] }
  val <- m
  ss <- gets decls
  modify' $ \st -> st{ decls = ss0 }
  pure $ Block
    { blockDecls = reverse ss
    , blockResult = val
    , blockTailCalls = mempty
    }

evalCon :: UIdent -> M VScalar
evalCon c = do
  tbl <- gets tags
  i <- case Map.lookup c tbl of
    Just i -> pure i
    Nothing -> do
      i <- gets nextTagId
      modify' $ \st -> st{ nextTagId = i + 1, tags = Map.insert c i $ tags st }
      pure i
  pure $ VEnum (positionOf c) c i

freshRegister :: Bool -> Ty -> M Register
freshRegister isGlobal t = if
  | isRegisterTy t -> do
    i <- gets nextRegisterId
    let r = Register{ registerIsGlobal = isGlobal, registerTy = t, registerId = i }
    modify' $ \st -> st{ nextRegisterId = i + 1 }
    pure r
  | otherwise -> unreachable101 "unable to create register of type" t noTCHint

freshRegisterScalar ::Ty -> M VScalar
freshRegisterScalar t = VRegister (positionOf t) <$> freshRegister False t

freshRegisterVal :: Ty -> M Val
freshRegisterVal t = VScalar (positionOf t) <$> freshRegisterScalar t

freshGlobalScalar ::Ty -> M VScalar
freshGlobalScalar t = VRegister (positionOf t) <$> freshRegister True t

freshGlobalVal :: Ty -> M Val
freshGlobalVal t = VScalar (positionOf t) <$> freshGlobalScalar t

freshVal :: Ty -> M Val
freshVal = freshValF id

freshValF :: (Ty -> Ty) -> Ty -> M Val
freshValF f x = case x of
  TyRecord pos m -> VRecord pos <$> mapM go m
  TySum pos m -> VSum pos <$> freshRegisterVal (f $ mkTyEnum pos $ Map.keys m) <*> mapM (mapM go) m
  TyTuple pos ts -> VTuple pos <$> mapM go ts
  TyUnit pos -> pure $ VUnit pos
  _ | isRegisterTy x -> freshRegisterVal $ f x -- needs to be above TyPointer
  TyPointer pos t -> VPtr pos x <$> freshValF (TyPointer pos) t
  TyArray pos sz t -> VIndexed pos x sz <$> freshValF (f . TyArray pos sz) t
  _ -> unreachable100 "unable to generate fresh value" x
  where
    go = freshValF f

type Env = Map LIdent Val

type M a = StateT St (StateT TCSt (StateT OpSt (StateT TySt IO))) a

mkTyEnum :: Position -> [UIdent] -> Ty
mkTyEnum pos = TyEnum pos . Set.fromList

type Prog = Map Text Func

data Func = Func{ retTy :: Ty, arg :: Val, body :: Block }
  deriving (Show, Data)

instance Pretty Func where
  pretty x = "func" <+> pretty (arg x) <+> "->" <+> pretty (retTy x) <+> "=" <+> pretty (body x)

data TailCallId = TailCallId{ tailCallId :: Integer, tailCallName :: LIdent }
  deriving (Show, Data)

instance Ord TailCallId where
  compare x y = tailCallId x `compare` tailCallId y

instance Eq TailCallId where
  x == y = tailCallId x == tailCallId y

data St = St
  { nextTagId :: TagId
  , tags :: Map UIdent TagId
  , nextRegisterId :: RegisterId
  , decls :: [VDecl]
  , tailcalls :: [(TailCallId, Val)]
  , calls :: Map Text (Val -> M Val)
  , nextTailCallId :: Integer
  , isSlowSafeBuild :: Bool
  , buildCmd :: [Text]
  , isPure :: Bool
  , mDynLib :: Maybe DL
  }

initSt :: Bool -> St
initSt b = St
  { nextTagId = 0
  , tags = mempty
  , nextRegisterId = 0
  , decls = mempty
  , tailcalls = mempty
  , calls = mempty
  , nextTailCallId = 0
  , isSlowSafeBuild = b
  , buildCmd = mempty
  , isPure = False
  , mDynLib = Nothing
  }

data Val
  -- these should be eliminated during evalType
  = XVLam Position Env Binding Exp -- at the end of eval all lambdas have been eliminated
  | XVDelay Position Env Exp -- think of this as a rewrite from v to \() -> v so it won't evaluate immediately and can be used repeatedly (i.e. to repeat side-effecting calls)
  | XVTailRecDecls Position Env (Map LIdent TailRecDecl) LIdent
  | XVTailCall Position TailCallId
  | XVCall Position Text
  | XVNone Position -- for tail calls
  -- at then end, only these remain
  | VType Position Ty
  -- constructed values
  | VArray Position Ty (NonEmpty Val)
  | VRecord Position (Map LIdent Val)
  | VSum Position Val (Map UIdent (Maybe Val))
  | VTuple Position (NonEmpty2 Val)
  | VIndexed Position Ty Sz Val
  | VPtr Position Ty Val
  | VUnit Position
  | VScalar Position VScalar
  deriving (Show, Data)

instance Positioned Val where
  positionOf x = case x of
    XVLam pos _ _ _ -> pos
    XVDelay pos _ _ -> pos
    XVTailRecDecls pos _ _ _ -> pos
    XVTailCall pos _ -> pos
    XVCall pos _ -> pos
    XVNone pos -> pos
    VType pos _ -> pos
    VArray pos _ _ -> pos
    VRecord pos _ -> pos
    VSum pos _ _ -> pos
    VTuple pos _ -> pos
    VIndexed pos _ _ _ -> pos
    VPtr pos _ _ -> pos
    VUnit pos -> pos
    VScalar pos _ -> pos

isNone :: Val -> Bool
isNone x = case x of
  XVNone{} -> True
  _ -> False

data VScalar
  = XVFreshRegVal Position Ty
  -- ^ removed
  | VString Position Text
  | VChar Position Char
  | VFloat Position VFloat
  | VInt Position VInt
  | VUInt Position VUInt
  | VBool Position Bool
  | VEnum Position UIdent Integer
  | VUndef Position Ty
  | VExtern Position Text Ty
  | VRegister Position Register
  | VPointer Position Ty (Ptr ())
  deriving (Show, Data)

data VFloat
  = VFloat32 Float
  | VFloat64 Double
  deriving (Show, Data, Eq)

data VUInt
  = VUInt8 Word8
  | VUInt16 Word16
  | VUInt32 Word32
  | VUInt64 Word64
  deriving (Show, Data, Eq)

data VInt
  = VInt8 Int8
  | VInt16 Int16
  | VInt32 Int32
  | VInt64 Int64
  deriving (Show, Data, Eq)

instance Pretty VFloat where
  pretty x = case x of
    VFloat32 a -> pretty a
    VFloat64 a -> pretty a

instance Pretty VInt where
  pretty x = case x of
    VInt8 a -> pretty a
    VInt16 a -> pretty a
    VInt32 a -> pretty a
    VInt64 a -> pretty a

instance Pretty VUInt where
  pretty x = case x of
    VUInt8 a -> pretty a
    VUInt16 a -> pretty a
    VUInt32 a -> pretty a
    VUInt64 a -> pretty a

instance Positioned VScalar where
  positionOf x = case x of
    XVFreshRegVal pos _ -> pos
    VString pos _ -> pos
    VChar pos _ -> pos
    VFloat pos _ -> pos
    VInt pos _ -> pos
    VUInt pos _ -> pos
    VBool pos _ -> pos
    VEnum pos _ _ -> pos
    VUndef pos _ -> pos
    VExtern pos _ _ -> pos
    VRegister pos _ -> pos
    VPointer pos _ _ -> pos

data VStmt
  = VCall Text Val
  | VSwitch Val Block [Alt]
  | VIf Val Block Block
  | VCallTailCall TailCallId Val
  deriving (Show, Data)

data VDecl
  = VLet Val VStmt
  | VTailRecDecls TailCallId (Map TailCallId (Val, Block))
  | VTailCall TailCallId Val
  deriving (Show, Data)

data Block = Block
  { blockDecls :: [VDecl]
  , blockTailCalls :: [(TailCallId, Val)]
  , blockResult :: Val
  } deriving (Show, Data)

data Alt -- BAL: remove?
  = AltScalar VScalar Block
  | AltDefault Block
  deriving (Show, Data)

instance Pretty Alt where
  pretty x = case x of
    AltScalar a b -> "alt" <+> pretty a <+> "->" <+> pretty b
    AltDefault b -> "alt-default" <+> "->" <+> pretty b

instance Pretty VDecl where
  pretty x = case x of
    VTailRecDecls _ m -> "tailrec" <+> vlist ""
      [ pretty a <+> "= \\" <+> pretty b <+> "->" <+> pretty c | (a, (b, c)) <- Map.toList m ]
    VLet a b -> case a of
      VUnit _ -> pretty b
      _ -> pretty a <+> "=" <+> pretty b
    VTailCall a b -> "tailcall" <+> pretty a <+> pretty b

instance Pretty TailCallId where
  pretty x = pretty (tailCallName x) <> "." <> pretty (tailCallId x)

instance Pretty VStmt where
  pretty x = case x of
    VIf a b c -> "if" <+> nest 2 (vcat [ pretty a, "then" <+> pretty b, "else" <+> pretty c ])
    VCall a b -> "call" <+> pretty a <+> pretty b
    VCallTailCall a b -> "call" <+> pretty a <+> pretty b
    VSwitch a b alts -> "switch" <+> pretty a <+> vlist "of" (fmap pretty (alts ++ [AltDefault b]))

instance Pretty Block where
  pretty x = vlist "do" $ fmap pretty (blockDecls x) ++ [pretty (blockResult x)]

type TagId = Integer

newtype RegisterId = RegisterId{ unRegisterId :: Int }
  deriving (Show, Eq, Ord, Num, Data)

instance Pretty RegisterId where
  pretty = pretty . unRegisterId

data Register = Register{ registerIsGlobal :: Bool, registerTy :: Ty, registerId :: RegisterId } deriving (Show, Data)

instance Typed Register where
  typeOf = registerTy

instance Pretty Register where
  pretty x = d <> pretty (registerId x) <+> ":" <+> pretty (typeOf x)
    where
      d = if registerIsGlobal x then "@" else "%"

instance Pretty Val where
  pretty x = case x of
    XVLam{} -> "<lambda>"
    XVDelay{} -> "<delay>"
    XVTailRecDecls _ _ m n -> "<tailrecdecls ="<+> pretty n <+> pretty m <> ">"
    XVTailCall{} -> "<tailcall>"
    XVNone{} -> "<no value>"
    XVCall _ v -> "<call" <+> pretty v <> ">"
    VRecord _ m -> "record" <+> pretty m
    VSum _ con m -> vlist "sum" [ "Tag:" <+> pretty con, "UNION:" <+> pretty m ]
    VType _ t -> "`" <> pretty t <> "`"
    VArray _ _ vs -> nelist $ fmap pretty vs
    VTuple _ vs -> tupled2 $ fmap pretty vs
    VUnit _ -> "()"
    VScalar _ a -> pretty a
    VPtr _ _ a -> "<ptr = " <> pretty a <> ">"
    VIndexed _ _ sz a -> "<indexed = " <> pretty sz <+> pretty a <> ">"

instance Pretty VScalar where
  pretty x = case x of
    VString _ a -> pretty $ show a
    VChar _ a -> pretty $ show a
    VFloat _ a -> pretty a
    VInt _ a -> pretty a
    VUInt _ a -> pretty a
    VBool _ a -> pretty a
    VUndef _ t -> "<undef:" <+> pretty t <> ">"
    VEnum _ a _ -> "tag" <+> pretty a
    VExtern _ nm _ -> "<extern" <+> pretty nm <+> ">"
    VRegister _ r -> pretty r
    XVFreshRegVal _ t -> "<freshreg :" <+> pretty t <+> ">"
    VPointer _ _ p -> "<pointer:" <+> pretty (p `minusPtr` nullPtr) <+> ">"

instance Typed Val where
  typeOf x = case x of
    VRecord pos m -> TyRecord pos $ fmap typeOf m
    VSum pos _ m -> TySum pos $ fmap (fmap typeOf) m
    VTuple pos vs -> TyTuple pos $ fmap typeOf vs
    VUnit pos -> TyUnit pos
    VType pos t -> TyType pos t
    VArray _ t _ -> t
    VPtr _ t _ -> t
    VIndexed _ t _ _ -> t
    VScalar _ a -> typeOf a
    _ -> unreachable "unable to take type of value" x

intSz :: VInt -> SzInt
intSz i = case i of
  VInt8 _ -> I8
  VInt16 _ -> I16
  VInt32 _ -> I32
  VInt64 _ -> I64

uintSz :: VUInt -> SzUInt
uintSz i = case i of
  VUInt8 _ -> U8
  VUInt16 _ -> U16
  VUInt32 _ -> U32
  VUInt64 _ -> U64

floatSz :: VFloat -> SzFloat
floatSz i = case i of
  VFloat32 _ -> F32
  VFloat64 _ -> F64 

instance Typed VScalar where
  typeOf x = case x of
    VString pos _ -> TyString pos
    VChar pos _ -> TyChar pos
    VFloat pos a -> TyFloat pos $ floatSz a
    VInt pos a -> TyInt pos $ intSz a
    VUInt pos a -> TyUInt pos $ uintSz a
    VBool pos _ -> TyBool pos
    VEnum pos c _ -> mkTyEnum pos [c]
    VRegister _ r -> typeOf r
    VExtern _ _ t -> t
    VUndef _ t -> t
    VPointer _ t _ -> t
    XVFreshRegVal _ t -> t

scalarToVScalar :: Scalar -> VScalar
scalarToVScalar x = case x of
  Char pos t -> VChar pos $ read $ Text.unpack t
  String pos v -> VString pos v

  Double pos v -> VFloat pos $ VFloat64 v
  Int pos i -> VInt pos $ VInt32 $ fromInteger i
  UInt pos i -> VUInt pos $ VUInt32 $ fromInteger i 

  ATrue pos -> VBool pos True
  AFalse pos -> VBool pos False

isRegisterVal :: Val -> Bool
isRegisterVal = isRegisterTy . typeOf

flattenVTuple :: Val -> [Val]
flattenVTuple x = case x of
  VTuple _ vs -> toList vs
  _ -> [x]

flattenVal :: Val -> Maybe Val
flattenVal x = case x of
  VRecord _ m -> f $ fmap snd $ sortByFst $ Map.toList m
  VSum _ k m -> f (k : fmap snd (sortByFst [ (con, v) | (con, Just v) <- Map.toList m ]))
  VArray _ _ vs -> f $ toList vs
  VTuple _ vs | all isFlatVal vs -> Nothing
  VTuple _ vs -> f $ concatMap flattenVTuple vs
  VPtr _ _ a -> Just a
  VIndexed _ _ _ a -> Just a
  _ | isFlatVal x -> Nothing
  _ -> unreachable "unable to flatten value" x
  where
    f = Just . mkVTuple
    isFlatVal v = case v of
      VType{} -> True
      VUnit{} -> True
      VScalar{} -> True
      XVNone{} -> True
      _ -> False

mkVTuple :: [Val] -> Val
mkVTuple xs = case xs of
  [] -> unreachable "empty tuple" ()
  [x] -> x
  x : y : rest -> VTuple (positionOf x) (cons2 x (y :| rest))

isSwitchVal :: Val -> Bool
isSwitchVal = isSwitchTy . typeOf

isValEnum :: Val -> Bool
isValEnum = isTyEnum . typeOf

isTyEnum :: Ty -> Bool
isTyEnum TyEnum{} = True
isTyEnum x = unreachable "expected enum type in sum constructore value" x

lookupField :: (Ord b, MonadIO m, Positioned b, Positioned c, Pretty b, Pretty c, Pretty a) => c -> b -> Map b a -> m a
lookupField a fld m = case Map.lookup fld m of
  Nothing -> err111 "missing field in 'select' expression" fld a m
  Just v -> pure v

switchValOf :: Val -> M Val
switchValOf x = case x of
  VSum _ c _ | isSwitchVal c -> pure c
  VScalar{} | isSwitchVal x -> pure x
  _ -> err101 "unexpected switch value in 'case' expression" x noTCHint

switch :: Val -> [(VScalar, Block)] -> Block -> M Val
switch val alts dflt = do
  tg <- switchValOf val

  (r, rdflt : ralts) <- joinVals $ blockResult dflt : fmap (blockResult . snd) alts
  pushDecl $ VLet r $ VSwitch tg (dflt{ blockResult = rdflt }) [ AltScalar a b{ blockResult = rb } | (rb, (a, b)) <- zip ralts alts ]
  pure r



