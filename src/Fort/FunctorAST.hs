{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternSynonyms #-}

module Fort.FunctorAST
  ( module Fort.FunctorAST
  )

where

import Control.Monad
import Control.Monad.IO.Class
import Data.Data (Data, Typeable)
import Data.Foldable
import Data.List.NonEmpty hiding (toList, last, init)
import Data.Text (Text)
import Fort.Abs (UIdentTok(..), BinTok(..), DecTok(..), HexTok(..), OctTok(..), CharTok(..), IntTok(..), PrefixOpTok(..), LIdentTok(..), ADoubleTok(..), AStringTok(..), InfixOpTok(..))
import Fort.Errors
import GHC.Generics (Generic)
import Prelude
import Prettyprinter
import qualified Data.List as List
import qualified Data.List.NonEmpty as NE
import qualified Fort.Abs as Abs

pvcat :: Pretty a => [a] -> Doc ann
pvcat = vcat . fmap pretty

instance Pretty (Module a) where
  pretty (Module _ ds) = pvcat ds

data Module a = Module a [Decl a]
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toModule :: MonadIO m => Abs.Module' Position -> m (Module Position)
toModule (Abs.Module a bs) = Module a <$> mapM toDecl bs

toTupleElemExp (Abs.TupleElemExp _ b) = toExp b

toTupleElemPat (Abs.TupleElemPat _ b) = toPat b

toTupleElemType (Abs.TupleElemType _ b) = toType b

toLayoutElemTField (Abs.LayoutElemTField _ b) = toTField b

toLayoutElemTSum (Abs.LayoutElemTSum _ b) = toTSum b

toLayoutElemExp (Abs.LayoutElemExp _ b) = toExp b

toLayoutElemStmt (Abs.LayoutElemStmt _ b) = toStmt b

toLayoutElemIfBranch (Abs.LayoutElemIfBranch _ b) = toIfBranch b

toLayoutElemCaseAlt (Abs.LayoutElemCaseAlt _ b) = toCaseAlt b

toLayoutElemFieldDecl (Abs.LayoutElemFieldDecl _ b) = toFieldDecl b

toLayoutElemTailRecDecl (Abs.LayoutElemTailRecDecl _ b) = toTailRecDecl b

toLayoutElemExpDecl (Abs.LayoutElemExpDecl _ b) = toExpDecl b

data ADouble a = ADouble a Text
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (ADouble a) where
  pretty (ADouble _ a) = pretty a

toADouble (Abs.ADouble a (ADoubleTok b)) = pure $ ADouble a b

data AString a = AString a Text
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (AString a) where
  pretty (AString _ x) = pretty x

toAString (Abs.AString a (AStringTok b)) = pure $ AString a b

data AltPat a
    = PCon a (UIdent a) (Pat a)
    | PDefault a (LIdent a)
    | PEnum a (UIdent a)
    | PScalar a (Scalar a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (AltPat a) where
  pretty x = case x of
    PEnum _ a -> pretty a
    PCon _ a b -> hsep2 a b
    PScalar _ a -> pretty a
    PDefault _ a -> pretty a

toAltPat x = case x of
  Abs.PCon a b c -> PCon a <$> toUIdent b <*> toPat c
  Abs.PDefault a b -> PDefault a <$> toLIdent b
  Abs.PEnum a b -> PEnum a <$> toUIdent b
  Abs.PScalar a b -> PScalar a <$> toScalar b

data Binding a
  = Delayed a (LIdent a)
  | Immediate a (Pat a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Positioned (Binding Position) where
  positionOf x = case x of
    Delayed pos _ -> pos
    Immediate pos _ -> pos

instance Pretty (Binding a) where
  pretty x = case x of
    Delayed _ a -> "~" <> pretty a
    Immediate _ a -> pretty a

toBinding x = case x of
  Abs.Delayed a b -> Delayed a <$> toLIdent b
  Abs.Immediate a b -> Immediate a <$> toPat b

data CaseAlt a = CaseAlt a (AltPat a) (Exp a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toCaseAlt (Abs.CaseAlt a b c) = CaseAlt a <$> toAltPat b <*> toExp c

instance Pretty (CaseAlt a) where
  pretty (CaseAlt _ p e) = binop "->" p e

data Decl a
    = ExpDecl a (ExpDecl a)
    | ExportDecl a (AString a) (QualLIdent a) (Type a)
    | InfixDecl a (InfixOp a) (InfixInfo a)
    | PrefixDecl a (PrefixOp a) (QualLIdent a)
    | QualDecl a (UIdent a) (AString a)
    | TypeDecl a (UIdent a) (Type a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (Decl a) where
  pretty x = case x of
    TypeDecl _ b c -> "type" <+> binop "=" b c
    PrefixDecl _ b c -> "operator" <+> binop "=" b c
    InfixDecl _ b c -> "operator" <+> binop "=" b c
    ExpDecl _ a -> pretty a
    QualDecl _ b c -> "qualifier" <+> binop "=" b c
    ExportDecl _ b c d -> "export" <+> pretty b <+> "=" <+> pretty c <+> "`" <> pretty d <> "`"

toDecl :: MonadIO m => Abs.Decl' Position -> m (Decl Position)
toDecl x = case x of
  Abs.ExpDecl a b -> ExpDecl a <$> toExpDecl b
  Abs.ExportDecl a b c d -> ExportDecl a <$> toAString b <*> toQualLIdent c <*> toType d
  Abs.InfixDecl a b c -> InfixDecl a <$> toInfixOp b <*> toInfixInfo c
  Abs.PrefixDecl a b c -> PrefixDecl a <$> toPrefixOp b <*> toQualLIdent c
  Abs.QualDecl a b c -> QualDecl a <$> toUIdent b <*> toAString c
  Abs.TypeDecl a b c -> TypeDecl a <$> toUIdent b <*> toType c

data Exp a
    = Lam a (Binding a) (Exp a)
    | Where a (Exp a) (NonEmpty (ExpDecl a))
    | Typed a (Exp a) (Type a)
    | With a (Exp a) (NonEmpty (FieldDecl a))
    | InfixOper a (Exp a) (InfixOp a) (Exp a)
    | App a (Exp a) (Exp a)
    | PrefixOper a (PrefixOp a) (Exp a)
    | Array a (NonEmpty (Exp a))
    | Case a (Exp a) (NonEmpty (CaseAlt a))
    | Con a (UIdent a)
    | Do a (NonEmpty (Stmt a))
    | EType a (Type a)
    | Extern a (AString a) (Type a)
    | If a (Exp a) (Exp a) (Exp a)
    | Else a (Exp a) (Exp a)
    | Parens a (Exp a)
    | Qualified a (UIdent a) (LIdent a)
    | Record a (NonEmpty (FieldDecl a))
    | Scalar a (Scalar a)
    | Select a (Exp a) (LIdent a)
    | Tuple a (NonEmpty2 (Exp a))
    | Unit a
    | Var a (LIdent a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (Exp a) where
  pretty x = case x of
    Lam{} -> prettyLam [] x
    If{} -> prettyIf [] x
    Else{} -> prettyIf [] x
    Typed _ b c -> pretty b <+> ":" <+> "`" <> pretty c <> "`"
    With _ b c -> pretty b <+> layout "with" c
    InfixOper _ b c d -> hsep3 b c d
    App _ b c -> hsep2 b c
    PrefixOper _ b c -> pretty b <> pretty c
    Extern _ b c -> "extern" <+> pretty b <+> "`" <> pretty c <> "`" 
    Do _ b -> layout "do" b

    Case _ b c -> "case" <+> pretty b <+> layout "of" c
    Record _ b -> layout "record" b
    Tuple _ cs -> tupled2 $ fmap pretty cs
    Parens _ b -> parens $ pretty b
    Unit _ -> "()"
    Array _ bs -> nelist $ fmap pretty bs
    EType _ b -> "`" <> pretty b <> "`"
    Var _ b -> pretty b
    Con _ b -> pretty b
    Scalar _ b -> pretty b
    Select _ b c -> pretty b <> "." <> pretty c
    Qualified _ b c -> pretty b <> "." <> pretty c
    Where _ b c -> pretty b <+> layout "where" c

prettyLam xs y = case y of
  Lam _ a b -> prettyLam (a : xs) b
  _ -> "\\" <+> hsep (fmap pretty $ List.reverse xs) <+> "->" <+> pretty y

prettyIf xs y = case y of
  Else _ a b -> layout "if" $ NE.reverse $ NE.fromList (IfBranch a b : xs)
  If _ a b c -> prettyIf (IfBranch a b : xs) c
  _ -> unreachable "malformed 'if'" y

data IfBranch a = IfBranch (Exp a) (Exp a)

instance Pretty (IfBranch a) where
  pretty (IfBranch a b) = binop "->" a b

toLayoutElemTSum :: MonadIO m => Abs.LayoutElemTSum' Position -> m (TSum Position)
toLayoutElemExp :: MonadIO m => Abs.LayoutElemExp' Position -> m (Exp Position)
toLayoutElemStmt :: MonadIO m => Abs.LayoutElemStmt' Position -> m (Stmt Position)
toLayoutElemIfBranch :: MonadIO m => Abs.LayoutElemIfBranch' Position -> m (Exp Position, Exp Position)
toLayoutElemCaseAlt :: MonadIO m => Abs.LayoutElemCaseAlt' Position -> m (CaseAlt Position)
toLayoutElemFieldDecl :: MonadIO m => Abs.LayoutElemFieldDecl' Position -> m (FieldDecl Position)
toLayoutElemTailRecDecl :: MonadIO m => Abs.LayoutElemTailRecDecl' Position -> m (TailRecDecl Position)
toLayoutElemExpDecl :: MonadIO m => Abs.LayoutElemExpDecl' Position -> m (ExpDecl Position)
toADouble :: MonadIO m => Abs.ADouble' Position -> m (ADouble Position)
toAString :: MonadIO m => Abs.AString' Position -> m (AString Position)
toAltPat :: MonadIO m => Abs.AltPat' Position -> m (AltPat Position)
toBinding :: MonadIO m => Abs.Binding' Position -> m (Binding Position)
toCaseAlt :: MonadIO m => Abs.CaseAlt' Position -> m (CaseAlt Position)

prettyLam :: [Binding a] -> Exp a -> Doc ann
prettyIf :: [IfBranch a] -> Exp a -> Doc ann

toExp :: MonadIO m => Abs.Exp' Position -> m (Exp Position)
toExp x = case x of
  Abs.Lam _ bs c -> do
    vs <- mapM toBinding bs
    e <- toExp c
    pure $ foldr (\v -> Lam (positionOf v) v) e $ toList vs
  Abs.If _ bs -> do
    cs <- mapM toLayoutElemIfBranch (fromList bs)
    let (dfltp, dflte) = NE.last cs
    pure $ foldr (\(p, e) -> If (positionOf p) p e) (Else (positionOf dfltp) dfltp dflte) (NE.init cs)
  Abs.Typed a b c -> Typed a <$> toExp b <*> toType c
  Abs.With a b c -> With a <$> toExp b <*> mapM toLayoutElemFieldDecl (fromList c)
  Abs.InfixOper a b c d -> InfixOper a <$> toExp b <*> toInfixOp c <*> toExp d
  Abs.App a b c -> App a <$> toExp b <*> toExp c
  Abs.PrefixOper a b c -> PrefixOper a <$> toPrefixOp b <*> toExp c
  Abs.Array a b -> Array a <$> mapM toExp (fromList b)
  Abs.Case a b c -> Case a <$> toExp b <*> mapM toLayoutElemCaseAlt (fromList c)
  Abs.Con a b -> Con a <$> toUIdent b
  Abs.Do a b -> Do a <$> mapM toLayoutElemStmt (fromList b)
  Abs.EType a b -> EType a <$> toType b
  Abs.Extern a b c -> Extern a <$> toAString b <*> toType c
  Abs.Parens a b -> Parens a <$> toExp b
  Abs.Record a b ->  Record a <$> mapM toFieldDecl (fromList b)
  Abs.Scalar a b -> Scalar a <$> toScalar b
  Abs.Tuple a b c -> Tuple a <$> mapM toTupleElemExp (cons2 b (fromList c))
  Abs.Var a b -> Var a <$> toLIdent b
  Abs.XArray a b -> Array a <$> mapM toLayoutElemExp (fromList b)
  Abs.Where a b cs -> Where a <$> toExp b <*> mapM toLayoutElemExpDecl (fromList cs)

  Abs.XDot a b c -> do
    e <- toExp b
    case e of
      Con _ q -> Qualified a q <$> toLIdent c
      _ -> Select a e <$> toLIdent c

  Abs.XRecord a b -> Record a <$> mapM toLayoutElemFieldDecl (fromList b)
  Abs.Unit a -> pure $ Unit a

data ExpDecl a
    = Binding a (Binding a) (Exp a)
    | TailRec a (TailRecDecls a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (ExpDecl a) where
  pretty x = case x of
    Binding _ b c -> binop "=" b c
    TailRec _ b -> pretty b

toExpDecl x = case x of
  Abs.Binding a b c -> Binding a <$> toBinding b <*> toExp c
  Abs.TailRec a b -> TailRec a <$> toTailRecDecls b

data FieldDecl a = FieldDecl a (LIdent a) (Exp a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toFieldDecl (Abs.FieldDecl a b c) = FieldDecl a <$> toLIdent b <*> toExp c

instance Pretty (FieldDecl a) where
  pretty (FieldDecl _ a b) = binop "=" a b

binop :: (Pretty a, Pretty b) => Doc ann -> a -> b -> Doc ann
binop op a b = pretty a <+> op <+> pretty b
 
data Fixity a
  = InfixL a
  | InfixN a
  | InfixR a
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (Fixity a) where
  pretty x = case x of
    InfixL _ -> "infixl"
    InfixN _ -> "infix"
    InfixR _ -> "infixr"

toFixity x = case x of
  Abs.InfixL a -> pure $ InfixL a
  Abs.InfixN a -> pure $ InfixN a
  Abs.InfixR a -> pure $ InfixR a

toIfBranch (Abs.IfBranch _ b c) = (,) <$> toExp b <*> toExp c

toTupleElemExp :: MonadIO m => Abs.TupleElemExp' Position -> m (Exp Position)
toTupleElemPat :: MonadIO m => Abs.TupleElemPat' Position -> m (Pat Position)
toTupleElemType :: MonadIO m => Abs.TupleElemType' Position -> m (Type Position)
toLayoutElemTField :: MonadIO m => Abs.LayoutElemTField' Position -> m (TField Position)

data InfixInfo a
    = InfixInfo a (QualLIdent a) (Fixity a) (ADouble a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

hsep2 :: (Pretty a, Pretty b) => a -> b -> Doc ann
hsep2 a b = pretty a <+> pretty b

hsep3 :: (Pretty a, Pretty b, Pretty c) => a -> b -> c -> Doc ann
hsep3 a b c = pretty a <+> pretty b <+> pretty c

instance Pretty (InfixInfo a) where
  pretty (InfixInfo _ a b c) = hsep3 a b c

toInfixInfo :: MonadIO m => Abs.InfixInfo' Position -> m (InfixInfo Position)
toInfixInfo (Abs.InfixInfo a b c d) = InfixInfo a <$> toQualLIdent b <*> toFixity c <*> toADouble d

data InfixOp a = InfixOp a Text
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (InfixOp a) where
  pretty (InfixOp _ x) = pretty x

toInfixOp (Abs.InfixOp a (InfixOpTok b)) = pure $ InfixOp a b

data LIdent a = LIdent a Text
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (LIdent a) where
  pretty (LIdent _ x) = pretty x

toLIdent :: MonadIO m => Abs.LIdent' Position -> m (LIdent Position)
toLIdent (Abs.LIdent a (LIdentTok b)) = pure $ LIdent a b

tupled2 :: NonEmpty2 (Doc ann) -> Doc ann
tupled2 = tupled . toList

concatNE :: NonEmpty (NonEmpty a) -> NonEmpty a
concatNE = fromList . concat . toList . fmap toList

length2 :: NonEmpty2 a -> Int
length2 = Prelude.length . toList

fromList2 :: Pretty a => [a] -> NonEmpty2 a
fromList2 xs = case xs of
  a : b : rest -> cons2 a (b :| rest)
  _ -> unreachable "expected list with at least two elements" xs

data Pat a
    = PParens a (Pat a)
    | PTuple a (NonEmpty2 (Pat a))
    | PTyped a (Pat a) (Type a)
    | PUnit a
    | PVar a (LIdent a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (Pat a) where
  pretty x = case x of
    PTyped _ b c -> pretty b <+> ":" <+> "`" <> pretty c <> "`"
    PTuple _ cs -> tupled2 $ fmap pretty cs
    PParens _ b -> parens $ pretty b
    PUnit _ -> "()"
    PVar _ b -> pretty b

toPat :: MonadIO m => Abs.Pat' Position -> m (Pat Position)
toPat x = case x of
    Abs.PParens a b -> PParens a <$> toPat b
    Abs.PTuple a b cs -> PTuple a <$> mapM toTupleElemPat (cons2 b $ fromList cs)
    Abs.PTyped a b c -> PTyped a <$> toPat b <*> toType c
    Abs.PUnit a -> pure $ PUnit a
    Abs.PVar a b -> PVar a <$> toLIdent b

data PrefixOp a = PrefixOp a Text
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (PrefixOp a) where
  pretty (PrefixOp _ x) = pretty x

toPrefixOp (Abs.PrefixOp a (PrefixOpTok b)) = pure $ PrefixOp a b

data QualLIdent a
    = Qual a (UIdent a) (LIdent a)
    | UnQual a (LIdent a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (QualLIdent a) where
  pretty x = case x of
    Qual _ a b -> pretty a <> "." <> pretty b
    UnQual _ a -> pretty a

toQualLIdent x = case x of
  Abs.Qual a b c -> Qual a <$> toUIdent b <*> toLIdent c
  Abs.UnQual a b -> UnQual a <$> toLIdent b

data Scalar a
    = AFalse a
    | ATrue a
    | Char a Text
    | Double a (ADouble a)
    | Int a Text
    | String a (AString a)
    | UInt a (UInt a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toScalar x = case x of
    Abs.AFalse a -> pure $ AFalse a
    Abs.ATrue a -> pure $ ATrue a
    Abs.Char a (CharTok b) -> pure $ Char a b
    Abs.Double a b -> Double a <$> toADouble b
    Abs.Int a (IntTok b) -> pure $ Int a b
    Abs.String a b -> String a <$> toAString b
    Abs.UInt a b -> UInt a <$> toUInt b

instance Pretty (Scalar a) where
  pretty x = case x of
    ATrue _ -> "True"
    AFalse _ -> "False"
    Double _ a -> pretty a
    UInt _ a -> pretty a
    Int _ a -> pretty a
    Char _ a -> pretty a
    String _ a -> pretty a

toSize :: MonadIO m => Abs.Size' Position -> m (Type Position)
toSize x = case x of
  Abs.SzNat a b -> TSize a <$> toUInt b
  Abs.SzVar a b -> TVar a <$> toLIdent b

data Stmt a
    = Let a (Pat a) (Exp a)
    | Stmt a (Exp a)
    | TailRecLet a (TailRecDecls a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toStmt x = case x of
    Abs.Stmt a b -> Stmt a <$> toExp b
    Abs.TailRecLet a b -> TailRecLet a <$> toTailRecDecls b
    Abs.XLet a b c -> Let a <$> (toExp b >>= expToPat) <*> toExp c

expToPat :: MonadIO m => Exp Position -> m (Pat Position)
expToPat x = case x of
  Parens pos a -> PParens pos <$> expToPat a
  Tuple pos bs -> PTuple pos <$> mapM expToPat bs
  Typed pos a t -> PTyped pos <$> expToPat a <*> pure t
  Unit pos -> pure $ PUnit pos
  Var pos v -> pure $ PVar pos v
  _ -> err100 "expression where pattern expected" x

instance Pretty (Stmt a) where
  pretty x = case x of
    TailRecLet _ a -> pretty a
    Stmt _ a -> pretty a
    Let _ a b -> binop "=" a b

toExpDecl :: MonadIO m => Abs.ExpDecl' Position -> m (ExpDecl Position)
toFieldDecl :: MonadIO m => Abs.FieldDecl' Position -> m (FieldDecl Position)
toFixity :: MonadIO m => Abs.Fixity' Position -> m (Fixity Position)
toIfBranch :: MonadIO m => Abs.IfBranch' Position -> m (Exp Position, Exp Position)
toInfixOp :: MonadIO m => Abs.InfixOp' Position -> m (InfixOp Position)
toPrefixOp :: MonadIO m => Abs.PrefixOp' Position -> m (PrefixOp Position)
toQualLIdent :: MonadIO m => Abs.QualLIdent' Position -> m (QualLIdent Position)
toScalar :: MonadIO m => Abs.Scalar' Position -> m (Scalar Position)
toStmt :: MonadIO m => Abs.Stmt' Position -> m (Stmt Position)
toUIdent :: MonadIO m => Abs.UIdent' Position -> m (UIdent Position)

data TField a = TField a (LIdent a) (Type a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (TField a) where
  pretty (TField _ a b) = binop ":" a b

toTField :: MonadIO m => Abs.TField' Position -> m (TField Position)
toTField (Abs.TField a b c) = TField a <$> toLIdent b <*> toType c

data TSum a
  = TCon a (UIdent a) (Type a)
  | TEnum a (UIdent a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (TSum a) where
  pretty x = case x of
    TCon _ b c -> binop ":" b c
    TEnum _ b -> pretty b

toTSum :: MonadIO m => Abs.TSum' Position -> m (TSum Position)
toTSum x = case x of
  Abs.TCon a b c -> TCon a <$> toUIdent b <*> toType c
  Abs.TEnum a b -> TEnum a <$> toUIdent b

data TailRecDecl a
    = TailRecDecl a (LIdent a) (LIdent a) (Exp a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toTailRecDecl :: MonadIO m => Abs.TailRecDecl' Position -> m (TailRecDecl Position)
toTailRecDecl (Abs.TailRecDecl a b c d) = TailRecDecl a <$> toLIdent b <*> toLIdent c <*> toExp d

instance Pretty (TailRecDecl a) where
  pretty (TailRecDecl _ b c d) = pretty b <+> "=" <+> "\\" <+> binop "->" c d

data TailRecDecls a = TailRecDecls a (NonEmpty (TailRecDecl a))
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toTailRecDecls :: MonadIO m => Abs.TailRecDecls' Position -> m (TailRecDecls Position)
toTailRecDecls (Abs.TailRecDecls a bs) = TailRecDecls a <$> mapM toLayoutElemTailRecDecl (fromList bs)

layout :: Pretty a => Doc ann -> NonEmpty a -> Doc ann
layout a bs = nest 2 $ vcat (a : fmap pretty (toList bs))

instance Pretty (TailRecDecls a) where
  pretty (TailRecDecls _ bs) = layout "tailrec" bs

data NonEmpty2 a
  = Cons2 a (NonEmpty a)
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

cons2 :: a -> NonEmpty a -> NonEmpty2 a
cons2 = Cons2

data Type a
    = TLam a (LIdent a) (Type a)
    | TFun a (Type a) (Type a)
    | TApp a (Type a) (Type a)
    | TName a (UIdent a)
    | TOpaque a (AString a)
    | TParens a (Type a)
    | TQualName a (UIdent a) (UIdent a)
    | TRecord a (NonEmpty (TField a))
    | TSize a (UInt a)
    | TSizes a (NonEmpty (Type a))
    | TSum a (NonEmpty (TSum a))
    | TTuple a (NonEmpty2 (Type a))
    | TVar a (LIdent a)
    | TPointer a
    | TString a
    | TUInt a
    | TUnit a
    | TArray a
    | TBool a
    | TChar a
    | TFloat a
    | TInt a
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

toType :: MonadIO m => Abs.Type' Position -> m (Type Position)
toType x = case x of
  Abs.TLam _ bs c -> do
    vs <- mapM toLIdent bs
    t <- toType c
    pure $ foldr (\v -> TLam (positionOf v) v) t $ toList vs
  Abs.TFun a b c -> TFun a <$> toType b <*> toType c
  Abs.TApp a b c -> TApp a <$> toType b <*> toType c
  Abs.TArray a -> pure $ TArray a
  Abs.TBool a -> pure $ TBool a
  Abs.TChar a -> pure $ TChar a
  Abs.TFloat a -> pure $ TFloat a
  Abs.TInt a -> pure $ TInt a
  Abs.TName a b -> TName a <$> toUIdent b
  Abs.TOpaque a b -> TOpaque a <$> toAString b
  Abs.TParens a b -> TParens a <$> toType b
  Abs.TPointer a -> pure $ TPointer a
  Abs.TQualName a b c -> TQualName a <$> toUIdent b <*> toUIdent c
  Abs.TRecord a bs -> TRecord a <$> mapM toLayoutElemTField (fromList bs)
  Abs.TSize a b -> TSize a <$> toUInt b
  Abs.TSizes a bs -> TSizes a <$> mapM toSize (fromList bs)
  Abs.TString a -> pure $ TString a
  Abs.TSum a bs -> TSum a <$> mapM toLayoutElemTSum (fromList bs)
  Abs.TTuple a b cs -> TTuple a <$> mapM toTupleElemType (cons2 b $ fromList cs)
  Abs.TUInt a -> pure $ TUInt a
  Abs.TUnit a -> pure $ TUnit a
  Abs.TVar a b -> TVar a <$> toLIdent b

nelist :: Foldable t => t (Doc ann) -> Doc ann
nelist = list . toList

nehsep :: Foldable t => t (Doc ann) -> Doc ann
nehsep = hsep . toList

instance Pretty (Type a) where
  pretty x = case x of
    TLam _ b c -> "\\" <+> pretty b <+> "=>" <+> pretty c
    TFun _ a b -> binop "->" a b
    TApp _ a b -> hsep2 a b
    TRecord _ bs -> layout "Record" bs
    TSum _ bs -> layout "Sum" bs
    TTuple _ cs -> tupled2 $ fmap pretty cs
    TParens _ a -> parens $ pretty a
    TSize _ a -> pretty a
    TSizes _ bs -> nelist $ fmap pretty bs
    TUnit _ -> "()"
    TPointer _ -> "Pointer"
    TArray _ -> "Array"
    TOpaque _ a -> "Opaque" <+> pretty a
    TString _ -> "String"
    TUInt _ -> "U"
    TInt _ -> "I"
    TFloat _ -> "F"
    TChar _ -> "C"
    TBool _ -> "Bool"
    TVar _ a -> pretty a
    TName _ a -> pretty a
    TQualName _ a b -> pretty a <> "." <> pretty b

data UIdent a = UIdent a Text
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (UIdent a) where
  pretty (UIdent _ x) = pretty x

toUIdent (Abs.UIdent a (UIdentTok b)) = pure $ UIdent a b

data UInt a
    = Bin a Text
    | Dec a Text
    | Hex a Text
    | Oct a Text
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable, Data, Typeable, Generic)

instance Pretty (UInt a) where
  pretty x = case x of
    Bin _ b -> pretty b
    Dec _ b -> pretty b
    Hex _ b -> pretty b
    Oct _ b -> pretty b

toUInt :: MonadIO m => Abs.UInt' Position -> m (UInt Position)
toUInt x = case x of
  Abs.Bin a (BinTok b) -> pure $ Bin a b
  Abs.Dec a (DecTok b) -> pure $ Dec a b
  Abs.Hex a (HexTok b) -> pure $ Hex a b
  Abs.Oct a (OctTok b) -> pure $ Oct a b

-- -- | Get the start position of something.
instance Positioned (Scalar Position) where
  positionOf x = case x of
    AFalse pos -> pos
    ATrue pos -> pos
    Char pos _ -> pos
    Double pos _ -> pos
    Int pos _ -> pos
    String pos _ -> pos
    UInt pos _ -> pos

instance Positioned (ExpDecl Position) where
  positionOf x = case x of
    Binding pos _ _ -> pos
    TailRec pos _ -> pos

instance Positioned (Type Position) where
  positionOf x = case x of
    TOpaque pos _ -> pos
    TLam pos _ _ -> pos
    TFun pos _ _ -> pos
    TApp pos _ _ -> pos
    TQualName pos _ _ -> pos
    TTuple pos _ -> pos

    TRecord pos _ -> pos
    TName pos _ -> pos
    TParens pos _ -> pos
    TSize pos _ -> pos
    TSizes pos _ -> pos
    TSum pos _ -> pos
    TVar pos _ -> pos

    TArray pos -> pos
    TBool pos -> pos
    TChar pos -> pos
    TFloat pos -> pos
    TInt pos -> pos
    TPointer pos -> pos
    TString pos -> pos
    TUInt pos -> pos
    TUnit pos -> pos

instance Positioned (Stmt Position) where
  positionOf x = case x of
    Let pos _ _ -> pos
    Stmt pos _ -> pos
    TailRecLet pos _ -> pos

instance Positioned (AltPat Position) where
  positionOf x = case x of
    PCon pos _ _ -> pos
    PDefault pos _ -> pos
    PEnum pos _ -> pos
    PScalar pos _ -> pos

instance Positioned (Exp Position) where
  positionOf x = case x of
    Lam pos _ _ -> pos
    Where pos _ _ -> pos
    Typed pos _ _ -> pos
    With pos _ _ -> pos
    InfixOper pos _ _ _ -> pos
    App pos _ _ -> pos
    PrefixOper pos _ _ -> pos
    Array pos _ -> pos
    Case pos _ _ -> pos
    Con pos _ -> pos
    Do pos _ -> pos
    EType pos _ -> pos
    If pos _ _ _ -> pos
    Parens pos _ -> pos
    Qualified pos _ _ -> pos
    Record pos _ -> pos
    Scalar pos _ -> pos
    Select pos _ _ -> pos
    Tuple pos _ -> pos
    Unit pos -> pos
    Var pos _ -> pos
    Extern pos _ _ -> pos
    Else pos _ _ -> pos

instance Positioned (Pat Position) where
  positionOf x = case x of
    PParens pos _ -> pos
    PTuple pos _ -> pos
    PTyped pos _ _ -> pos
    PUnit pos -> pos
    PVar pos _ -> pos

instance Positioned (PrefixOp Position) where
  positionOf (PrefixOp pos _) = pos

instance Positioned (InfixOp Position) where
  positionOf (InfixOp pos _) = pos

instance Positioned (LIdent Position) where
  positionOf (LIdent pos _) = pos

instance Positioned (UIdent Position) where
  positionOf (UIdent pos _) = pos

instance Positioned (QualLIdent Position) where
  positionOf x = case x of
    Qual pos _ _ -> pos
    UnQual pos _ -> pos

instance Positioned (AString Position) where
  positionOf (AString pos _) = pos

instance Positioned (Decl Position) where
  positionOf x = case x of
    ExpDecl pos _ -> pos
    InfixDecl pos _ _ -> pos
    QualDecl pos _ _ -> pos
    PrefixDecl pos _ _ -> pos
    TypeDecl pos _ _ -> pos
    ExportDecl pos _ _ _ -> pos


--
