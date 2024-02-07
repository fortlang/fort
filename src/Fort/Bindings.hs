module Fort.Bindings (bindings, Bindings) where

import Fort.Utils
import qualified Data.List as List

class Bindings a where
  bindings :: a -> [Name] -- list instead of Set for reporting of errors

instance Bindings Binding where
  bindings x = case x of
    Delayed _ p -> bindings p
    Immediate _ p -> bindings p

instance Bindings TailRecDecl where
  bindings (TailRecDecl _ v _ _) = bindings v

instance Bindings TailRecDecls where
  bindings (TailRecDecls _ ds) = bindings ds

instance Bindings Pat where
  bindings x = case x of
    PParens _ p -> bindings p
    PTuple _ ps -> bindings (toList ps)
    PTyped _ p _ -> bindings p
    PUnit _ -> mempty
    PVar _ v -> bindings v

instance Bindings a => Bindings (NonEmpty a) where
  bindings = concat . toList . fmap bindings

instance Bindings a => Bindings [a] where
  bindings = List.concatMap bindings

instance Bindings Decl where
  bindings x = case x of
    QualDecl{} -> mempty
    ExportDecl{} -> mempty
    ExpDecl _ a -> bindings a
    InfixDecl _ op _ -> [nameOf op]
    PrefixDecl _ op _ -> [nameOf op]
    TypeDecl _ c _ -> [nameOf c]

instance Bindings LIdent where
  bindings x = [nameOf x]

instance Bindings ExpDecl where
  bindings x = case x of
   Binding _ a _ -> bindings a
   TailRec _ a -> bindings a

instance Bindings AltPat where
  bindings x = case x of
    PCon _ _ p -> bindings p
    PDefault _ v -> bindings v
    _ -> mempty
