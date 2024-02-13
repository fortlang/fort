{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}
{-# LANGUAGE PatternSynonyms #-}

module Fort.Val (module Fort.Val)

where

import Fort.Type hiding (M)
import Fort.Utils
import Fort.FunctorAST (pattern Char, pattern Int, pattern String)
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
  (XVNone{}, _) -> pure y
  (_, XVNone{}) -> pure x
  _ | x == y -> pure x
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

instance Eq Val where
  x == y = case (x, y) of
    (VArray _ a bs, VArray _ c ds) -> a == c && bs == ds
    (VRecord _ m, VRecord _ n) -> m == n
    (VSum _ a m, VSum _ b n) -> a == b && m == n
    (VTuple _ bs, VTuple _ cs) -> bs == cs
    (VIndexed _ a b c, VIndexed _ d e f) -> a == d && b == e && c == f
    (VPtr _ a b, VPtr _ c d) -> a == c && b == d
    (VUnit _, VUnit _) -> True
    (VScalar _ a,  VScalar _ b) -> a == b
    _ -> False

instance Eq VScalar where
  x == y = case (x, y) of
    (VString _ a, VString _ b) -> a == b
    (VChar _ a, VChar _ b) -> a == b
    (VFloat _ a, VFloat _ b) -> a == b
    (VInt _ a, VInt _ b) -> a == b
    (VUInt _ a, VUInt _ b) -> a == b
    (VBool _ a, VBool _ b) -> a == b
    (VEnum _ a b, VEnum _ c d) -> a == c && b == d
    (VUndef _ a, VUndef _ b) -> a == b
    (VExtern _ a ta, VExtern _ b tb) -> a == b && ta == tb
    (VRegister _ a, VRegister _ b) -> registerId a == registerId b
    _ -> False

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
  (XVNone{}, _) -> pure x
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

freshRegister :: Ty -> M Register
freshRegister t = if
  | isRegisterTy t -> do
    i <- gets nextRegisterId
    let r = Register{ registerTy = t, registerId = i }
    modify' $ \st -> st{ nextRegisterId = i + 1 }
    pure r
  | otherwise -> unreachable101 "unable to create register of type" t noTCHint

freshRegisterScalar :: Ty -> M VScalar
freshRegisterScalar t = VRegister (positionOf t) <$> freshRegister t

freshRegisterVal :: Ty -> M Val
freshRegisterVal t = VScalar (positionOf t) <$> freshRegisterScalar t

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

type Prog = Map AString Func

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
  , calls :: Map AString (Val -> M Val)
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
  = XVLam Position Env Binding Exp -- at the end of eval all lambdas have been eliminated
  | XVDelay Position Env Exp -- think of this as a rewrite from v to \() -> v so it won't evaluate immediately and can be used repeatedly (i.e. to repeat side-effecting calls)
  | XVTailRecDecls Position Env (Map LIdent TailRecDecl) LIdent
  | XVTailCall Position TailCallId
  | XVCall Position AString
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
  | VFloat Position Double
  | VInt Position Integer
  | VUInt Position Integer
  | VBool Position Bool
  | VEnum Position UIdent Integer
  | VUndef Position Ty
  | VExtern Position AString Ty
  | VRegister Position Register
  deriving (Show, Data)

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

data VStmt
  = VCall AString Val
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

newtype RegisterId = RegisterId{ unRegisterId :: Int } deriving (Show, Eq, Ord, Num, Data)

instance Pretty RegisterId where
  pretty x = "%r" <> pretty (unRegisterId x)

data Register = Register{ registerTy :: Ty, registerId :: RegisterId } deriving (Show, Data)

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
    VUndef _ t -> "<undef :" <+> pretty t <> ">"
    VEnum _ a _ -> "tag" <+> pretty a
    VExtern _ nm _ -> "<extern" <+> pretty nm <+> ">"
    VRegister _ r -> pretty r
    XVFreshRegVal _ t -> "<freshreg :" <+> pretty t <+> ">"

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

instance Typed VScalar where
  typeOf x = case x of
    VString pos _ -> TyString pos
    VChar pos _ -> TyChar pos 8
    VFloat pos _ -> TyFloat pos 64
    VInt pos _ -> TyInt pos 32
    VUInt pos _ -> TyUInt pos 32
    VBool pos _ -> TyBool pos
    VEnum pos c _ -> mkTyEnum pos [c]
    VRegister _ r -> typeOf r
    VExtern _ _ t -> t
    VUndef _ t -> t
    XVFreshRegVal _ t -> t

scalarToVScalar :: Scalar -> VScalar
scalarToVScalar x = case x of
  Char pos t -> VChar pos $ read $ Text.unpack t
  Double pos v -> VFloat pos $ valOf v
  Int pos t -> VInt pos $ read $ Text.unpack t
  String pos v -> VString pos $ valOf v
  UInt pos v -> case v of
    Dec{} -> VInt pos $ valOf v
    _ -> VUInt pos $ valOf v
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



