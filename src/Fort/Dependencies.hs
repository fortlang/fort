module Fort.Dependencies (dependenciesModules, reachableDecls, depGraph, Exported(..))

where

import Data.Graph
import Fort.Bindings
import Fort.FreeVars
import Fort.Utils
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

data Exported
  = Main LIdent [Decl]
  | Exported QualLIdent Type [Decl]
  deriving Show

instance Pretty Exported where
  pretty x = case x of
    Main n ds -> "main" <+> pretty n <+> "=" <+> vlist "do" (fmap pretty ds)
    Exported q t ds -> "exported" <+> pretty q <+> ":" <+> pretty t <+> "=" <+> vlist "do" (fmap pretty ds)

-- if we don't find a binding, we assume it's in a where clause and will be checked for in a later pass
dependenciesModules :: MonadIO m => Text -> [FilePath] -> [(FilePath, Module)] -> m ([Decl], [(FilePath, Map AString Exported)])
dependenciesModules mainNm fns ms = do
  bld <- reachableDecls gr (Set.fromList $ catMaybes $ fmap toBuildName allDecls)
  (bld,) <$> sequence [ (fn, ) <$> dependenciesModule mainNm gr fn ds | (fn, Module _ ds) <- ms, fn `List.elem` fns ]
  where
    allDecls = concat [ ds | (_, Module _ ds) <- ms ]
    gr = depGraph allDecls

toBuildName :: Decl -> Maybe Name
toBuildName (ExpDecl _ (Binding _ (Immediate _ x) _)) = go x
  where
    go p0 = case p0 of
      PParens _ p -> go p
      PTyped _ p _ -> go p
      PVar _ v | ".build" `Text.isSuffixOf` textOf v -> Just $ nameOf v
      _ -> Nothing

toBuildName _ = Nothing

dependenciesModule :: MonadIO m => Text -> DepGraph -> FilePath -> [Decl] -> m (Map AString Exported)
dependenciesModule mainNm gr fn ds0 = do
  exs0 <- mainReaches
  bs <- exportedFuncs ds0
  exs1 <- sequence [ (n, ) . Exported v t <$> reachableDecls gr (Set.fromList (nameOf v : typeNames t)) | (n, (v, t)) <- bs ]
  pure $ Map.fromList (exs0 ++ exs1)
  where
    mainReaches = case filter ((== qv) . textOf) vs of
      [] -> pure []
      [v] -> do
        ds <- reachableDecls gr (Set.singleton $ nameOf v)
        pure [(AString (positionOf v) "main", Main v ds)]
      _ -> unreachablen00 "multiple mains" vs
      where
        vs = concat [ universeBi b | ExpDecl _ (Binding _ b _) <- ds0 ]
        qv = mkQNameText (Text.pack fn) mainNm

exportedFuncs :: MonadIO m => [Decl] -> m [(AString, (QualLIdent, Type))]
exportedFuncs ds = do
  let bs = [ n | ExportDecl _ n _ _ <- ds ]
  let cs = List.nub bs
  case bs List.\\ cs of
    [] -> pure [ (a, (b, c)) | ExportDecl _ a b c <- ds ]
    bs' -> errn00 "duplicate export names" [ n | ExportDecl _ n _ _ <- ds, n `elem` bs' ]

reachableDecls :: MonadIO m => DepGraph -> Set Name -> m [Decl]
reachableDecls gr nms = catMaybes <$> mapM f (sccs gr)
  where
    verts = catMaybes [ Map.lookup v (binds gr) | v <- Set.toList nms ]
    reaches = Set.fromList $ concatMap (reachable (graph gr)) verts
    f ascc = case ascc of
      AcyclicSCC (d, v, _) | Set.member v reaches -> pure $ Just d
      CyclicSCC bs -> errn00 "definitions form a cycle" [ d | (d, _, _) <- bs ]
      _ -> pure Nothing

depGraph :: [Decl] -> DepGraph
depGraph ds = DepGraph
    { graph = gr
    , binds = bnds
    , sccs = stronglyConnCompR edgs
    }
  where
    (gr, _, _) = graphFromEdges edgs

    edgs :: [(Decl, Vertex, [Vertex])]
    edgs = [ (d, i, catMaybes [ Map.lookup v bnds | v <- List.nub $ freeVarsOf d ]) | (i, d) <- nodes ]

    nodes :: [(Vertex, Decl)]
    nodes = zip [0..] ds

    bnds :: Map Name Vertex
    bnds = Map.fromList $ concat [ [ (v, i) | v <- bindings d ] | (i, d) <- nodes ]

data DepGraph = DepGraph
  { graph :: Graph
  , binds :: Map Name Vertex
  , sccs :: [SCC (Decl, Vertex, [Vertex])]
  }
