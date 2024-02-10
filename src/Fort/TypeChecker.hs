{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}

module Fort.TypeChecker

where

import Fort.Dependencies
import Fort.FreeVars
import Fort.Prims
import Fort.Type hiding (M, evalType_)
import Fort.Utils hiding (err10n, err100, err101, err110)
import qualified Fort.Errors as Err
import Fort.Val (OpSt(..), initOpSt, scalarToVScalar, lookupField)
import qualified Data.List.NonEmpty as NE
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Fort.Type as Type

typeCheckModules :: [(FilePath, Map AString Exported)] -> IO ()
typeCheckModules xs = sequence_ $ concat [ [ evalExported a | a <- Map.elems m ] | (_, m) <- xs ]

evalType_ :: Type -> M Ty
evalType_ = lift . lift . Type.evalType_

evalExported :: Exported -> IO ()
evalExported x = case x of
  Main v ds -> evalSt ds $ do
    env <- evalDecls ds
    case lookup_ v env of
      TyInt _ 32 -> pure ()
      TyUInt _ 32 -> pure ()
      TyUnit _ -> pure ()
      _ -> err100ST "expected return type of main function to be int or ()" v

  Exported q t ds -> evalSt ds $ do
    t' <- evalType_ t
    checkExtern t t'
    case t' of
      TyFun _ ta tb -> do
        env <- evalDecls ds
        case lookup_ (qnToLIdent q) env of
          XTyLam _ env' (Immediate _ pat) e -> do
            env'' <- match pat ta
            tr <- eval (env'' <> env') e
            void $ unify tr tb
          _ -> err100ST "unable to export function (only immediate single arity functions can be exported)" q
      _ -> err110ST "only function types can be exported" q t

evalDecls :: [Decl] -> M TyEnv
evalDecls ds = evalExpDecls initEnv [ a | ExpDecl _ a <- ds ]

initEnv :: TyEnv
initEnv =
  Map.insert (LIdent noPosition "Prim.slow-safe-build") (TyBool noPosition) $
  Map.mapKeys (\nm -> LIdent noPosition $ textOf nm) $
  Map.mapWithKey (\nm _ -> XTyPrimCall noPosition nm) primCallTys

evalSt :: [Decl] -> M a -> IO a
evalSt ds m = flip evalStateT (initTySt ds) $ flip evalStateT (initOpSt ds) $ evalStateT m initSt

initSt :: TCSt
initSt = TCSt
  { nextUnknown = 0
  , constraints = mempty
  , stackTrace = []
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
freshTyUnknown fn = XTyUnknown (positionOf fn) fn <$> freshUnknown

tailRecDeclNm :: TailRecDecl -> LIdent
tailRecDeclNm (TailRecDecl _ nm _ _) = nm

mkTailRecTyFun :: Ty -> Ty
mkTailRecTyFun t = TyFun pos t $ TyNone pos
  where pos = positionOf t

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
  pure cs

evalTailRecDecl :: TyEnv -> Ty -> TailRecDecl -> [TailRecDecl] -> M Ty
evalTailRecDecl env tv (TailRecDecl _ nm v e) ds = do
  let env' = Map.fromList [ (nm, mkTailRecTyFun tv), (v, tv) ]
  unkEnv <- Map.fromList <$> mapM mkU (fmap tailRecDeclNm ds)
  eval (env' <> unkEnv <> env) e
    where
      mkU n = do
        t <- freshTyUnknown n
        pure (n, mkTailRecTyFun t)

pushConstraint :: LIdent -> Int -> Ty -> M ()
pushConstraint nm i pt = do
  tbl <- gets constraints
  pt'' <- case Map.lookup i tbl of
    Nothing -> pure pt
    Just (_, pt') -> unify pt pt'
  modify' $ \st -> st{ constraints = Map.insert i (nm, pt'') $ constraints st }

envTailRecDecls :: TyEnv -> TailRecDecls -> M TyEnv
envTailRecDecls env (TailRecDecls pos ds) =
  pure $ Map.fromList [ (v, XTyTailRecDecls pos env ds v) | TailRecDecl _ v _ _ <- toList ds ]

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
    matchBinding p t
  TailRec _ a -> envTailRecDecls env a

evalCaseAlt :: TyEnv -> Ty -> CaseAlt -> M (Maybe (Ty, Maybe UIdent))
evalCaseAlt env ty (CaseAlt _ altp e) = case altp of
  PDefault _ v -> Just . (, Nothing) <$> eval (Map.insert v ty env) e
  PCon _ c p -> case ty of
    TySum _ m -> case Map.lookup c m of
      Nothing -> pure Nothing
      Just mt -> case mt of
        Just t -> do
          env' <- match p t
          Just . (, Just c) <$> eval (env' <> env) e
        Nothing -> err101ST "unexpected sum pattern" p ty
    _ -> err101ST "unexpected sum pattern with non-sum type" altp ty
  PEnum _ c -> case ty of
    TySum _ m -> case Map.lookup c m of
      Nothing -> pure Nothing
      Just mt -> case mt of
        Nothing -> Just . (, Just c) <$> eval env e
        Just _ -> err101ST "unexpected enum pattern" altp ty
    _ -> err101ST "unexpected enum pattern with non-enum type" altp ty
  PScalar _ a -> do
    _ <- unify ty (typeOf a)
    Just . (, Nothing) <$> eval env e

instance Typed Scalar where
  typeOf = typeOf . scalarToVScalar

-- BAL: use the actual positions from Ty since we have those now
unifies :: NonEmpty Ty -> M Ty
unifies (x :| xs) = foldM unify x xs

unify :: Ty -> Ty -> M Ty -- BAL: rewrite with go
unify tya0 tyb0 = go tya0 tyb0
  where
    go :: Ty -> Ty -> M Ty
    go tya TyNone{} = pure tya
    go TyNone{} tyb = pure tyb
    go tya tyb = case (tya, tyb) of
      (TyRecord pos m, TyRecord _ n) | isEqualByKeys m n -> do
        o <- intersectionWithM go m n
        if
          | Map.null o -> err "unification results in empty record"
          | otherwise -> pure $ TyRecord pos o
      (TySum pos m, TySum _ n) -> TySum pos <$> unionWithM goMaybe m n
      (TyTuple pos bs, TyTuple _ cs)
        | length2 bs == length2 cs -> TyTuple pos . fromList2 <$> zipWithM go (toList bs) (toList cs)
        | otherwise -> err "tuple types have differing lengths"
      (TyArray pos sza a, TyArray _ szb b)
        | sza == szb -> TyArray pos sza <$> go a b
        | otherwise -> err "array types have differing sizes"
      (TyPointer pos a, TyPointer _ b) -> TyPointer pos <$> go a b
      (TyFun pos a b, TyFun _ c d) -> TyFun pos <$> go a c <*> go b d
      (XTyLam _ env bnd e, TyFun _ tyc tyd) -> goLam tyc tyd env bnd e
      (TyFun _ tyc tyd, XTyLam _ env bnd e) -> goLam tyc tyd env bnd e
      _ | tya == tyb -> pure tya
      _ -> err "type mismatch"
      where
        err :: Doc () -> M a
        err msg = err110ST msg tya tyb

        goMaybe :: Maybe Ty -> Maybe Ty -> M (Maybe Ty)
        goMaybe ma mb = case (ma, mb) of
          (Nothing, Nothing) -> pure Nothing
          (Just a, Just b) -> Just <$> go a b
          _ -> err "constructor used as both enum and sum"

        goLam tyc tyd env bnd e = do
          env' <- matchBinding bnd tyc
          let env'' = env' <> env
          TyFun (positionOf tyc) tyc <$> (eval env'' e >>= go tyd)

matchBinding :: Binding -> Ty -> M TyEnv
matchBinding x ty = case x of
  Delayed _ v -> pure $ Map.singleton v ty
  Immediate _ p -> match p ty

match :: Pat -> Ty -> M TyEnv
match p0 x = case (p0, x) of
  (PVar _ v, _) -> pure $ Map.singleton v x
  (PUnit _ , TyUnit _) -> pure mempty
  (PTyped _ p pt, _) -> do
    ty' <- evalType_ pt
    ty'' <- unify ty' x
    match p ty''
  (PParens _ p, _) -> match p x
  (PTuple _ ps, TyTuple _ xs) | length2 ps == length2 xs ->
    Map.unions <$> zipWithM match (toList ps) (toList xs)
  (PTuple{}, TyPointer _ (TyTuple pos xs)) -> match p0 (TyTuple pos $ fmap (TyPointer pos) xs)
  _ -> err101ST "pattern incompatible with type" p0 x

traceEval :: (Positioned a, Pretty a) => a -> M b -> M b
traceEval x m = do
  modify' $ \st -> st{ stackTrace = Posn (positionOf x) (pretty x) : stackTrace st }
  a <- m
  modify' $ \st -> st{ stackTrace = tail $ stackTrace st }
  pure a

err110ST :: (Positioned a, Pretty a, Positioned b, Pretty b) => Doc () -> a -> b -> M c
err110ST msg a b = stackTraceHint >>= \stHint -> Err.err11n msg a b stHint

err100ST :: (Positioned a, Pretty a) => Doc () -> a -> M c
err100ST msg a = err10nST msg a ([] :: [Int])

err10nST :: (Positioned a, Pretty a, Pretty b) => Doc () -> a -> [b] -> M c
err10nST msg a bs = stackTraceHint >>= \stHint -> Err.err10n msg a (fmap (show . pretty) bs ++ stHint)

err101ST :: (Positioned a, Pretty a, Pretty b) => Doc () -> a -> b -> M c
err101ST msg a b = err10nST msg a [b]

err111ST :: (Positioned a, Pretty a, Pretty b, Positioned b, Pretty c) => Doc () -> a -> b -> c -> M d
err111ST msg a b c = stackTraceHint >>= \stHint -> Err.err111 msg a b (show (pretty c) : stHint)

getStackTraceLine :: Positioned a => a -> IO String
getStackTraceLine x = case positionOf x of
  (Just fn, Just (j, i)) -> do
    let s0 = fn ++ "@" ++ show j ++ ":" ++ show i
    s <- getLineAt fn j
    pure (s0 ++ ":  " ++ s)
  _ -> pure "<noposition>"

stackTraceHint :: M [String]
stackTraceHint = do
  bs <- declutter <$> gets stackTrace
  case bs of
    [] -> pure []
    [_] -> pure []
    _ -> do
      ss <- mapM (liftIO . getStackTraceLine) bs
      pure [unlines ("eval steps:" : ss)]
  where
    declutter :: Positioned a => [a] -> [a]
    declutter = List.reverse . fmap (last . List.sortBy maxCol) . List.groupBy lineNum
      where
        lineNum a b = case (positionOf a, positionOf b) of
          ((Just fna, Just (ja, _)), (Just fnb, Just (jb, _))) -> fna == fnb && ja == jb
          (pa, pb) -> pa == pb

        maxCol a b = case (positionOf a, positionOf b) of
              ((_, Just (_, ia)), (_, Just (_, ib))) -> compare ia ib
              (pa, pb) -> compare pa pb

eval :: TyEnv -> Exp -> M Ty
eval env x = traceEval x $ case x of
  Qualified pos c v -> eval env $ Var pos $ mkQName (textOf c) v
  Var _ v -> traceEval v $ case Map.lookup v env of
    Nothing -> err100ST "unknown variable" v
    Just ty -> pure ty

  Lam pos bs e -> pure $ XTyLam pos env bs e
  App _ a b -> do
    va <- eval env a
    vb <- eval env b
    case va of
      XTyTailRecDecls _ env' ds fn -> evalTailRecDecls env' fn vb ds

      XTyPrimCall _ nm -> case lookup_ nm primCallTys vb of
        Right t -> pure t
        Left msg -> err101ST msg b vb

      XTyLam _ env' bnd e -> do
          env'' <- matchBinding bnd vb
          eval (env'' <> env') e

      TySum pos m -> case Map.toList m of
        [(c, Nothing)] -> pure $ TySum pos $ Map.singleton c $ Just vb
        _ -> err101ST "unexpected sum type in application" a va

      TyFun _ (XTyUnknown _ fn i) tc -> do
        pushConstraint fn i vb
        pure tc
      TyFun _ tb tc -> do
        _ <- unify tb vb
        pure tc

      _ -> err101ST "unexpected value in application" a va

  Extern _ _ t -> do
    t' <- evalType_ t
    checkExtern t t'
    pure t'

  Case _ a bs -> do
    va <- eval env a
    unless (isIntTy va || isTySum va) $
      err101ST "expected integral type in 'case' expression" a va
    (alts, mcons) <- unzip . catMaybes <$> mapM (evalCaseAlt env va) (toList bs)
    t <- case alts of
      [] -> err100ST "no alternatives match" a
      _ -> unifies $ NE.fromList alts
    let noDefaultCase = List.null [ () | CaseAlt _ PDefault{} _ <- toList bs ]
    when noDefaultCase $ case va of
      TySum _ m -> if
        | List.null cs -> pure ()
        | otherwise -> err10nST "'case' on sum type missing alternatives" x cs
        where
          cs = Map.keys m List.\\ catMaybes mcons
      _ -> err100ST "'case' on scalar type with no default given" x
    pure t

  Do _ ss -> evalStmts env ss

  Where _ a bs -> do
     let gr = depGraph [ ExpDecl (positionOf b) b | b <- toList bs ]
     rds <- reachableDecls gr (Set.fromList $ freeVarsOf a)
     env' <- evalExpDecls env [ ed | ExpDecl _ ed <- rds ]
     eval env' a

  If _ a b c -> do
    ta <- eval env a
    _ <- unify (TyBool $ positionOf a) ta
    tb <- eval env b
    tc <- eval env c
    unify tb tc

  Else _ a b -> do
    ta <- eval env a
    _ <- unify (TyBool $ positionOf a) ta
    eval env b

  EType pos t -> TyType pos <$> evalType_ t

  Typed _ a t -> do
    ta <- eval env a
    tt <- evalType_ t
    unify ta tt

  Tuple pos bs -> TyTuple pos <$> mapM (eval env) bs
  Parens _ a -> eval env a
  Unit pos -> pure $ TyUnit pos

  Record pos bs -> TyRecord pos <$> evalFieldDecls env bs

  With _ a bs -> do
    ty <- eval env a
    case ty of
      TyRecord pos m -> do
        n <- evalFieldDecls env bs
        pure $ TyRecord pos (n `Map.union` m)
      _ -> err101ST "expected record in 'with' expression" a ty

  Select _ a fld -> do
    ty <- eval env a
    case ty of
      TyRecord _ m -> lookupField a fld m
      TyPointer pos (TyRecord _ m) -> TyPointer pos <$> lookupField a fld m
      _ -> err101ST "expected record in 'select' expression" a ty

  PrefixOper pos op a -> traceEval op $ do
    tbl <- lift $ gets prefixOps
    eval env $ App pos (Var pos $ lookup_ op tbl) a

  InfixOper pos a op b -> traceEval op $ do
    tbl <- lift $ gets infixOps
    eval env $ App pos (App pos (Var pos $ lookup_ op tbl) a) b

  Array pos bs -> do
    cs <- mapM (eval env) bs
    TyArray pos (toInteger $ NE.length bs) <$> unifies cs

  Con pos c -> pure $ TySum pos $ Map.singleton c Nothing
  Scalar _ a -> pure $ typeOf a

evalStmts :: TyEnv -> NonEmpty Stmt -> M Ty
evalStmts = go
  where
    go env (c :| cs) = case cs of
      [] -> case c of
        Stmt _ e -> eval env e
        _ -> err100ST "last element of 'do' must be an expression" c
      _ -> case c of
        Stmt _ e -> do
          vc <- eval env e
          case vc of
            TyUnit{} -> go env $ NE.fromList cs
            _ -> err101ST "value discarded in 'do' expression" c vc
          
        Let _ p e -> do
          te <- eval env e
          env' <- match p te
          go (env' <> env) $ NE.fromList cs
        TailRecLet _ a -> do
          env' <- envTailRecDecls env a
          go (env' <> env) $ NE.fromList cs



