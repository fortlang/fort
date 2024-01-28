module Fort.FreeVars (freeVars) where

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

unions :: [[a]] -> [a]
unions = concat

difference :: Eq a => [a] -> [a] -> [a]
difference bs cs = filter (`notElem` cs) bs

instance FreeVars Decl where
  freeVars x = case x of
    ExpDecl _ a -> freeVars a
    InfixDecl _ _ (InfixInfo _ n _ _) -> singleton $ nameOf n
    PrefixDecl _ _ n -> singleton $ nameOf n
    TypeDecl _ _ t -> freeVars t
    QualDecl{} -> mempty
    ExportDecl _ _ n t -> insert (nameOf n) $ freeVars t

instance FreeVars Type where
  freeVars x = [ Name pos $ mkQNameText (textOf a) (textOf b) | TQualName pos a b <- universe x ]

instance FreeVars ExpDecl where
  freeVars x = case x of
    Binding _ _ e -> freeVars e `difference` bindings x
    TailRec _ d -> freeVars d

instance FreeVars FieldDecl where
  freeVars (FieldDecl _ _ e) = freeVars e

instance FreeVars IfBranch where
  freeVars (IfBranch _ a b) = freeVars a `union` freeVars b

instance FreeVars LayoutElemIfBranch where
  freeVars (LayoutElemIfBranch _ a) = freeVars a

instance FreeVars TupleElemExp where
  freeVars (TupleElemExp _ e) = freeVars e

instance FreeVars LayoutElemFieldDecl where
  freeVars (LayoutElemFieldDecl _ d) = freeVars d

instance FreeVars CaseAlt where
  freeVars (CaseAlt _ altp e) = freeVars e `difference` bindings altp

instance FreeVars LayoutElemCaseAlt where
  freeVars (LayoutElemCaseAlt _ d) = freeVars d

freeVarsStmts :: [LayoutElemStmt] -> [Name]
freeVarsStmts [] = mempty
freeVarsStmts (b : bs) =
  let fvs = freeVarsStmts bs in
  case newtypeOf b of
    Stmt _ e -> freeVars e `union` fvs
    Let _ p e -> freeVars e `union` (fvs `difference` bindings p)
    TailRecLet _ d -> freeVars d `union` (fvs `difference` bindings d)
    XLet{} -> unreachable "freeVars: XLet not removed" b

instance FreeVars Exp where
  freeVars x = case x of
    Where _ a bs -> unions (freeVars a : fmap freeVars bs) `difference` bindings bs
    Do _ bs -> freeVarsStmts bs

    Var _ v -> singleton $ nameOf v
    Qualified pos a b -> singleton $ nameOf $ Qual pos a b

    Lam _ ps e -> freeVars e `difference` bindings ps
    Case _ a bs -> freeVars a `union` unions (fmap freeVars bs)
    With _ e ds -> freeVars e `union` unions (fmap freeVars ds)

    Typed _ a b -> freeVars a `union` freeVars b
    EType _ t -> freeVars t
    Extern _ _ t -> freeVars t

    InfixOper _ a op b -> nameOf op `insert` freeVars a `union` freeVars b
    PrefixOper _ op a -> nameOf op `insert` freeVars a
    App _ a b -> freeVars a `union` freeVars b
    Array _ es -> unions $ fmap freeVars es
    If _ bs -> unions $ fmap freeVars bs
    Parens _ a -> freeVars a
    Record _ bs -> unions $ fmap freeVars bs
    Select _ a _ -> freeVars a
    Tuple _ a bs -> unions $ fmap freeVars (a:bs)

    Con{} -> mempty
    Unit{} -> mempty
    Scalar{} -> mempty

    XArray{} -> unreachable "freeVars: XArray not removed" x
    XDot{} -> unreachable "freeVars: XDot not removed" x
    XRecord{} -> unreachable "freeVars: XRecord not removed" x

instance FreeVars TailRecDecl where
  freeVars (TailRecDecl _ a b e) = freeVars e `difference` (bindings a ++ bindings b)

instance FreeVars LayoutElemTailRecDecl where
  freeVars (LayoutElemTailRecDecl _ a) = freeVars a

instance FreeVars LayoutElemExpDecl where
  freeVars (LayoutElemExpDecl _ a) = freeVars a

instance FreeVars TailRecDecls where
  freeVars x@(TailRecDecls _ ds) = unions (fmap freeVars ds) `difference` bindings x

