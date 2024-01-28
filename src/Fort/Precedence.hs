-- | This module reorders infix operators based on user defined precedences.  (the parser simply parses them all the same way).
--
module Fort.Precedence (fixInfixOpsModules) where

import Fort.Utils
import qualified Data.List as List
import qualified Data.Map as Map

type M a = ReaderT St IO a

data St = St
  { infixOps :: Map Text [(Name, (Fixity, Double))]
  , prefixOps :: Map Text [Name]
  }

fixInfixOpsModules :: [(FilePath, Module)] -> IO [(FilePath, Module)]
fixInfixOpsModules xs = runReaderT (mapM precModule xs) (envModules $ fmap snd xs)

lookupInfixOp :: InfixOp -> M (Fixity, Double)
lookupInfixOp op = do
  tbl <- asks infixOps
  case Map.lookup (textOf op) tbl of
    Nothing -> err100 "unknown infix operator" op
    Just [a] -> pure $ snd a
    Just bs -> err1n0 "duplicate infix operator" op $ fmap fst bs

lookupPrefixOp :: PrefixOp -> M ()
lookupPrefixOp op = do
  tbl <- asks prefixOps
  case Map.lookup (textOf op) tbl of
    Nothing -> err100 "unknown prefix operator" op
    Just [_] -> pure ()
    Just bs -> err1n0 "duplicate prefix operator" op bs

envModules :: [Module] -> St
envModules xs = St
  { infixOps =
      List.foldr (\(k, v) -> Map.insertWith (List.++) k [v]) mempty $
      List.concatMap infixBindings xs
  , prefixOps =
      List.foldr (\(k, v) -> Map.insertWith (List.++) k [v]) mempty $
      List.concatMap prefixBindings xs
  }

prefixBindings :: Module -> [(Text, Name)]
prefixBindings (Module _ ds) = List.concatMap f ds
  where
    f x = case x of
      PrefixDecl _ op _ -> [(textOf op, nameOf op)]
      _ -> []

infixBindings :: Module -> [(Text, (Name, (Fixity, Double)))]
infixBindings (Module _ ds) = List.concatMap f ds
  where
    f x = case x of
      InfixDecl _ op (InfixInfo _ _ fx pr) ->
        [(textOf op, (nameOf op, (fx, valOf pr)))]
      _ -> []

precModule :: (FilePath, Module) -> M (FilePath, Module)
precModule (fn, m) = (fn, ) <$> rewriteBiM precExp m

precExp :: Exp -> M (Maybe Exp)
precExp x = case x of
  InfixOper pos a op (InfixOper _ b op' c) -> do
    (fixity, pr) <- lookupInfixOp op
    (fixity', pr') <- lookupInfixOp op'
    let reassoc = pure $ Just $ InfixOper pos (InfixOper pos a op b) op' c
    if
      | pr > pr' -> reassoc
      | pr' > pr -> ignore
      | otherwise -> case (fixity, fixity') of
          (InfixR _, InfixR _) -> ignore
          (InfixL _, InfixL _) -> reassoc
          _ -> err110 "ambiguous operators.  add parens to disambiguate" op op'
  InfixOper pos (InfixOper _ a op b) op' c -> do
    (fixity, pr) <- lookupInfixOp op
    (fixity', pr') <- lookupInfixOp op'
    let reassoc = pure $ Just $ InfixOper pos a op (InfixOper (positionOf b) b op' c) -- BAL: check positions
    if
      | pr > pr' -> ignore
      | pr' > pr -> reassoc
      -- ^ due to the way the parser works, this is unreachable
      | otherwise -> case (fixity, fixity') of
          (InfixL _, InfixL _) -> ignore
          (InfixR _, InfixR _) -> reassoc
          -- ^ due to the way the parser works, this is unreachable
          _ -> err110 "ambiguous operators.  add parens to disambiguate" op op'
          -- ^ due to the way the parser works, this is unreachable
  InfixOper _ _ op _ -> lookupInfixOp op >> ignore
  PrefixOper _ op _ -> lookupPrefixOp op >> ignore
  _ -> ignore
  where
    ignore :: M (Maybe Exp)
    ignore = pure Nothing

