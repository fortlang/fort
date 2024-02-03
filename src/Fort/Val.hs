{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}
module Fort.Val (module Fort.Val)

where

import Fort.Type hiding (M)
import Fort.Utils
import qualified Data.Map as Map
import qualified Data.Set as Set

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

evalIf :: Val -> Block -> Block -> M Val
evalIf v blkt blkf = do
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
  (XVNone, _) -> pure y
  (_, XVNone) -> pure x
  _ | x == y -> pure x
  (VRecord bs, VRecord cs) -> VRecord <$> intersectionWithM templateOfVals bs cs
  (VArray t bs, VArray _ cs) | length bs == length cs -> VArray t <$> zipWithM templateOfVals bs cs
  (VTuple bs, VTuple cs) | length bs == length cs -> VTuple <$> zipWithM templateOfVals bs cs
  (VSum mb bs, VSum mc cs) -> do
    bs' <- extendSum bs cs
    cs' <- extendSum cs bs
    VSum <$> templateOfVals mb mc <*> unionWithM templateOfSumDataVals bs' cs'
  (VPtr t a, VPtr _ b) -> VPtr t <$> templateOfVals a b
  (VIndexed t sz a, VIndexed _ _ b) -> VIndexed t sz <$> templateOfVals a b
  -- otherwise x and y are either scalars or registers
  -- (assuming the type checker hasn't been disabled)
  _ -> VScalar . XVFreshRegVal <$> case (typeOf x, typeOf y) of
    (TyEnum a, TyEnum b) -> pure $ TyEnum $ Set.union a b
    (tx, ty)
      | isRegisterTy tx && tx == ty -> pure tx
      | otherwise -> err101 "unable to create template for values" (noPos (tx, ty)) noTCHint

instantiateWithFreshRegs :: VScalar -> M VScalar
instantiateWithFreshRegs x = case x of
  XVFreshRegVal t -> freshRegisterScalar t
  _ -> pure x

instantiateWithUndef :: VScalar -> VScalar
instantiateWithUndef x = case x of
  XVFreshRegVal t -> VUndef t
  _ -> x

unionVals :: Val -> Val -> M Val -- left biased union
unionVals x y = case (x, y) of
  (VRecord bs, VRecord cs) -> VRecord <$> intersectionWithM unionVals bs cs
  (VArray t bs, VArray _ cs) | length bs == length cs -> VArray t <$> zipWithM unionVals bs cs
  (VTuple bs, VTuple cs) | length bs == length cs -> VTuple <$> zipWithM unionVals bs cs
  (VSum k bs, VSum l cs) -> VSum <$> unionVals k l <*> unionWithM (joinSumDataVals unionVals) bs cs
  (VPtr t a, VPtr _ b) -> VPtr t <$> unionVals a b
  (VIndexed t sz a, VIndexed _ _ b) -> VIndexed t sz <$> unionVals a b
  (XVNone, _) -> pure XVNone
  (VUnit, _) -> pure VUnit
  _ | isRegisterVal x -> pure x
  _ -> unreachable100 "unable to union values" (noPos (x, y))

joinVals :: [Val] -> M (Val, [Val])
joinVals vs = do
  rval <- foldM templateOfVals XVNone vs
  vs' <- sequence [ unionVals v rval | v <- vs ]
  (, ) <$> transformBiM instantiateWithFreshRegs rval <*> pure (fmap (transformBi instantiateWithUndef) vs')

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
  pure $ VEnum c i

freshRegister :: Ty -> M Register
freshRegister t = if
  | isRegisterTy t -> do
    i <- gets nextRegisterId
    let r = Register{ registerTy = t, registerId = i }
    modify' $ \st -> st{ nextRegisterId = i + 1 }
    pure r
  | otherwise -> unreachable101 "unable to create register of type" (noPos t) noTCHint

freshRegisterScalar :: Ty -> M VScalar
freshRegisterScalar t = VRegister <$> freshRegister t

freshRegisterVal :: Ty -> M Val
freshRegisterVal t = VScalar <$> freshRegisterScalar t

freshVal :: Ty -> M Val
freshVal = freshValF id

freshValF :: (Ty -> Ty) -> Ty -> M Val
freshValF f x = case x of
  TyRecord m -> VRecord <$> mapM go m
  TySum m -> VSum <$> freshRegisterVal (f $ mkTyEnum $ Map.keys m) <*> mapM (mapM go) m
  TyTuple ts -> VTuple <$> mapM go ts
  TyUnit -> pure VUnit
  _ | isRegisterTy x -> freshRegisterVal $ f x -- needs to be above TyPointer
  TyPointer t -> VPtr x <$> freshValF TyPointer t
  TyArray sz t -> VIndexed x sz <$> freshValF (f . TyArray sz) t
  _ -> unreachable100 "unable to generate fresh value" (noPos x)
  where
    go = freshValF f

type Env = Map LIdent Val

type M a = StateT St (StateT TCSt (StateT OpSt (StateT TySt IO))) a

mkTyEnum :: [UIdent] -> Ty
mkTyEnum = TyEnum . Set.fromList

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
  , calls :: Map LIdent (Val -> M Val)
  , nextTailCallId :: Integer
  , isSlowSafeBuild :: Bool
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
  }

data Val
  -- these should be eliminated during evalType
  = XVLam Env [Binding] Exp -- at the end of eval all lambdas have been eliminated
  | XVDelay Env Exp -- think of this as a rewrite from v to \() -> v so it won't evaluate immediately and can be used repeatedly (i.e. to repeat side-effecting calls)
  | XVTailRecDecls Env (Map LIdent TailRecDecl) LIdent
  | XVTailCall TailCallId
  | XVCall LIdent
  | XVNone -- for tail calls
  -- at then end, only these remain
  | VType Ty
  -- constructed values
  | VArray Ty [Val]
  | VRecord (Map LIdent Val)
  | VSum Val (Map UIdent (Maybe Val))
  | VTuple [Val] -- 2 or more
  | VIndexed Ty Sz Val
  | VPtr Ty Val
  | VUnit
  | VScalar VScalar
  deriving (Show, Eq, Data)

isNone :: Val -> Bool
isNone x = case x of
  XVNone -> True
  _ -> False

data VScalar
  = XVFreshRegVal Ty
  -- ^ removed
  | VString Text
  | VChar Char
  | VFloat Double
  | VInt Integer
  | VUInt Integer
  | VBool Bool
  | VEnum UIdent Integer
  | VUndef Ty
  | VExtern LIdent Ty
  | VRegister Register
  deriving (Show, Eq, Data)

data VStmt
  = VCall LIdent Val
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

data Alt
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
      VUnit -> pretty b
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

newtype RegisterId = RegisterId{ unRegisterId :: Int } deriving (Show, Eq, Ord, Num, Data)

instance Pretty RegisterId where
  pretty x = "%r" <> pretty (unRegisterId x)

data Register = Register{ registerTy :: Ty, registerId :: RegisterId } deriving (Show, Eq, Data)

instance Typed Register where
  typeOf = registerTy

instance Pretty Register where
  pretty x = pretty (registerId x) <+> ":" <+> pretty (typeOf x)

instance Pretty Val where
  pretty x = case x of
    XVLam{} -> "<lambda>"
    XVDelay{} -> "<delay>"
    XVTailRecDecls{} -> "<tailrecdecls>"
    XVTailCall{} -> "<tailcall>"
    XVNone -> "<no value>"
    XVCall v -> "<call" <+> pretty v <> ">"
    VRecord m -> "record" <+> pretty m
    VSum con m -> vlist "sum" [ "Tag:" <+> pretty con, "UNION:" <+> pretty m ]
    VType t -> "`" <> pretty t <> "`"
    VArray _ vs -> list $ fmap pretty vs
    VTuple vs -> tupled $ fmap pretty vs
    VUnit -> "()"
    VScalar a -> pretty a
    VPtr _ a -> "<ptr = " <> pretty a <> ">"
    VIndexed _ sz a -> "<indexed = " <> pretty sz <+> pretty a <> ">"

instance Pretty VScalar where
  pretty x = case x of
    VString a -> pretty $ show a
    VChar a -> pretty $ show a
    VFloat a -> pretty a
    VInt a -> pretty a
    VUInt a -> pretty a
    VBool a -> pretty a
    VUndef t -> "<undef :" <+> pretty t <> ">"
    VEnum a _ -> "tag" <+> pretty a
    VExtern nm _ -> "<extern" <+> pretty nm <+> ">"
    VRegister r -> pretty r
    XVFreshRegVal t -> "<freshreg :" <+> pretty t <+> ">"

instance Typed Val where
  typeOf x = case x of
    VRecord m -> TyRecord $ fmap typeOf m
    VSum _ m -> TySum $ fmap (fmap typeOf) m
    VTuple vs -> TyTuple $ fmap typeOf vs
    VUnit -> TyUnit
    VArray t _ -> t
    VPtr t _ -> t
    VIndexed t _ _ -> t
    VScalar a -> typeOf a
    VType t -> TyType t
    _ -> unreachable "unable to take type of value" x

instance Typed VScalar where
  typeOf x = case x of
    VString _ -> TyString
    VChar _ -> TyChar 8
    VFloat _ -> TyFloat 64
    VInt _ -> TyInt 32
    VUInt _ -> TyUInt 32
    VBool _ -> TyBool
    VEnum c _ -> mkTyEnum [c]
    VExtern _ t -> t
    VUndef t -> t
    VRegister r -> typeOf r
    XVFreshRegVal t -> t

scalarToVScalar :: Scalar -> VScalar
scalarToVScalar x = case x of
  Char _ v -> VChar $ valOf v
  Double _ v -> VFloat $ valOf v
  Int _ v -> VInt $ valOf v
  String _ v -> VString $ valOf v
  UInt _ v -> case v of
    Dec{} -> VInt $ valOf v
    _ -> VUInt $ valOf v
  ATrue _ -> VBool True
  AFalse _ -> VBool False

isRegisterVal :: Val -> Bool
isRegisterVal = isRegisterTy . typeOf

flattenVTuple :: Val -> [Val]
flattenVTuple x = case x of
  VTuple vs -> vs
  _ -> [x]

flattenVal :: Val -> Maybe Val
flattenVal x = case x of
  VRecord m -> f $ fmap snd $ sortByFst $ Map.toList m
  VSum k m -> f (k : fmap snd (sortByFst [ (con, v) | (con, Just v) <- Map.toList m ]))
  VArray _ vs -> f vs
  VTuple vs | all isFlatVal vs -> Nothing
  VTuple vs -> f $ concatMap flattenVTuple vs
  VPtr _ a -> Just a
  VIndexed _ _ a -> Just a
  _ | isFlatVal x -> Nothing
  _ -> unreachable "unable to flatten value" x
  where
    f = Just . mkVTuple
    isFlatVal v = case v of
      VType _ -> True
      VUnit -> True
      VScalar{} -> True
      XVNone -> True
      _ -> False

mkVTuple :: [Val] -> Val
mkVTuple xs = case xs of
  [x] -> x
  _ -> VTuple xs

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


