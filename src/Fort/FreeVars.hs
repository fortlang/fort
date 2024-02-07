module Fort.FreeVars (freeVarsOf, typeNames) where

import Fort.Bindings
import Fort.Utils

class FreeVars a where
  freeVars :: a -> [Name] -- list instead of set so we can compute number of occurances

singleton :: a -> [a]
singleton = (:[])

insert :: a -> [a] -> [a]
insert = (:)

union :: [a] -> [a] -> [a]
union = (++)

neunions :: Foldable t => t [a] -> [a]
neunions = unions . toList

unions :: [[a]] -> [a]
unions = concat

difference :: Eq a => [a] -> [a] -> [a]
difference bs cs = filter (`notElem` cs) bs

typeNames :: Type -> [Name]
typeNames x = [ Name pos $ mkQNameText (textOf a) (textOf b) | TQualName pos a b <- universe x ]

freeVarsOf :: (Data a, FreeVars a) => a -> [Name]
freeVarsOf x = unions (freeVars x : [ typeNames t | t :: Type <- universeBi x ])

instance FreeVars Decl where
  freeVars x = case x of
    ExpDecl _ a -> freeVars a
    InfixDecl _ _ (InfixInfo _ n _ _) -> singleton $ nameOf n
    PrefixDecl _ _ n -> singleton $ nameOf n
    TypeDecl{} -> mempty
    QualDecl{} -> mempty
    ExportDecl _ _ n _ -> singleton $ nameOf n

instance FreeVars ExpDecl where
  freeVars x = case x of
    Binding _ v e -> freeVars e `difference` bindings v
    TailRec _ d -> freeVars d

instance FreeVars FieldDecl where
  freeVars (FieldDecl _ _ e) = freeVars e

instance FreeVars CaseAlt where
  freeVars (CaseAlt _ altp e) = freeVars e `difference` bindings altp

freeVarsStmts :: NonEmpty Stmt -> [Name]
freeVarsStmts (b :| bs) = case b of
  Stmt _ e -> freeVars e `union` fvs
  Let _ p e -> freeVars e `union` (fvs `difference` bindings p)
  TailRecLet _ d -> freeVars d `union` (fvs `difference` bindings d)
  where
    fvs = case bs of
      [] -> mempty
      c : cs -> freeVarsStmts (c :| cs)

instance FreeVars Exp where
  freeVars x = case x of
    Where _ a bs -> neunions (freeVars a <| fmap freeVars bs) `difference` bindings bs
    Do _ bs -> freeVarsStmts bs

    Var _ v -> singleton $ nameOf v
    Qualified pos a b -> singleton $ nameOf $ Qual pos a b

    Lam _ ps e -> freeVars e `difference` bindings ps
    Case _ a bs -> neunions (freeVars a <| fmap freeVars bs)
    With _ e ds -> neunions (freeVars e <| fmap freeVars ds)

    Typed _ a _ -> freeVars a
    EType{} -> mempty
    Extern{} -> mempty

    InfixOper _ a op b -> nameOf op `insert` freeVars a `union` freeVars b
    PrefixOper _ op a -> nameOf op `insert` freeVars a
    App _ a b -> freeVars a `union` freeVars b
    Array _ es -> neunions $ fmap freeVars es
    If _ a b c -> unions $ fmap freeVars [a, b, c]
    Else _ a b -> unions $ fmap freeVars [a, b]
    Parens _ a -> freeVars a
    Record _ bs -> neunions $ fmap freeVars bs
    Select _ a _ -> freeVars a
    Tuple _ bs -> neunions $ fmap freeVars bs

    Con{} -> mempty
    Unit{} -> mempty
    Scalar{} -> mempty

instance FreeVars TailRecDecl where
  freeVars (TailRecDecl _ a b e) = freeVars e `difference` (bindings a ++ bindings b)

instance FreeVars TailRecDecls where
  freeVars x@(TailRecDecls _ ds) = neunions (fmap freeVars ds) `difference` bindings x

