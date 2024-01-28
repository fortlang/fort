{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}

module Fort.TypeChecker

where

import Fort.Dependencies
import Fort.FreeVars
import Fort.Prims
import Fort.Type hiding (M, evalType_)
import qualified Fort.Type as Type
import Fort.Utils
import Fort.Val (OpSt(..), initOpSt, scalarToVScalar, lookupField)
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set

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
          XTyLam env' [Immediate _ pat] e -> do
            env'' <- match pat ta
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

initSt :: Bool -> St
initSt b = St
  { nextUnknown = 0
  , constraints = mempty
  , traceTC = b
  }

freshUnknown :: M Int
freshUnknown = do
  i <- gets nextUnknown
  modify' $ \st -> st{ nextUnknown = i + 1 }
  pure i

data St = St
  { nextUnknown :: Int
  , constraints :: Map Int (LIdent, (Position, Ty))
  , traceTC :: Bool
  }

type M a = StateT St (StateT OpSt (StateT TySt IO)) a

evalFieldDecls :: TyEnv -> [FieldDecl] -> M (Map LIdent Ty)
evalFieldDecls env bs = Map.fromList <$> sequence [ (fld, ) <$> eval env a | FieldDecl _ fld a <- bs ]

evalStmts :: Exp -> TyEnv -> [LayoutElemStmt] -> M Ty
evalStmts x0 = go
  where
    go env xs = case xs of
      [] -> unreachable100 "empty 'do'" x0
      [c] -> case newtypeOf c of
        Stmt _ e -> eval env e
        _ -> err100 "last element of 'do' must be an expression" c
      c : cs -> case newtypeOf c of
        Stmt _ e -> do
          vc <- eval env e
          unless (vc == TyUnit) $ err101 "value discarded in 'do' expression" c vc
          go env cs
        Let _ p e -> do
          env' <- eval env e >>= match p
          go (env' <> env) cs
        TailRecLet _ a -> do
          env' <- envTailRecDecls env a
          go (env' <> env) cs
        XLet{} -> unreachable100 "XLet not removed" c

freshTyUnknown :: LIdent -> M Ty
freshTyUnknown fn = XTyUnknown fn <$> freshUnknown

tailRecDeclNm :: TailRecDecl -> LIdent
tailRecDeclNm (TailRecDecl _ nm _ _) = nm

mkTailRecTyFun :: Ty -> Ty
mkTailRecTyFun t = TyFun t TyNone

evalTailRecDecls :: TyEnv -> LIdent -> Ty -> [TailRecDecl] -> M Ty
evalTailRecDecls env nm t = goTailRecDecls mempty env [(nm, t)]

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
    Nothing -> err101 "unknown variable" v $ Map.toList env
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

      XTyLam env' bnds e -> case bnds of
        [] -> unreachable101 "empty lambda" a va
        [bnd] -> do
          env'' <- matchBinding bnd vb
          eval (env'' <> env') e
        bnd : rest -> do
          env'' <- matchBinding bnd vb
          pure $ XTyLam (env'' <> env') rest e

      TySum m -> case Map.toList m of
        [(c, Nothing)] -> pure $ TySum $ Map.singleton c $ Just vb
        _ -> err101 "unexpected sum type in application" a va

      TyFun (XTyUnknown fn i) tc -> do
        pushConstraint fn i (positionOf b, vb)
        pure tc
      TyFun tb tc -> if
        | tb == vb -> pure tc
        | otherwise -> err10n "type mismatch in application" a [tb, vb]

      _ -> err101 "unexpected value in application" a va

  Extern _ _ t -> do
    t' <- evalType_ t
    checkExtern t t'
    pure t'

  Case _ a bs -> do
    va@(_, ta) <- evalWithPos env a
    unless (isIntTy ta || isTySum ta) $
      err101 "expected integral type in 'case' expression" a ta
    alts <- catMaybes <$> mapM (evalCaseAlt env va) (fmap newtypeOf bs)
    case alts of
      [] -> err100 "no alternatives match" a
      _ -> unifies alts

  Do _ ss -> evalStmts x env ss

  Where _ a bs -> do
     let gr = depGraph [ ExpDecl (positionOf b) b | b <- fmap newtypeOf bs ]
     rds <- reachableDecls gr (Set.fromList $ freeVars a)
     env' <- evalExpDecls env [ ed | ExpDecl _ ed <- rds ]
     eval env' a

  If pos ds -> do
    let (bs, cs) = List.unzip [ (b, c) | IfBranch _ b c <- fmap newtypeOf ds ]
    tbs <- mapM (evalWithPos env) bs
    tcs <- mapM (evalWithPos env) cs
    _ <- unifies ((pos, TyBool) : tbs)
    unifies tcs

  EType _ t -> TyType <$> evalType_ t

  Typed _ a t -> do
    ta <- evalWithPos env a
    tt <- evalTypeWithPos t
    unifies [ta, tt]

  Tuple _ a bs -> TyTuple <$> mapM (eval env . newtypeOf) (a : bs)
  Parens _ a -> eval env a
  Unit _ -> pure TyUnit

  Record _ bs -> TyRecord <$> evalFieldDecls env bs

  With _ a bs -> do
    ty <- eval env a
    case ty of
      TyRecord m -> do
        n <- evalFieldDecls env $ fmap newtypeOf bs
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
    TyArray (List.genericLength bs) <$> unifies cs

  Con _ c -> pure $ TySum $ Map.singleton c Nothing
  Scalar _ a -> pure $ typeOf a
  XArray{} -> unreachable100 "XArray not removed" x
  XDot{} -> unreachable100 "XDot not removed" x
  XRecord{} -> unreachable100 "XRecord not removed" x

unifies :: [(Position, Ty)] -> M Ty
unifies [] = unreachable001 "empty unification" ()
unifies (x : xs) = snd <$> foldM unify x xs

unify :: (Position, Ty) -> (Position, Ty) -> M (Position, Ty)
unify (posa, tya0) (posb, tyb0) = do
  ty <- go tya0 tyb0
  pure (posa, ty)
  where
    go :: Ty -> Ty -> M Ty
    go tya TyNone = pure tya
    go TyNone tyb = pure tyb
    go tya tyb = case (tya, tyb) of
      (TyRecord m, TyRecord n) -> do
        o <- intersectionWithM go m n
        if
          | Map.null o -> err "unification results in empty record"
          | otherwise -> pure $ TyRecord o
      (TySum m, TySum n) -> TySum <$> unionWithM goMaybe m n
      (TyTuple bs, TyTuple cs)
        | length bs == length cs -> TyTuple <$> zipWithM go bs cs
        | otherwise -> err "tuple types have differing lengths"
      (TyArray sza a, TyArray szb b)
        | sza == szb -> TyArray sza <$> go a b
        | otherwise -> err "array types have differing sizes"
      (TyPointer a, TyPointer b) -> TyPointer <$> go a b
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

envTailRecDecls :: TyEnv -> TailRecDecls -> M TyEnv
envTailRecDecls env (TailRecDecls _ ds0) = do
  let ds = fmap newtypeOf ds0
  pure $ Map.fromList [ (v, XTyTailRecDecls env ds v) | TailRecDecl _ v _ _ <- ds ]

evalExpDecls :: TyEnv -> [ExpDecl] -> M TyEnv
evalExpDecls = go
  where
    go env [] = pure env
    go env (d : ds) = do
      env' <- evalExpDecl env d
      go (env' <> env) ds

evalExpDecl :: TyEnv -> ExpDecl -> M TyEnv
evalExpDecl env x = case x of
  Binding _ p e -> eval env e >>= matchBinding p
  TailRec _ a -> envTailRecDecls env a

matchBinding :: Binding -> Ty -> M TyEnv
matchBinding x t = case x of
  Delayed _ v -> pure $ Map.singleton v t
  Immediate _ p -> match p t

evalCaseAlt :: TyEnv -> (Position, Ty) -> CaseAlt -> M (Maybe (Position, Ty))
evalCaseAlt env ty@(_, t0) (CaseAlt _ altp e) = case altp of
  PDefault _ v -> Just <$> evalWithPos (Map.insert v t0 env) e
  PCon _ c p -> case t0 of
    TySum m -> case Map.lookup c m of
      Nothing -> pure Nothing
      Just mt -> case mt of
        Just t -> do
          env' <- match p t
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
    _ <- unifies [ty, (positionOf a, typeOf a)]
    Just <$> evalWithPos env e

match :: Pat -> Ty -> M TyEnv
match p0 x = case (p0, x) of
  (PVar _ v, _) -> pure $ Map.singleton v x
  (PUnit _ , TyUnit) -> pure mempty
  (PTyped _ p _, _) -> match p x
  (PParens _ p, _) -> match p x
  (PTuple _ p ps, TyTuple xs) | 1 + length ps == length xs ->
    Map.unions <$> zipWithM match (fmap newtypeOf (p:ps)) xs
  (PTuple{}, TyPointer (TyTuple xs)) -> match p0 $ TyTuple $ fmap TyPointer xs
  _ -> err101 "pattern incompatible with type" p0 x

evalWithPos :: TyEnv -> Exp -> M (Position, Ty)
evalWithPos env x = (positionOf x, ) <$> eval env x

evalTypeWithPos :: Type -> M (Position, Ty)
evalTypeWithPos x = (positionOf x, ) <$> evalType_ x

instance Typed Scalar where
  typeOf = typeOf . scalarToVScalar

