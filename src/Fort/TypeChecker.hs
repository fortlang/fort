{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}

module Fort.TypeChecker

where

import Fort.Dependencies
import Fort.FreeVars
import Fort.Prims
import Fort.Type hiding (M, evalType_)
import Fort.Utils
import Fort.Val (OpSt(..), initOpSt, scalarToVScalar, lookupField)
import qualified Data.List.NonEmpty as NE
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Fort.Type as Type

typeCheckModules :: Bool -> [(FilePath, Map Text Exported)] -> IO ()
typeCheckModules b xs = sequence_ $ concat [ [ evalExported b a | a <- Map.elems m ] | (_, m) <- xs ]

evalType_ :: Type -> M Ty
evalType_ = lift . lift . Type.evalType_

evalExported :: Bool -> Exported -> IO ()
evalExported b x = case x of
  Main v ds -> evalSt b ds $ do
    env <- evalDecls ds
    case lookup_ v env of
      TyInt 32 -> pure ()
      TyUInt 32 -> pure ()
      TyUnit -> pure ()
      _ -> err100 "expected return type of main function to be int or ()" v

  Exported q t ds -> evalSt b ds $ do
    t' <- evalType_ t
    checkExtern t t'
    case t' of
      TyFun ta tb -> do
        env <- evalDecls ds
        case lookup_ (qnToLIdent q) env of
          XTyLam env' (Immediate _ pat) e -> do
            env'' <- match pat (positionOf t, ta)
            tr <- eval (env'' <> env') e
            void $ unify (positionOf q, tr) (positionOf t, tb)
          _ -> err100 "unable to export function (only immediate single arity functions can be exported)" q
      _ -> err110 "only function types can be exported" q t

evalDecls :: [Decl] -> M TyEnv
evalDecls ds = evalExpDecls initEnv [ a | ExpDecl _ a <- ds ]

initEnv :: TyEnv
initEnv = Map.insert (mkTok noPosition "Prim.slow-safe-build") TyBool $ Map.mapWithKey (\nm _ -> XTyPrimCall nm) primCallTys

evalSt :: Bool -> [Decl] -> M a -> IO a
evalSt b ds m = flip evalStateT (initTySt ds) $ flip evalStateT (initOpSt ds) $ evalStateT m (initSt b)

initSt :: Bool -> TCSt
initSt b = TCSt
  { nextUnknown = 0
  , constraints = mempty
  , traceTC = b
  }

freshUnknown :: M Int
freshUnknown = do
  i <- gets nextUnknown
  modify' $ \st -> st{ nextUnknown = i + 1 }
  pure i

type M a = StateT TCSt (StateT OpSt (StateT TySt IO)) a

evalFieldDecls :: TyEnv -> NonEmpty FieldDecl -> M (Map LIdent Ty)
evalFieldDecls env bs = Map.fromList <$> sequence [ (fld, ) <$> eval env a | FieldDecl _ fld a <- toList bs ]

freshTyUnknown :: LIdent -> M Ty
freshTyUnknown fn = XTyUnknown fn <$> freshUnknown

tailRecDeclNm :: TailRecDecl -> LIdent
tailRecDeclNm (TailRecDecl _ nm _ _) = nm

mkTailRecTyFun :: Ty -> Ty
mkTailRecTyFun t = TyFun t TyNone

evalTailRecDecls :: TyEnv -> LIdent -> Ty -> NonEmpty TailRecDecl -> M Ty
evalTailRecDecls env nm t = goTailRecDecls mempty env [(nm, t)] . toList

goTailRecDecls :: [Ty] -> Map LIdent Ty -> [(LIdent, Ty)] -> [TailRecDecl] -> M Ty
goTailRecDecls rs env xs0 ds0 = case xs0 of
  (nm, t) : xs | not (null ds0) -> case List.partition ((== nm) . tailRecDeclNm) ds0 of
    ([d], ds) -> do
      r <- evalTailRecDecl env t d ds
      xs' <- popConstraints
      goTailRecDecls (r : rs) (Map.insert nm (mkTailRecTyFun t) env) (xs' ++ xs) ds
    a -> unreachable101 "TypeChecker:goTailRecDecls" nm a

  _ -> case reverse rs of
    r : _ -> pure r
    a -> unreachable001 "TypeChecker:goTailRecDecls" a

popConstraints :: M [(LIdent, Ty)]
popConstraints = do
  cs <- Map.elems <$> gets constraints
  modify' $ \st -> st{ constraints = mempty }
  pure [ (nm, t) | (nm, (_, t)) <- cs ]

evalTailRecDecl :: TyEnv -> Ty -> TailRecDecl -> [TailRecDecl] -> M Ty
evalTailRecDecl env tv (TailRecDecl _ nm v e) ds = do
  let env' = Map.fromList [ (nm, mkTailRecTyFun tv), (v, tv) ]
  unkEnv <- Map.fromList <$> mapM mkU (fmap tailRecDeclNm ds)
  eval (env' <> unkEnv <> env) e
    where
      mkU n = do
        t <- freshTyUnknown n
        pure (n, mkTailRecTyFun t)

pushConstraint :: LIdent -> Int -> (Position, Ty) -> M ()
pushConstraint nm i pt = do
  tbl <- gets constraints
  pt'' <- case Map.lookup i tbl of
    Nothing -> pure pt
    Just (_, pt') -> unify pt pt'
  modify' $ \st -> st{ constraints = Map.insert i (nm, pt'') $ constraints st }

envTailRecDecls :: TyEnv -> TailRecDecls -> M TyEnv
envTailRecDecls env (TailRecDecls _ ds) =
  pure $ Map.fromList [ (v, XTyTailRecDecls env ds v) | TailRecDecl _ v _ _ <- toList ds ]

evalExpDecls :: TyEnv -> [ExpDecl] -> M TyEnv
evalExpDecls = go
  where
    go env [] = pure env
    go env (d : ds) = do
      env' <- evalExpDecl env d
      go (env' <> env) ds

evalExpDecl :: TyEnv -> ExpDecl -> M TyEnv
evalExpDecl env x = case x of
  Binding _ p e -> do
    t <- eval env e
    matchBinding p (positionOf e, t)
  TailRec _ a -> envTailRecDecls env a

evalCaseAlt :: TyEnv -> (Position, Ty) -> CaseAlt -> M (Maybe (Position, Ty))
evalCaseAlt env ty@(pos0, t0) (CaseAlt _ altp e) = case altp of
  PDefault _ v -> Just <$> evalWithPos (Map.insert v t0 env) e
  PCon _ c p -> case t0 of
    TySum m -> case Map.lookup c m of
      Nothing -> pure Nothing
      Just mt -> case mt of
        Just t -> do
          env' <- match p (pos0, t)
          Just <$> evalWithPos (env' <> env) e
        Nothing -> err101 "unexpected sum pattern" p t0
    _ -> err101 "unexpected sum pattern with non-sum type" altp t0
  PEnum _ c -> case t0 of
    TySum m -> case Map.lookup c m of
      Nothing -> pure Nothing
      Just mt -> case mt of
        Nothing -> Just <$> evalWithPos env e
        Just _ -> err101 "unexpected enum pattern" altp t0
    _ -> err101 "unexpected enum pattern with non-enum type" altp t0
  PScalar _ a -> do
    _ <- unify_ ty (positionOf a, typeOf a)
    Just <$> evalWithPos env e

instance Typed Scalar where
  typeOf = typeOf . scalarToVScalar

unifies :: NonEmpty (Position, Ty) -> M Ty
unifies (x :| xs) = snd <$> foldM unify x xs

unify_ :: (Position, Ty) -> (Position, Ty) -> M Ty
unify_ x y = snd <$> unify x y

unify :: (Position, Ty) -> (Position, Ty) -> M (Position, Ty)
unify (posa, tya0) (posb, tyb0) = do
  ty <- go tya0 tyb0
  pure (posa, ty)
  where
    go :: Ty -> Ty -> M Ty
    go tya TyNone = pure tya
    go TyNone tyb = pure tyb
    go tya tyb = case (tya, tyb) of
      (TyRecord m, TyRecord n) | isEqualByKeys m n -> do
        o <- intersectionWithM go m n
        if
          | Map.null o -> err "unification results in empty record"
          | otherwise -> pure $ TyRecord o
      (TySum m, TySum n) -> TySum <$> unionWithM goMaybe m n
      (TyTuple bs, TyTuple cs)
        | length2 bs == length2 cs -> TyTuple . fromList2 <$> zipWithM go (toList bs) (toList cs)
        | otherwise -> err "tuple types have differing lengths"
      (TyArray sza a, TyArray szb b)
        | sza == szb -> TyArray sza <$> go a b
        | otherwise -> err "array types have differing sizes"
      (TyPointer a, TyPointer b) -> TyPointer <$> go a b
      (TyFun a b, TyFun c d) -> TyFun <$> go a c <*> go b d
      (XTyLam env bnd e, TyFun tyc tyd) -> goLam (posb, tyc) tyd env bnd e
      (TyFun tyc tyd, XTyLam env bnd e) -> goLam (posa, tyc) tyd env bnd e
      _ | tya == tyb -> pure tya
      _ -> err "type mismatch"
      where
        err :: Doc () -> M a
        err msg = errn00 msg [Posn posa tya, Posn posb tyb]

        goMaybe :: Maybe Ty -> Maybe Ty -> M (Maybe Ty)
        goMaybe ma mb = case (ma, mb) of
          (Nothing, Nothing) -> pure Nothing
          (Just a, Just b) -> Just <$> go a b
          _ -> err "constructor used as both enum and sum"

        goLam ptyc@(_, tyc) tyd env bnd e = do
          env' <- matchBinding bnd ptyc
          let env'' = env' <> env
          TyFun tyc <$> (eval env'' e >>= go tyd)

matchBinding :: Binding -> (Position, Ty) -> M TyEnv
matchBinding x ty@(_, t) = case x of
  Delayed _ v -> pure $ Map.singleton v t
  Immediate _ p -> match p ty

match :: Pat -> (Position, Ty) -> M TyEnv
match p0 ty@(pos, x) = case (p0, x) of
  (PVar _ v, _) -> pure $ Map.singleton v x
  (PUnit _ , TyUnit) -> pure mempty
  (PTyped _ p pt, _) -> do
    ty' <- evalTypeWithPos pt
    ty'' <- unify_ ty' ty
    match p (pos, ty'')
  (PParens _ p, _) -> match p ty
  (PTuple _ ps, TyTuple xs) | length2 ps == length2 xs ->
    Map.unions <$> zipWithM match (toList ps) (fmap (pos,) $ toList xs)
  (PTuple{}, TyPointer (TyTuple xs)) -> match p0 (pos, TyTuple $ fmap TyPointer xs)
  _ -> err101 "pattern incompatible with type" p0 x

evalTypeWithPos :: Type -> M (Position, Ty)
evalTypeWithPos x = (positionOf x, ) <$> evalType_ x

traceEval :: Exp -> M Ty -> M Ty
traceEval e m = do
  tr <- gets traceTC
  when tr $ liftIO $ print $ pretty e
  a <- m
  when tr $ liftIO $ do
    putStr ": "
    print $ pretty a
  pure a

eval :: TyEnv -> Exp -> M Ty
eval env x = traceEval x $ case x of
  Qualified pos c v -> eval env $ Var pos $ mkQName (textOf c) v
  Var _ v -> case Map.lookup v env of
    Nothing -> err100 "unknown variable" v
    Just ty -> pure ty

  Lam _ bs e -> pure $ XTyLam env bs e
  App _ a b -> do
    va <- eval env a
    vb <- eval env b
    case va of
      XTyTailRecDecls env' ds fn -> evalTailRecDecls env' fn vb ds

      XTyPrimCall nm -> case lookup_ nm primCallTys vb of
        Right t -> pure t
        Left msg -> err101 msg b vb

      XTyLam env' bnd e -> do
          env'' <- matchBinding bnd (positionOf b, vb)
          eval (env'' <> env') e

      TySum m -> case Map.toList m of
        [(c, Nothing)] -> pure $ TySum $ Map.singleton c $ Just vb
        _ -> err101 "unexpected sum type in application" a va

      TyFun (XTyUnknown fn i) tc -> do
        pushConstraint fn i (positionOf b, vb)
        pure tc
      TyFun tb tc -> do
        _ <- unify (positionOf a, tb) (positionOf b, vb)
        pure tc

      _ -> err101 "unexpected value in application" a va

  Extern _ _ t -> do
    t' <- evalType_ t
    checkExtern t t'
    pure t'

  Case _ a bs -> do
    va@(_, ta) <- evalWithPos env a
    unless (isIntTy ta || isTySum ta) $
      err101 "expected integral type in 'case' expression" a ta
    alts <- catMaybes <$> mapM (evalCaseAlt env va) (toList bs)
    case alts of
      [] -> err100 "no alternatives match" a
      _ -> unifies $ NE.fromList alts

  Do _ ss -> evalStmts env ss

  Where _ a bs -> do
     let gr = depGraph [ ExpDecl (positionOf b) b | b <- toList bs ]
     rds <- reachableDecls gr (Set.fromList $ freeVarsOf a)
     env' <- evalExpDecls env [ ed | ExpDecl _ ed <- rds ]
     eval env' a

  If _ a b c -> do
    ta <- evalWithPos env a
    _ <- unify_ (positionOf a, TyBool) ta
    tb <- evalWithPos env b
    tc <- evalWithPos env c
    unify_ tb tc

  Else _ a b -> do
    ta <- evalWithPos env a
    _ <- unify_ (positionOf a, TyBool) ta
    eval env b

  EType _ t -> TyType <$> evalType_ t

  Typed _ a t -> do
    ta <- evalWithPos env a
    tt <- evalTypeWithPos t
    unify_ ta tt

  Tuple _ bs -> TyTuple <$> mapM (eval env) bs
  Parens _ a -> eval env a
  Unit _ -> pure TyUnit

  Record _ bs -> TyRecord <$> evalFieldDecls env bs

  With _ a bs -> do
    ty <- eval env a
    case ty of
      TyRecord m -> do
        n <- evalFieldDecls env bs
        pure $ TyRecord (n `Map.union` m)
      _ -> err101 "expected record in 'with' expression" a ty

  Select _ a fld -> do
    ty <- eval env a
    case ty of
      TyRecord m -> lookupField a fld m
      TyPointer (TyRecord m) -> TyPointer <$> lookupField a fld m
      _ -> err101 "expected record in 'select' expression" a ty

  PrefixOper pos op a -> do
    tbl <- lift $ gets prefixOps
    eval env $ App pos (Var pos $ lookup_ op tbl) a

  InfixOper pos a op b -> do
    tbl <- lift $ gets infixOps
    eval env $ App pos (App pos (Var pos $ lookup_ op tbl) a) b

  Array _ bs -> do
    cs <- mapM (evalWithPos env) bs
    TyArray (toInteger $ NE.length bs) <$> unifies cs

  Con _ c -> pure $ TySum $ Map.singleton c Nothing
  Scalar _ a -> pure $ typeOf a

evalWithPos :: TyEnv -> Exp -> M (Position, Ty)
evalWithPos env x = (positionOf x, ) <$> eval env x

evalStmts :: TyEnv -> NonEmpty Stmt -> M Ty
evalStmts = go
  where
    go env (c :| cs) = case cs of
      [] -> case c of
        Stmt _ e -> eval env e
        _ -> err100 "last element of 'do' must be an expression" c
      _ -> case c of
        Stmt _ e -> do
          vc <- eval env e
          unless (vc == TyUnit) $ err101 "value discarded in 'do' expression" c vc
          go env $ NE.fromList cs
        Let _ p e -> do
          te <- eval env e
          env' <- match p (positionOf e, te)
          go (env' <> env) $ NE.fromList cs
        TailRecLet _ a -> do
          env' <- envTailRecDecls env a
          go (env' <> env) $ NE.fromList cs



