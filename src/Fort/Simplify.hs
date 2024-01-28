module Fort.Simplify
( simplifyModules
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
import Fort.Utils
import Fort.Val
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Fort.Type as Type

evalType_ :: Type -> M Ty
evalType_ = lift . lift . Type.evalType_

evalSt :: Bool -> [Decl] -> M a -> IO a
evalSt ssb ds m =
  flip evalStateT (initTySt ds) $ flip evalStateT (initOpSt ds) $ evalStateT m st0
  where
    st0 = (initSt ssb) { calls = primCalls }

simplifyModules :: Bool -> [(FilePath, Map Text Exported)] -> IO [(FilePath, Prog)]
simplifyModules ssb xs = sequence [ (fn, ) <$> mapM (simplifyFunc ssb) m | (fn, m) <- xs ]

mainArgOf :: [Decl] -> M Val
mainArgOf xs = do
  margc <- lookupArg "\"FORT_argc\""
  margv <- lookupArg "\"FORT_argv\""
  case (margc, margv) of
    (Nothing, Nothing) -> pure VUnit
    (Just argc, Nothing) -> pure argc
    (Just argc, Just argv) -> pure $ VTuple [argc, argv]
    (Nothing, Just argv) -> do
      argc <- freshVal $ TyInt 32
      pure $ VTuple [argc, argv]
  where
    ss = [ (textOf s, (e, t)) | e@(Extern _ (s :: AString) t) <- universeBi xs ]
    lookupArg nm = case lookup nm ss of
      Nothing -> pure Nothing
      Just (e, ty) -> do
        t <- evalType_ ty
        case t of
          TyPointer ta -> do
            a <- freshVal ta
            ve <- eval mempty e
            void $ store ve a
            pure $ Just a
          _ -> err100 "expected main argument to have pointer type" e

simplifyFunc :: Bool -> Exported -> IO Func
simplifyFunc ssb x = case x of
  Main v ds -> evalSt ssb ds $ do
    mainArg <- mainArgOf ds
    env <- evalExpDecls (initEnv ssb) [ a | ExpDecl _ a <- ds ]
    let r = case lookup_ v env of
          VUnit -> VScalar $ VInt 0
          val -> val
    blk <- evalBlockM $ exitPrim r
    bds <- gets decls
    pure $ Func
      { retTy = TyInt 32
      , arg = mainArg
      , body = blk{ blockDecls = reverse bds ++ blockDecls blk }
      }

  Exported q t ds -> evalSt ssb ds $ do
    ty <- evalType_ t
    env <- evalExpDecls (initEnv ssb) [ a | ExpDecl _ a <- ds ]
    let val = lookup_ (qnToLIdent q) env
    case (val, ty) of
      (XVLam env' [Immediate _ pat] e, TyFun ta tb) -> do
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
      _ -> err111 "unable to export function (only immediate single arity functions can be exported)" q t noTCHint

initEnv :: Bool -> Env
initEnv b = Map.insert (mkTok noPosition "Prim.slow-safe-build") (VScalar $ VBool b) $ Map.mapWithKey (\nm _ -> XVCall nm) primCalls

evalCaseAlt :: Env -> Val -> CaseAlt -> M (Maybe Alt)
evalCaseAlt env val0 (CaseAlt _ altp e) = case altp of
  PDefault _ v -> Just . AltDefault <$> evalBlock (Map.insert v val0 env) e
  PScalar _ a -> Just . AltScalar (scalarToVScalar a) <$> evalBlock env e
  PEnum _ c -> case val0 of
    VSum _ m -> case Map.lookup c m of
      Just Nothing -> Just <$> (AltScalar <$> evalCon c <*> evalBlock env e)
      Just (Just _) -> err101 "unexpected enum pattern on sum" c val0
      Nothing -> pure Nothing
    _ -> err101 "unexpected enum pattern" altp val0
  PCon _ c p -> case val0 of
    VSum _ m -> case Map.lookup c m of
      Just (Just cval) -> do
        env' <- match p cval
        Just <$> (AltScalar <$> evalCon c <*> evalBlock (env' <> env) e)
      Just Nothing -> err101 "unexpected sum pattern on enum" p val0
      Nothing -> pure Nothing
    _ -> err101 "unexpected sum pattern" altp val0

-- this makes lots of extra registers, counting on the llvm optimizer to clean them up
-- e.g. 1 register can be used for the results of a multiway if but we make n - 1

pushTailCall :: TailCallId -> Val -> M ()
pushTailCall x y =
  modify' $ \st -> st{ tailcalls = (x, y) : tailcalls st }

evalBlock :: Env -> Exp -> M Block
evalBlock env x = evalBlockM (eval env x)

evalTailRecBlock :: Env -> Exp -> M Block
evalTailRecBlock env e = do
  tcs0 <- gets tailcalls
  modify' $ \st -> st{ tailcalls = [] }
  blk <- evalBlock env e
  tcs <- gets tailcalls
  modify' $ \st -> st{ tailcalls = tcs0 }
  pure $ blk { blockTailCalls = tcs }

evalXVTailRecDecls :: Env -> Map LIdent TailRecDecl -> LIdent -> Val -> M (TailCallId, [(TailCallId, (Val, Block))])
evalXVTailRecDecls env m0 nm0 val0 = do
  bs <- sequence [ ((v, d),) <$> freshTailCallId v | (v, d) <- Map.toList m0 ]
  let m = Map.fromList [ (tcid, d) | ((_, d), tcid) <- bs ]
  let env' = Map.fromList [ (v, XVTailCall tcid) | ((v, _), tcid) <- bs ]

  case [ tcid | ((v, _), tcid) <- bs, v == nm0 ] of
    [] -> unreachable001 "evalXVTailRecDecls: empty tcids" ()
    tcid : _ -> (tcid, ) <$> evalXVTailRecDecls' (env' <> env) m tcid val0

evalXVTailRecDecls' :: Env -> Map TailCallId TailRecDecl -> TailCallId -> Val -> M [(TailCallId, (Val, Block))]
evalXVTailRecDecls' env m0 tcid0 val0 = go m0 [(tcid0, val0)]
  where
  go _ [] = pure []
  go m ((tcid, val) : rest) = case Map.lookup tcid m of
    Nothing -> go m rest
    Just (TailRecDecl _ _ v e) -> do
      trArg <- freshVal $ typeOf val
      blk <- evalTailRecBlock (Map.insert v trArg env) e
      ((tcid, (trArg, blk)) :) <$> go (Map.delete tcid m) (rest ++ blockTailCalls blk)

evalTailRecDecls :: Env -> TailRecDecls -> Env
evalTailRecDecls env (TailRecDecls _ ds) =
  Map.mapWithKey (\k _ -> XVTailRecDecls env m k) m
  where
    m = Map.fromList [ (nm, b) | b@(TailRecDecl _ nm _ _) <- fmap newtypeOf ds ]

evalFieldDecl :: Env -> FieldDecl -> M (LIdent, Val)
evalFieldDecl env (FieldDecl _ lbl e) = (lbl, ) <$> eval env e

evalFieldDecls :: Env -> [FieldDecl] -> M (Map LIdent Val)
evalFieldDecls env xs = Map.fromList <$> mapM (evalFieldDecl env) xs

match :: Pat -> Val -> M Env
match p0 x = case (p0, x) of
  (PVar _ v, _) -> pure $ Map.singleton v x
  (PUnit _ , VUnit) -> pure mempty
  (PTyped _ p _, _) -> match p x
  (PParens _ p, _) -> match p x
  (PTuple _ b bs, VTuple xs) | length ps == length xs ->
    Map.unions <$> zipWithM match (fmap newtypeOf ps) xs
    where ps = b : bs
  (PTuple{}, VPtr _ (VTuple xs)) -> match p0 $ VTuple $ fmap mkVPtr xs
  _ -> err101 "pattern match failure" p0 x

mkVPtr :: Val -> Val
mkVPtr x = VPtr (typeOf x) x

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
  TailRec _ a -> pure $ evalTailRecDecls env a

freshTailCallId :: LIdent -> M TailCallId
freshTailCallId v = do
  i <- gets nextTailCallId
  modify' $ \st -> st{ nextTailCallId = i + 1 }
  pure TailCallId{ tailCallName = v, tailCallId = i }

evalBinding :: Env -> Binding -> Exp -> M Env
evalBinding env x e = case x of
  Delayed _ v -> pure $ Map.singleton v $ XVDelay env e
  Immediate _ p -> eval env e >>= match p

canBeDelayed :: LIdent -> Exp -> Bool
canBeDelayed v e = case filter (== nameOf v) $ freeVars e of
  _ : _ : _ -> False
  _ -> True

eval :: Env -> Exp -> M Val
eval env x = case x of
    Qualified pos c v -> eval env $ Var pos $ mkQName (textOf c) v
    Var _ v -> case Map.lookup v env of
      Nothing -> err101 "unknown variable" v $ Map.toList env
      Just val -> case val of
        XVDelay env' e -> eval env' e
        _ -> pure val

    Lam _ bs e -> pure $ XVLam env bs e

    App _ a b -> do
      va <- eval env a
      case va of
        XVCall nm -> do
          tbl <- gets calls
          eval env b >>= lookup_ nm tbl

        XVTailCall nm -> do
          vb <- eval env b
          pushTailCall nm vb
          pushDecl $ VTailCall nm vb
          pure XVNone

        XVTailRecDecls env' m nm -> do
          vb <- eval env b
          (tcid, tds) <- evalXVTailRecDecls env' m nm vb
          (r, rs) <- joinVals $ fmap (blockResult . snd . snd) tds
          let tds' = [ (tid, (trArg, blk{ blockResult = rt })) | (rt, (tid, (trArg, blk))) <- zip rs tds ]
          pushDecl $ VTailRecDecls tcid $ Map.fromList tds'
          pushDecl $ VLet r $ VCallTailCall tcid vb
          pure r

        XVLam env' vs e -> case vs of
          [] -> unreachable101 "empty lambda expression" a va
          bnd : rest -> do
            let bnd' = case bnd of
                  Immediate _ (PVar pos var) | canBeDelayed var e -> Delayed pos var
                  _ -> bnd
            env'' <- evalBinding env bnd' b
            let env''' = env'' <> env'
            case rest of
              [] -> eval env''' e
              _ -> pure $ XVLam env''' rest e

        VSum con m -> do
          vb <- eval env b
          case Map.toList m of
            [(c, Nothing)] -> pure $ VSum con $ Map.singleton c $ Just vb
            _ -> err101 "unexpected sum value in application" a va
        _ -> err101 "unexpected value in application" a va

    Extern _ s t -> do
      t' <- evalType_ t
      checkExtern t t'
      let nm = mkTok (positionOf s) $ textOf s
      case t' of
        TyFun _ rt -> do
          modify' $ \st -> st{ calls = Map.insert nm (fun rt nm) $ calls st }
          pure $ XVCall nm
        _ -> pure $ VScalar $ VExtern nm t'

    Case _ a bs -> do
      va <- eval env a
      alts <- catMaybes <$> mapM (evalCaseAlt env va) (fmap newtypeOf bs)
      evalSwitch va alts

    Do _ [] -> unreachable100 "empty 'do'" x
    Do _ [c] -> case newtypeOf c of
      Stmt _ e -> eval env e
      _ -> err100 "last element of 'do' expression must be an expression" c

    Do pos (c : cs) -> case newtypeOf c of
      Stmt _ e -> do
        vc <- eval env e
        case vc of
          VUnit -> pure ()
          _ -> err101 "value discarded in 'do' expression" c vc
        eval env $ Do pos cs
      Let _ p e -> do
        env' <- eval env e >>= match p
        eval (env' <> env) $ Do pos cs
      TailRecLet _ a -> do
        let env' = evalTailRecDecls env a
        eval (env' <> env) $ Do pos cs
      XLet{} -> unreachable100 "XLet not removed" c

    Where _ a bs -> do
       let gr = depGraph [ ExpDecl (positionOf b) b | b <- fmap newtypeOf bs ]
       rds <- reachableDecls gr (Set.fromList $ freeVars a)
       env' <- evalExpDecls env [ ed | ExpDecl _ ed <- rds ]
       eval env' a

    If _ [] -> unreachable100 "empty 'if' expression" x
    If _ [c] -> do
      let IfBranch _ a b = newtypeOf c
      _ <- eval env a >>= assertWithMessage "'if' is never true"
      eval env b

    If pos (c : cs) -> do
      let IfBranch _ a b = newtypeOf c
      va <- eval env a
      blkb <- evalBlock env b
      blkcs <- evalBlock env $ If pos cs
      evalIf va blkb blkcs

    EType _ a -> VType <$> evalType_ a

    Typed _ a _ -> eval env a

    Record _ bs -> VRecord . Map.fromList <$> mapM (evalFieldDecl env) bs

    With _ a bs -> do
      val <- eval env a
      case val of
        VRecord m -> do
          n <- evalFieldDecls env (fmap newtypeOf bs)
          pure $ VRecord (n `Map.union` m)
        _ -> err101 "expected record in 'with' expression" a (typeOf val)

    Select _ a fld -> do
      val <- eval env a
      case val of
        VRecord m -> lookupField a fld m
        VPtr _ (VRecord m) -> mkVPtr <$> lookupField a fld m
        _ -> err101 "expected record in 'select' expression" a (typeOf val)

    PrefixOper pos op a -> do
      tbl <- lift $ gets prefixOps
      eval env $ App pos (Var pos $ lookup_ op tbl) a

    InfixOper pos a op b -> do
      tbl <- lift $ gets infixOps
      eval env $ App pos (App pos (Var pos $ lookup_ op tbl) a) b

    Array _ bs -> VArray <$> mapM (eval env) bs
    Tuple _ a bs -> VTuple <$> mapM (eval env . newtypeOf) (a : bs)
    Parens _ a -> eval env a
    Unit _ -> pure VUnit

    Con _ c -> do
      vc <- evalCon c
      pure $ VSum (VScalar vc) $ Map.singleton c Nothing

    Scalar _ a -> pure $ VScalar $ scalarToVScalar a

    XArray{} -> unreachable100 "XArray not removed" x
    XDot{} -> unreachable100 "XDot not removed" x
    XRecord{} -> unreachable100 "XRecord not removed" x
