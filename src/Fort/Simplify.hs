module Fort.Simplify
( simplifyModules
, simplifyBuildDecls
, RegisterId(..)
, Val(..)
, M
, VScalar(..)
, VStmt(..)
, pushDecl
) where

import Fort.Dependencies
import Fort.FreeVars
import Fort.Prims
import Fort.Type hiding (M, evalType_)
import Fort.Utils hiding (err10n, err100, err101, err110)
import Fort.Val
import qualified Data.List.NonEmpty as NE
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Fort.Type as Type
import qualified Fort.TypeChecker as TC

evalType_ :: Type -> M Ty
evalType_ = lift . lift . lift . Type.evalType_

unifies :: NonEmpty Ty -> M Ty
unifies = lift . TC.unifies

evalSt :: Bool -> [Decl] -> M a -> IO a
evalSt ssb ds m =
  flip evalStateT (initTySt ds) $
  flip evalStateT (initOpSt ds) $
  flip evalStateT TC.initSt $
  evalStateT m st0
  where
    st0 = (initSt ssb) { calls = primCalls }

simplifyModules :: Bool -> [(FilePath, Map Text Exported)] -> IO [(FilePath, Prog)]
simplifyModules ssb xs = sequence [ (fn, ) <$> mapM (simplifyFunc ssb) m | (fn, m) <- xs ]

traceEval :: (Positioned a, Pretty a) => a -> M b -> M b
traceEval x m = do
  tr <- lift$ gets stackTrace
  lift $ modify' $ \st -> st{ stackTrace = Posn (positionOf x) (pretty x) : stackTrace st }
  a <- m
  lift $ modify' $ \st -> st{ stackTrace = tr }
  pure a

mainArgOf :: [Decl] -> M Val
mainArgOf xs = do
  margc <- lookupArg "FORT_argc"
  margv <- lookupArg "FORT_argv"
  case (margc, margv) of
    (Nothing, Nothing) -> pure $ VUnit noPosition
    (Just argc, Nothing) -> pure argc
    (Just argc, Just argv) -> pure $ VTuple (positionOf argc) $ fromList2 [argc, argv]
    (Nothing, Just argv) -> do
      let pos = positionOf argv
      argc <- freshVal $ TyInt pos I32
      pure $ VTuple pos $ fromList2 [argc, argv]
  where
    ss = [ (s, (e, t)) | e@(Extern _ s t) <- universeBi xs ]
    lookupArg nm = case lookup nm ss of
      Nothing -> pure Nothing
      Just (e, ty) -> do
        t <- evalType_ ty
        case t of
          TyPointer _ ta -> do
            a <- freshVal ta
            ve <- eval mempty e
            void $ store ve a
            pure $ Just a
          _ -> err100ST "expected main argument to have pointer type" e

simplifyBuildDecls :: Bool -> [Decl] -> IO [Text]
simplifyBuildDecls ssb ds = case ds of
  [] -> pure ["cbits/builtins.c"]
  _ -> evalSt ssb ds $ do
    void $ evalExpDecls (initEnv ssb) [ a | ExpDecl _ a <- ds ]
    gets buildCmd

