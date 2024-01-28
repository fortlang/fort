-- | This module qualifies free variables and type names.  E.g. an unqualified free variable 'foo' will be changed to '<filepath>.foo'.
-- User qualified names are left unchanged.  When they are resolved in later passes there with be a mapping from UIdent -> filepath.
-- Operator names are global and left unchanged.

module Fort.Qualify (qualifyModules) where

import Fort.Bindings
import Fort.Utils
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Text as Text

type M a = ReaderT St IO a

data St = St
  { env :: Map Text [Name]
  , qualifiers :: Map UIdent Text
  }

initSt :: St
initSt = St
  { env = mempty
  , qualifiers = mempty
  }

toQualifierTable :: [(UIdent, FilePath)] -> M (Map UIdent Text)
toQualifierTable xs = Map.fromList <$> mapM f (Map.toList m)
  where
    m = foldr (\(q, fn) -> Map.insertWith (++) q [(q, fn)]) mempty xs
    f (q, _) | textOf q == "Prim" = err100 "'Prim' is a reserved qualifier" q
    f (q, bs) = case List.nub $ fmap snd bs of
      [fn] -> pure (q, Text.pack fn)
      _ -> errn00 "duplicate conflicting qualifiers" (fmap fst bs)

qualifyModules :: [(UIdent, FilePath)] -> [(FilePath, Module)] -> IO [(FilePath, Module)]
qualifyModules quals xs = runReaderT (qualModules quals xs) initSt

qualModules :: [(UIdent, FilePath)] -> [(FilePath, Module)] -> M [(FilePath, Module)]
qualModules quals xs = do
  qualTbl <- toQualifierTable quals
  local (\st -> st{ qualifiers = qualTbl }) $ do
    env0 <- Map.unionsWith (++) <$> mapM envModule xs
    local (\st -> st{ env = env0 }) $ mapM qualModule xs

envModule :: (FilePath, Module) -> M (Map Text [Name])
envModule (fn, Module _ ds) = do
  bs <- uniqueBindings ds
  pure $ Map.fromList [ (textOf n, [Name (positionOf n) $ Text.pack fn]) | n <- bs ]

