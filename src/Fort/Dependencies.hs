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
dependenciesModules :: MonadIO m => Text -> [FilePath] -> [(FilePath, Module)] -> m [(FilePath, Map Text Exported)]
dependenciesModules mainNm fns ms = do
  sequence [ (fn, ) <$> reaches fn ds | (fn, Module _ ds) <- ms, fn `List.elem` fns ]
  where
    reaches fn ds = do
      exs0 <- mainReaches fn ds
      bs <- exportedFuncs ds
      exs1 <- sequence [ (n, ) . Exported v t <$> reachableDecls gr (Set.fromList (nameOf v : typeNames t)) | (n, (v, t)) <- bs ]
      pure $ Map.fromList (exs0 ++ exs1)

    gr = modulesDepGraph $ fmap snd ms

    mainReaches fn ds0 = case filter (== qv) vs of
      v : _ -> do
        ds <- reachableDecls gr (Set.singleton $ nameOf v)
        pure [("main", Main v ds)]
      [] -> pure []
      where
        vs = concat [ universeBi b | ExpDecl _ (Binding _ b _) <- ds0 ]
        qv = mkTok noPosition $ mkQNameText (Text.pack fn) mainNm

exportedFuncs :: MonadIO m => [Decl] -> m [(Text, (QualLIdent, Type))]
exportedFuncs ds = do
  let bs = [ textOf n | ExportDecl _ n _ _ <- ds ]
  let cs = List.nub bs
  case bs List.\\ cs of
    [] -> pure [ (textOf a, (b, c)) | ExportDecl _ a b c <- ds ]
    bs' -> errn00 "duplicate export names" [ n | ExportDecl _ n _ _ <- ds, textOf n `elem` bs' ]

modulesDepGraph :: [Module] -> DepGraph
modulesDepGraph ms = depGraph $ concat [ ds | Module _ ds <- ms ]

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