simplifyFunc :: Bool -> Exported -> IO Func
simplifyFunc ssb x = case x of
  Main v ds -> evalSt ssb ds $ do
    mainArg <- mainArgOf ds
    env <- evalExpDecls (initEnv ssb) [ a | ExpDecl _ a <- ds ]
    let r = case lookup_ v env of
          VUnit pos -> VScalar pos $ VInt pos $ VInt32 0
          val -> val
    blk <- evalBlockM $ exitPrim r
    bds <- gets decls
    pure $ Func
      { retTy = TyInt (positionOf v) I32
      , arg = mainArg
      , body = blk{ blockDecls = reverse bds ++ blockDecls blk }
      }

  Exported q t ds -> evalSt ssb ds $ do
    ty <- evalType_ t
    env <- evalExpDecls (initEnv ssb) [ a | ExpDecl _ a <- ds ]
    let val = lookup_ (qnToLIdent q) env
    case (val, ty) of
      (XVLam _ env' (Immediate _ pat) e, TyFun _ ta tb) -> do
        va <- freshVal ta
        env'' <- match pat va
        r <- eval (env'' <> env') e
        blk <- evalBlockM $ exitPrim r
        bds <- gets decls
        pure $ Func
          { retTy = tb
          , arg = va
          , body = blk{ blockDecls = reverse bds ++ blockDecls blk }
          }
      _ -> err111ST "unable to export function (only immediate single arity functions can be exported)" q t noTCHint

err100ST :: (Positioned a, Pretty a) => Doc () -> a -> M c
err100ST msg a = lift $ TC.err100ST msg a

err101ST :: (Positioned a, Pretty a, Pretty b) => Doc () -> a -> b -> M c
err101ST msg a c = lift $ TC.err101ST msg a c

err10nST :: (Positioned a, Pretty a, Pretty b) => Doc () -> a -> [b] -> M c
err10nST msg a bs = lift $ TC.err10nST msg a bs

err111ST :: (Positioned a, Pretty a, Pretty b, Positioned b, Pretty c) => Doc () -> a -> b -> c -> M d
err111ST msg a b c = lift $ TC.err111ST msg a b c

initEnv :: Bool -> Env
initEnv b =
  Map.insert (mkTok noPosition "Prim.slow-safe-build") (VScalar noPosition $ VBool noPosition b) $
  Map.mapKeys (LIdent noPosition) $
  Map.mapWithKey (\nm _ -> XVCall noPosition nm) primCalls

insertAlt :: (VScalar, Block) -> [(VScalar, Block)] -> M [(VScalar, Block)]
insertAlt alt@(k, _) alts = case filter ((== IsEqual) . compareScalars k) $ fmap fst alts of
  [] -> pure (alt : alts)
  ks -> err10nST "duplicate alternative" k ks

evalCaseAlts :: [(VScalar, Block)] -> Env -> Val -> [CaseAlt] -> M Val
evalCaseAlts alts _ val0 [] = case alts of
  [] -> err101ST "no alternatives match" val0 noTCHint
  (vsclr, blk) : alts' -> case typeOf val0 of
    TySum _ m -> if
      | Map.null m -> do
          tg <- switchValOf val0
          blk' <- evalBlockM (eqVal tg (VScalar (positionOf vsclr) vsclr) >>= assertWithMessage "unmatched 'case' alternative")
          switch val0 (reverse alts') blk{ blockDecls = blockDecls blk' ++ blockDecls blk }

      | otherwise -> err10nST "'case' on sum type missing alternatives" val0 $ Map.keys m
    _ -> err101ST "'case' on scalar type with no default given" val0 noTCHint

evalCaseAlts alts env val0 (CaseAlt _ altp e : rest) = case altp of
  PDefault _ v -> do
    dflt <- evalBlock (Map.insert v val0 env) e
    switch val0 (reverse alts) dflt

  PScalar _ a -> do
    alt <- (scalarToVScalar a, ) <$> evalBlock env e
    alts' <- insertAlt alt alts
    evalCaseAlts alts' env val0 rest

  PEnum _ c -> case val0 of
    VSum pos k m -> case Map.lookup c m of
      Nothing -> evalCaseAlts alts env val0 rest
      Just (Just _) -> err101ST "unexpected enum pattern (sum pattern expected)" c val0
      Just Nothing -> do
         alt <- (,) <$> evalCon c <*> evalBlock env e
         alts' <- insertAlt alt alts
         evalCaseAlts alts' env (VSum pos k $ Map.delete c m) rest
    _ -> err101ST "unexpected enum pattern for non-sum type" altp val0

  PCon _ c p -> case val0 of
    VSum pos k m -> case Map.lookup c m of
      Nothing -> evalCaseAlts alts env val0 rest
      Just Nothing -> err101ST "unexpected sum pattern (enum pattern expected)" p val0
      Just (Just cval) -> do
        env' <- match p cval
        alt <- (,) <$> evalCon c <*> evalBlock (env' <> env) e
        alts' <- insertAlt alt alts
        evalCaseAlts alts' env (VSum pos k $ Map.delete c m) rest

    _ -> err101ST "unexpected sum pattern" altp val0

-- this makes lots of extra registers, counting on the llvm optimizer to clean them up
-- e.g. 1 register can be used for the results of a multiway if but we make n - 1

evalBlock :: Env -> Exp -> M Block
evalBlock env x = evalBlockM (eval env x)

evalFieldDecl :: Env -> FieldDecl -> M (LIdent, Val)
evalFieldDecl env (FieldDecl _ lbl e) = (lbl, ) <$> eval env e

evalFieldDecls :: Env -> NonEmpty FieldDecl -> M (Map LIdent Val)
evalFieldDecls env xs = Map.fromList <$> mapM (evalFieldDecl env) (toList xs)

match :: Pat -> Val -> M Env
match p0 x = case (p0, x) of
  (PVar _ v, _) -> pure $ Map.singleton v x
  (PUnit _ , VUnit _) -> pure mempty
  (PTyped _ p _, _) -> match p x
  (PParens _ p, _) -> match p x
  (PTuple _ ps, VTuple _ xs) | length2 ps == length2 xs ->
    Map.unions <$> zipWithM match (toList ps) (toList xs)
  (PTuple{}, VPtr pos _ (VTuple _ xs)) -> match p0 $ VTuple pos $ fmap mkVPtr xs
  _ -> err101ST "pattern match failure" p0 x

mkVPtr :: Val -> Val
mkVPtr x = VPtr (positionOf x) (typeOf x) x

evalExpDecls :: Env -> [ExpDecl] -> M Env
evalExpDecls = go
  where
    go env [] = pure env
    go env (d : ds) = do
      env' <- evalExpDecl env d
      go (env' <> env) ds

evalExpDecl :: Env -> ExpDecl -> M Env
evalExpDecl env x = case x of
  Binding _ p e -> evalBinding env p e

evalBinding :: Env -> Binding -> Exp -> M Env
evalBinding env x e = case x of
  Delayed _ v -> pure $ Map.singleton v $ XVDelay (positionOf e) env e
  Immediate _ p -> eval env e >>= match p

canBeDelayed :: LIdent -> Exp -> Bool
canBeDelayed v e = case filter (== nameOf v) $ freeVarsOf e of
  _ : _ : _ -> False
  _ -> True

eval :: Env -> Exp -> M Val
eval env x = traceEval x $ case x of
    Qualified pos c v -> eval env $ Var pos $ mkQName (textOf c) v
    Var pos v | textOf v == "Prim.loop" -> pure $ XVLoop pos
    Var _ v -> traceEval v $ case Map.lookup v env of
      Nothing -> err100ST "unknown variable" v
      Just val -> case val of
        XVDelay _ env' e -> eval env' e
        _ -> pure val

    Lam pos bs e -> pure $ XVLam pos env bs e

    App _ a b -> do
      va <- eval env a
      case va of
        XVLoop _ -> do
          vb <- eval env b
          case vb of
            VTuple _ (Cons2 i0 (vf :| [])) -> case vf of
              XVLam _ env' bnd e -> case bnd of
                Immediate _ p -> do
                  vi <- freshVal $ typeOf i0
                  blk <- evalBlockM $ do
                    env'' <- match p vi
                    eval (env'' <> env') e
                  (eqblk, (mc, mr)) <- case blockResult blk of
                    VSum pos k m -> do
                      eqk <- evalBlockM $ do
                        cont <- VScalar pos <$> evalCon (mkTok pos "Continue")
                        eqVal k cont
                      (eqk,) <$> lift (TC.unLoopSum m)
                    _ -> err100ST "loop expects Continue/Done sum result value" e
                  let pos = positionOf e
                  let r = fromMaybe (VUnit pos) mr
                  pushDecl $ VLet r $ VLoop vi i0 (blockResult eqblk) blk{ blockDecls = blockDecls blk ++ blockDecls eqblk,  blockResult = fromMaybe (VUnit pos) mc }
                  pure r
                _ -> err100ST "expected immediate binding in 'loop' lambda" bnd
              _ -> err100ST "expected lambda as second argument to 'loop'" vf
            _ -> err100ST "expected tuple argument to Prim.loop" vb

        XVCall _ nm -> do
          tbl <- gets calls
          eval env b >>= lookup_ nm tbl

        XVLam _ env' bnd e -> do
            let bnd' = case bnd of
                  Immediate _ (PVar pos var) | canBeDelayed var e -> Delayed pos var
                  _ -> bnd
            env'' <- evalBinding env bnd' b
            let env''' = env'' <> env'
            eval env''' e

        VSum pos con m -> do
          vb <- eval env b
          case Map.toList m of
            [(c, Nothing)] -> pure $ VSum pos con $ Map.singleton c $ Just vb
            _ -> err101ST "unexpected sum value in application" a va
        _ -> err101ST "unexpected value in application" a va

    Extern pos s t -> do
      t' <- evalType_ t
      checkExtern t'
      case t' of
        TyFun _ _ rt -> do
          modify' $ \st -> st{ calls = Map.insert s (fun rt s) $ calls st }
          pure $ XVCall pos s
        _ -> pure $ VScalar pos $ VExtern pos s t'

    Case _ a bs -> do
      va <- eval env a
      evalCaseAlts [] env va $ toList bs

    Do pos (c :| cs) -> case cs of
      [] -> case c of
        Stmt _ e -> eval env e
        _ -> err100ST "last element of 'do' expression must be an expression" c
      _ -> case c of
        Stmt _ e -> do
          vc <- eval env e
          case vc of
            VUnit _ -> pure ()
            _ -> err101ST "value discarded in 'do' expression" c vc
          eval env $ Do pos $ NE.fromList cs
        Let _ p e -> do
          env' <- eval env e >>= match p
          eval (env' <> env) $ Do pos $ NE.fromList cs

    Where _ a bs -> do
       let gr = depGraph [ ExpDecl (positionOf b) b | b <- toList bs ]
       rds <- reachableDecls gr (Set.fromList $ freeVarsOf a)
       env' <- evalExpDecls env [ ed | ExpDecl _ ed <- rds ]
       eval env' a

    If _ a b c -> do
      va <- eval env a
      evalIf va (eval env b) (eval env c)

    Else _ a b -> do
      _ <- eval env a >>= assertWithMessage "'if' is never true"
      eval env b

    EType pos a -> VType pos <$> evalType_ a

    Typed _ a _ -> eval env a

    Record pos bs -> VRecord pos . Map.fromList <$> mapM (evalFieldDecl env) (toList bs)

    With _ a bs -> do
      val <- eval env a
      case val of
        VRecord pos m -> do
          n <- evalFieldDecls env bs
          pure $ VRecord pos (n `Map.union` m)
        _ -> err101ST "expected record in 'with' expression" a (typeOf val)

    Select _ a fld -> do
      val <- eval env a
      case val of
        VRecord _ m -> lookupField a fld m
        VPtr _ _ (VRecord _ m) -> mkVPtr <$> lookupField a fld m
        _ -> err101ST "expected record in 'select' expression" a (typeOf val)

    PrefixOper pos op a -> traceEval op $ do
      tbl <- lift $ lift $ gets prefixOps
      eval env $ App pos (Var pos $ lookup_ op tbl) a

    InfixOper pos a op b -> traceEval op $ do
      tbl <- lift $ lift $ gets infixOps
      eval env $ App pos (App pos (Var pos $ lookup_ op tbl) a) b

    Array pos bs -> do
      vs <- mapM (eval env) bs
      t <- unifies $ fmap typeOf vs
      pure $ VArray pos (TyArray pos (fromIntegral $ NE.length bs) t) vs
    Tuple pos bs -> VTuple pos <$> mapM (eval env) bs
    Parens _ a -> eval env a
    Unit pos -> pure $ VUnit pos

    Con pos c -> do
      vc <- evalCon c
      pure $ VSum pos (VScalar pos vc) $ Map.singleton c Nothing

    Scalar pos a -> pure $ VScalar pos $ scalarToVScalar a