qualModule :: (FilePath, Module) -> M (FilePath, Module)
qualModule x@(fn, Module pos ds) = do
  env' <- envModule x
  local (\st -> st{ env = Map.union env' $ env st }) $ (fn,) . Module pos <$> mapM (qualDecl $ Text.pack fn) ds

subEnv :: Bindings a => a -> M b -> M b
subEnv x m = do
  ks <- fmap textOf <$> uniqueBindings x
  local (\st -> st{ env = List.foldr Map.delete (env st) ks }) m

tupleElemExpToTupleElemPat :: TupleElemExp -> M TupleElemPat
tupleElemExpToTupleElemPat (TupleElemExp pos a) = TupleElemPat pos <$> expToPat a

expToPat :: Exp -> M Pat
expToPat x = case x of
  Parens pos a -> PParens pos <$> expToPat a
  Tuple pos a bs -> PTuple pos <$> tupleElemExpToTupleElemPat a <*> mapM tupleElemExpToTupleElemPat bs
  Typed pos a t -> PTyped pos <$> expToPat a <*> pure t
  Unit pos -> pure $ PUnit pos
  Var pos v -> pure $ PVar pos v
  _ -> err100 "expression where pattern expected" x

uniqueBindings :: Bindings a => a -> M [Name]
uniqueBindings x = do
  let bs = bindings x
  let cs = List.nub bs
  case bs List.\\ cs of
    [] -> pure bs
    bs' -> errn00 "duplicate names" $ filter (`elem` bs') bs

lookupName :: (HasText a, Pretty a, Positioned a) => a -> M (Maybe UIdent)
lookupName n = do
  tbl <- asks env
  case Map.lookup (textOf n) tbl of
    Nothing -> pure Nothing
    Just qs -> case qs of
      [q] -> pure $ Just $ mkTok (positionOf n) (textOf q)
      _ -> err1n0 "ambiguous name" n qs

qualLayoutElemExpDecl :: LayoutElemExpDecl -> M LayoutElemExpDecl
qualLayoutElemExpDecl (LayoutElemExpDecl pos a) = LayoutElemExpDecl pos <$> qualExpDecl a

qualLayoutElemFieldDecl :: LayoutElemFieldDecl -> M LayoutElemFieldDecl
qualLayoutElemFieldDecl (LayoutElemFieldDecl pos a) = LayoutElemFieldDecl pos <$> qualFieldDecl a

qualFieldDecl :: FieldDecl -> M FieldDecl
qualFieldDecl (FieldDecl pos fld e) = FieldDecl pos fld <$> qualExp e

qualLayoutElemCaseAlt :: LayoutElemCaseAlt -> M LayoutElemCaseAlt
qualLayoutElemCaseAlt (LayoutElemCaseAlt pos a) = LayoutElemCaseAlt pos <$> qualCaseAlt a

qualCaseAlt :: CaseAlt -> M CaseAlt
qualCaseAlt (CaseAlt pos altp e) = CaseAlt pos altp <$> subEnv altp (qualExp e)

qualExpDecl :: ExpDecl -> M ExpDecl
qualExpDecl x = case x of
  Binding pos p e -> Binding pos p <$> qualExp e -- binding p already removed from env
  TailRec pos a -> TailRec pos <$> qualTailRecDecls a

qualTailRecDecls :: TailRecDecls -> M TailRecDecls
qualTailRecDecls (TailRecDecls pos ds) = TailRecDecls pos <$> mapM qualLayoutElemTailRecDecl ds -- don't remove the ds bindings

qualLayoutElemTailRecDecl :: LayoutElemTailRecDecl -> M LayoutElemTailRecDecl
qualLayoutElemTailRecDecl (LayoutElemTailRecDecl pos a) = LayoutElemTailRecDecl pos <$> qualTailRecDecl a

qualTailRecDecl :: TailRecDecl -> M TailRecDecl
qualTailRecDecl (TailRecDecl pos a b c) = TailRecDecl pos a b <$> subEnv b (qualExp c) -- binding 'a' should not be removed from env

qualTupleElemExp :: TupleElemExp -> M TupleElemExp
qualTupleElemExp (TupleElemExp pos e) = TupleElemExp pos <$> qualExp e

qualInfixInfo :: InfixInfo -> M InfixInfo
qualInfixInfo (InfixInfo pos qn fx pr) = InfixInfo pos <$> qualQualLIdent qn <*> pure fx <*> pure pr

qualify :: UIdent -> M UIdent
qualify q | textOf q == "Prim" = pure q
qualify q = do
  tbl <- asks qualifiers
  case Map.lookup q tbl of
    Nothing -> err100 "unknown qualifier" q
    Just fn -> pure $ mkTok (positionOf q) fn

qualQualLIdent :: QualLIdent -> M QualLIdent
qualQualLIdent x = case x of
  Qual pos q n -> Qual pos <$> qualify q <*> pure n
  UnQual pos n -> do
    mq <- lookupName n
    pure $ case mq of
      Nothing -> x
      Just q -> Qual pos q n

qualDecl :: Text -> Decl -> M Decl
qualDecl fn x = case x of
  ExpDecl pos d -> ExpDecl pos . mkQNameExpDecl fn <$> qualExpDecl d
  InfixDecl pos n a -> InfixDecl pos n <$> qualInfixInfo a
  PrefixDecl pos n m -> PrefixDecl pos n <$> qualQualLIdent m
  TypeDecl pos n t -> TypeDecl pos (mkQName fn n) <$> qualType t
  QualDecl{} -> pure x
  ExportDecl pos s n t -> ExportDecl pos s <$> qualQualLIdent n <*> qualType t

mkQNameExpDecl :: Text -> ExpDecl -> ExpDecl
mkQNameExpDecl fn x = case x of
  Binding pos p e -> Binding pos (mkQNameBinding fn p) e
  TailRec pos d -> TailRec pos (mkQNameTailRecDecls fn d)

mkQNameTailRecDecls :: Text -> TailRecDecls -> TailRecDecls
mkQNameTailRecDecls fn (TailRecDecls pos bs) = TailRecDecls pos $ fmap (mkQNameLayoutElemTailRecDecl fn) bs

mkQNameLayoutElemTailRecDecl :: Text -> LayoutElemTailRecDecl -> LayoutElemTailRecDecl
mkQNameLayoutElemTailRecDecl fn (LayoutElemTailRecDecl pos a) = LayoutElemTailRecDecl pos $ mkQNameTailRecDecl fn a

mkQNameTailRecDecl :: Text -> TailRecDecl -> TailRecDecl
mkQNameTailRecDecl fn (TailRecDecl pos a b c) = TailRecDecl pos (mkQName fn a) b c

mkQNameBinding :: Text -> Binding -> Binding
mkQNameBinding fn = transformBi (mkQName fn :: LIdent -> LIdent)

qualLayoutElemIfBranch :: LayoutElemIfBranch -> M LayoutElemIfBranch
qualLayoutElemIfBranch (LayoutElemIfBranch pos a) = LayoutElemIfBranch pos <$> qualIfBranch a

qualIfBranch :: IfBranch -> M IfBranch
qualIfBranch (IfBranch pos a b) = IfBranch pos <$> qualExp a <*> qualExp b

qualTField :: TField -> M TField
qualTField (TField pos fld t) = TField pos fld <$> qualType t

qualLayoutElemTField :: LayoutElemTField -> M LayoutElemTField
qualLayoutElemTField (LayoutElemTField pos a) = LayoutElemTField pos <$> qualTField a

qualTSum :: TSum -> M TSum
qualTSum x = case x of
  TCon pos c t -> TCon pos c <$> qualType t
  TEnum{} -> pure x

qualLayoutElemTSum :: LayoutElemTSum -> M LayoutElemTSum
qualLayoutElemTSum (LayoutElemTSum pos a) = LayoutElemTSum pos <$> qualTSum a

qualTupleElemType :: TupleElemType -> M TupleElemType
qualTupleElemType (TupleElemType pos a) = TupleElemType pos <$> qualType a

qualType :: Type -> M Type
qualType x = case x of
  -- BAL: TName's should be eliminated since all type decls are top level
  TName pos n -> do
    mq <- lookupName n
    pure $ case mq of
      Nothing -> x
      Just q -> TQualName pos q n

  TQualName pos q n -> TQualName pos <$> qualify q <*> pure n
  TArray{} -> pure x
  TChar{} -> pure x
  TFloat{} -> pure x
  TInt{} -> pure x
  TPointer{} -> pure x
  TSize{} -> pure x
  TSizes{} -> pure x
  TString{} -> pure x
  TUInt{} -> pure x
  TUnit{} -> pure x
  TBool{} -> pure x
  TVar{} -> pure x
  TOpaque{} -> pure x

  TLam pos vs t -> TLam pos vs <$> go t
  TFun pos a b -> TFun pos <$> go a <*> go b
  TApp pos a b -> TApp pos <$> go a <*> go b
  TParens pos a -> TParens pos <$> go a

  TRecord pos bs -> TRecord pos <$> mapM qualLayoutElemTField bs
  TSum pos bs -> TSum pos <$> mapM qualLayoutElemTSum bs
  TTuple pos a bs -> TTuple pos <$> qualTupleElemType a <*> mapM qualTupleElemType bs

  where
    go = qualType

qualExp :: Exp -> M Exp
qualExp x = case x of
  Lam pos bs e -> Lam pos bs <$> subEnv bs (go e)
  Where pos e ds -> subEnv ds (Where pos <$> go e <*> mapM qualLayoutElemExpDecl ds)
  Do pos bs -> Do pos <$> qualLayoutElemStmts bs
  Case pos e alts -> Case pos <$> go e <*> mapM qualLayoutElemCaseAlt alts

  Var pos v -> do
    mq <- lookupName v
    pure $ case mq of
      Nothing -> x
      Just q -> Qualified pos q v

  InfixOper pos a op b -> InfixOper pos <$> go a <*> pure op <*> go b
  PrefixOper pos op e -> PrefixOper pos op <$> go e

  Unit{} -> pure x
  Scalar{} -> pure x

  Con{} -> pure x
  Select{} -> unreachable001 "qualExp:Select already simplified" x

  Array pos es -> Array pos <$> mapM go es
  XArray pos es -> go $ Array pos $ fmap newtypeOf es

  Record pos ds -> Record pos <$> sequence [ FieldDecl p fld <$> go e | FieldDecl p fld e <- ds ]
  XRecord pos ds -> go $ Record pos $ fmap newtypeOf ds

  XDot pos e fld -> case e of
    Con _ q -> qualExp $ Qualified pos q $ mkTok (positionOf fld) (textOf fld)
    _ -> Select pos <$> go e <*> pure fld

  Qualified pos q v -> Qualified pos <$> qualify q <*> pure v

  Typed pos e t -> Typed pos <$> go e <*> qualType t
  With pos e ds -> With pos <$> go e <*> mapM qualLayoutElemFieldDecl ds
  App pos a b -> App pos <$> go a <*> go b
  EType pos t -> EType pos <$> qualType t
  Parens pos a -> Parens pos <$> go a
  Tuple pos a bs -> Tuple pos <$> qualTupleElemExp a <*> mapM qualTupleElemExp bs
  If pos bs -> If pos <$> mapM qualLayoutElemIfBranch bs
  Extern pos a t -> Extern pos a <$> qualType t

  where
     go = qualExp

qualLayoutElemStmts :: [LayoutElemStmt] -> M [LayoutElemStmt]
qualLayoutElemStmts [] = pure []
qualLayoutElemStmts (LayoutElemStmt pos x : ys) = do
  (x', ys') <- case x of
    Let{} -> unreachable001 "qualLayoutElemStmts: 'let' already simplified" x
    XLet pos1 pe e -> do
      p <- expToPat pe
      (,) <$> (Let pos1 p <$> qualExp e) <*> subEnv p (go ys)
    TailRecLet pos1 a -> (,) <$> (TailRecLet pos1 <$> qualTailRecDecls a) <*> subEnv a (go ys)
    Stmt pos1 e -> (,) <$> (Stmt pos1 <$> qualExp e) <*> go ys
  pure (LayoutElemStmt pos x' : ys')
  where
    go = qualLayoutElemStmts

