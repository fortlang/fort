-- | This module qualifies free variables and type names.  E.g. an unqualified free variable 'foo' will be changed to '<filepath>.foo'.
-- User qualified names are left unchanged.  When they are resolved in later passes there with be a mapping from UIdent -> filepath.
-- Operator names are global and left unchanged.

module Fort.Qualify (qualifyModules) where

import Fort.Bindings
import Fort.Utils
import qualified Data.List as List
import qualified Data.List.NonEmpty as NE
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
    f :: (UIdent, [(UIdent, FilePath)]) -> M (UIdent, Text)
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
  local (\st -> st{ env = Map.union env' $ env st }) $ do
    ds' <- mapM (qualDecl $ Text.pack fn) ds
    ds'' <- qualAllTypes ds'
    pure (fn, Module pos ds'')

subEnv :: Bindings a => a -> M b -> M b
subEnv x m = do
  ks <- fmap textOf <$> uniqueBindings x
  local (\st -> st{ env = List.foldr Map.delete (env st) ks }) m


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

qualCaseAlt :: CaseAlt -> M CaseAlt
qualCaseAlt (CaseAlt pos altp e) = CaseAlt pos altp <$> subEnv altp (qualExp e)

qualExpDecl :: ExpDecl -> M ExpDecl
qualExpDecl x = case x of
  Binding pos p e -> Binding pos p <$> qualExp e -- binding p already removed from env

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
  TypeDecl pos n t -> pure $ TypeDecl pos (mkQName fn n) t
  QualDecl{} -> pure x
  ExportDecl pos s n t -> ExportDecl pos s <$> qualQualLIdent n <*> pure t

mkQNameExpDecl :: Text -> ExpDecl -> ExpDecl
mkQNameExpDecl fn x = case x of
  Binding pos p e -> Binding pos (mkQNameBinding fn p) e

mkQNameBinding :: Text -> Binding -> Binding
mkQNameBinding fn = transformBi (mkQName fn :: LIdent -> LIdent)

qualAllTypes :: Data a => a -> M a
qualAllTypes = transformBiM qualType

qualType :: Type -> M Type
qualType x = case x of
  -- TName's can be eliminated since all type decls are top level
  TName pos n -> do
    mq <- lookupName n
    pure $ case mq of
      Nothing -> x
      Just q -> TQualName pos q n
  TQualName pos q n -> TQualName pos <$> qualify q <*> pure n
  _ -> pure x

qualExp :: Exp -> M Exp
qualExp x = case x of
  Lam pos bs e -> Lam pos bs <$> subEnv bs (go e)
  Where pos e ds -> subEnv ds (Where pos <$> go e <*> mapM qualExpDecl ds)
  Do pos bs -> Do pos <$> qualStmts bs
  Case pos e alts -> Case pos <$> go e <*> mapM qualCaseAlt alts

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
  Select pos e fld -> Select pos <$> go e <*> pure fld

  Array pos es -> Array pos <$> mapM go es

  Record pos ds -> Record pos . NE.fromList <$> sequence [ FieldDecl p fld <$> go e | FieldDecl p fld e <- toList ds ]

  Qualified pos q v -> Qualified pos <$> qualify q <*> pure v

  Typed pos e t -> Typed pos <$> go e <*> pure t
  With pos e ds -> With pos <$> go e <*> mapM qualFieldDecl ds
  App pos a b -> App pos <$> go a <*> go b
  EType{} -> pure x
  Parens pos a -> Parens pos <$> go a
  Tuple pos bs -> Tuple pos <$> mapM qualExp bs
  If pos a b c -> If pos <$> qualExp a <*> qualExp b <*> qualExp c
  Else pos a b -> Else pos <$> qualExp a <*> qualExp b
  Extern{} -> pure x

  where
     go = qualExp

qualFieldDecl :: FieldDecl -> M FieldDecl
qualFieldDecl (FieldDecl pos fld e) = FieldDecl pos fld <$> qualExp e

qualStmts :: NonEmpty Stmt -> M (NonEmpty Stmt)
qualStmts (x :| ys) = do
  case x of
    Let pos p e -> (:|) <$> (Let pos p <$> qualExp e) <*> subEnv p ys'
    Stmt pos e -> (:|) <$> (Stmt pos <$> qualExp e) <*> ys'
  where
    ys' = case ys of
      [] -> pure []
      y : rest -> toList <$> qualStmts (y :| rest)


