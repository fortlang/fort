{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}
module Fort.Type (module Fort.Type) where

import Fort.Utils
import qualified Data.List.NonEmpty as NE
import qualified Data.Map as Map
import qualified Data.Set as Set

type M a = StateT TySt IO a

newtype TySt = TySt{ types :: Map UIdent Type }

class Typed a where
  typeOf :: a -> Ty

initTySt :: [Decl] -> TySt
initTySt ds = TySt{ types = Map.fromList [ (nm, t) | TypeDecl _ nm t <- ds ] }

type TyEnv = Map LIdent Ty

data TCSt = TCSt
  { nextUnknown :: Int
  , constraints :: Map Int (LIdent, Ty)
  , stackTrace :: [Posn (Doc ())]
  }

data Ty
  -- these should be eliminated during evalType
  = XTyTLam Position TyEnv LIdent Type
  | XTyLam Position TyEnv Binding Exp
  | XTyTailRecDecls Position TyEnv (NonEmpty TailRecDecl) LIdent
  | XTyUnknown Position LIdent Int
  | XTyChar Position
  | XTyFloat Position
  | XTyInt Position
  | XTyUInt Position
  | XTyPointer Position
  | XTyArray Position
  | XXTyArray Position (NonEmpty Integer)
  | XTySizes Position (NonEmpty Integer)
  | XTyPrimCall Position AString

  -- these should remain
  | TyNone Position -- the type of 'undef' and looping tailrec calls
  | TyFun Position Ty Ty
  | TyRecord Position (Map LIdent Ty)
  | TySum Position (Map UIdent (Maybe Ty))
  | TyTuple Position (NonEmpty2 Ty)
  | TyArray Position Sz Ty
  | TyUnit Position

  | TyType Position Ty
  | TyOpaque Position Text

  | TyPointer Position Ty

  | TyEnum Position (Set UIdent)
  | TyString Position
  | TyChar Position Sz
  | TyFloat Position Sz
  | TyInt Position Sz
  | TyUInt Position Sz
  | TyBool Position
  deriving (Show, Data)

instance Eq Ty where
  x == y = case (x, y) of
    (TySum _ m, TySum _ n) -> and $ Map.elems $ Map.intersectionWith (==) m n
    (TyRecord _ m, TyRecord _ n) -> isEqualByKeys m n && and bs
      where
        bs = Map.elems $ Map.intersectionWith (==) m n
    (TyTuple _ bs, TyTuple _ cs) -> length2 bs == length2 cs && and (uncurry (==) <$> zip (toList bs) (toList cs))
    (TyArray _ sza a, TyArray _ szb b) -> sza == szb && a == b
    (TyNone _ , TyNone _) -> True
    (TyFun _ a b, TyFun _ c d) -> a == c && b == d
    (TyUnit _, TyUnit _) -> True
    (TyType _ a, TyType _ b) -> a == b
    (TyOpaque _ a, TyOpaque _ b) -> a == b
    (TyPointer _ a, TyPointer _ b) -> a == b
    (TyEnum{}, TyEnum{}) -> True
    (TyString{}, TyString{}) -> True
    (TyChar _ a, TyChar _ b) -> a == b
    (TyFloat _ a, TyFloat _ b) -> a == b
    (TyInt _ a, TyInt _ b) -> a == b
    (TyUInt _ a, TyUInt _ b) -> a == b
    (TyBool{}, TyBool{}) -> True
    _ -> False

instance Positioned Ty where
  positionOf x = case x of
    XTyTLam pos _ _ _ -> pos
    XTyLam pos _ _ _ -> pos
    XTyTailRecDecls pos _ _ _ -> pos
    XTyUnknown pos _ _ -> pos
    XTyChar pos -> pos
    XTyFloat pos -> pos
    XTyInt pos -> pos
    XTyUInt pos -> pos
    XTyPointer pos -> pos
    XTyArray pos -> pos
    XXTyArray pos _ -> pos
    XTySizes pos _ -> pos
    XTyPrimCall pos _ -> pos
    TyNone pos -> pos
    TyFun pos _ _ -> pos
    TyRecord pos _ -> pos
    TySum pos _ -> pos
    TyTuple pos _ -> pos
    TyArray pos _ _ -> pos
    TyUnit pos -> pos
    TyType pos _ -> pos
    TyOpaque pos _ -> pos
    TyPointer pos _ -> pos
    TyEnum pos _ -> pos
    TyString pos -> pos
    TyChar pos _ -> pos
    TyFloat pos _ -> pos
    TyInt pos _ -> pos
    TyUInt pos _ -> pos
    TyBool pos -> pos

instance Pretty Ty where
  pretty x = case x of
    XTyTailRecDecls{} -> "<tytailrecdecls>"
    XTyUnknown _ fn i -> "<tyunknown =" <+> pretty fn <+> pretty i <> ">"
    TyFun _ a b -> pretty a <+> "->" <+> f b
    TyArray _ sz t -> "Array" <+> pretty sz <+> f t

    XTyTLam{} -> "<tylam>"
    XTyLam{} -> "<lam>"
    XTyPrimCall _ nm -> "<primcall = " <> pretty nm <> ">"
    XTyChar{} -> "<tychar>"
    XTyFloat{} -> "<tyfloat>"
    XTyInt{} -> "<tyint>"
    XTyUInt{} -> "<tyuint>"
    XTyPointer{} -> "<typointer>"
    XTyArray{} -> "<tyarray>"
    XXTyArray{} -> "<tyarray sizes>"
    XTySizes{} -> "<tysizes>"

    -- these should remain
    TyNone{} -> "TyNone"
    TyType _ t -> "<Type = " <> pretty t <> ">"
    TyOpaque _ n -> "<Opaque" <+> pretty n <> ">"

    TyRecord _ m -> "Record" <+> pretty m
    TySum _ m -> "Sum" <+> pretty m
    TyTuple _ ts -> tupled2 (fmap pretty ts)
    TyUnit{} -> "()"

    TyPointer _ t -> "Pointer" <+> f t
    TyEnum _ bs -> ppTyEnum bs

    TyString{} -> "String"
    TyChar _ sz -> "C" <+> pretty sz
    TyFloat _ sz -> "F" <+> pretty sz
    TyInt _ sz -> "I" <+> pretty sz
    TyUInt _ sz -> "U" <+> pretty sz
    TyBool{} -> "Bool"
    where
      f ty = case ty of
        TyFun{} -> parens (pretty ty)
        TySum{} -> parens (pretty ty)
        TyRecord{} -> parens (pretty ty)
        TyArray{} -> parens (pretty ty)
        TyPointer{} -> parens (pretty ty)
        TyChar{} -> parens (pretty ty)
        TyFloat{} -> parens (pretty ty)
        TyInt{} -> parens (pretty ty)
        TyUInt{} -> parens (pretty ty)
        _ -> pretty ty

ppTyEnum :: Pretty a => Set a -> Doc ann
ppTyEnum bs = encloseSep "<" ">" " | " (pretty <$> Set.toList bs)

isUIntTy :: Ty -> Bool
isUIntTy x = case x of
  TyUInt{} -> True
  TyChar{} -> True
  TyEnum{} -> True -- True but unreachable as TyEnum is always part of a Sum type
  TyBool{} -> True
  _ -> False

isIntTy :: Ty -> Bool
isIntTy x = isTyInt x || isUIntTy x

isTyInt :: Ty -> Bool
isTyInt x = case x of
  TyInt{} -> True
  _ -> False

isTySum :: Ty -> Bool
isTySum x = case x of
  TySum{} -> True
  _ -> False

evalType_ :: Type -> M Ty
evalType_ t = evalType mempty t >>= go
  where
    go ty = case ty of
      TyFun pos a b -> TyFun pos <$> go a <*> go b
      TyRecord pos m -> TyRecord pos <$> mapM go m
      TySum pos m -> TySum pos <$> mapM (mapM go) m
      TyTuple pos ts -> TyTuple pos <$> mapM go ts
      TyArray pos sz a -> TyArray pos sz <$> go a
      TyPointer pos a -> TyPointer pos <$> go a
      TyUnit{} -> pure ty
      TyOpaque{} -> pure ty
      TyString{} -> pure ty
      TyChar{} -> pure ty
      TyFloat{} -> pure ty
      TyInt{} -> pure ty
      TyUInt{} -> pure ty
      TyBool{} -> pure ty
      _ -> err101 "incomplete type" t ty

evalType :: TyEnv -> Type -> M Ty
evalType env x = case x of
  TQualName pos c v -> evalType env $ TName pos $ mkQName (textOf c) v
  TName _ n -> do
    tbl <- gets types
    case Map.lookup n tbl of
      Nothing -> err101 "unknown type name" n tbl
      Just t -> evalType env t

  TLam pos v t -> pure $ XTyTLam pos env v t
 
  TVar _ v ->
    case Map.lookup v env of
      Nothing -> err101 "unknown type variable" v env
      Just t -> pure t
 
  TApp _ a b -> do
    ta <- evalType env a
    tb <- evalType env b
    case (ta, tb) of
      (XTyTLam _ env' v t, _) -> do
        let env'' = Map.insert v tb env'
        evalType env'' t

      (XTyPointer pos, _) -> pure $ TyPointer pos tb
      (XTyChar pos, XTySizes _ (sz :| [])) -> pure $ TyChar pos sz
      (XTyFloat pos, XTySizes _ (sz :| [])) -> if
        | sz `elem` [32, 64] -> pure $ TyFloat pos sz
        | otherwise -> err101 "unsupported Float size" b sz
      (XTyInt pos, XTySizes _ (sz :| [])) -> pure $ TyInt pos sz
      (XTyUInt pos, XTySizes _ (sz :| [])) -> pure $ TyUInt pos sz
      (XXTyArray pos szs, _) -> pure $ foldr (TyArray pos) tb szs
      (XTyArray pos, XTySizes _ szs) -> pure $ XXTyArray pos szs
      _ -> err101 "unexpected type in type application" a ta

  TPointer pos -> pure $ XTyPointer pos
  TArray pos -> pure $ XTyArray pos

  TFun pos a b -> TyFun pos <$> evalType env a <*> evalType env b
  TParens _ t -> evalType env t
  TBool pos -> pure $ TyBool pos
  TString pos -> pure $ TyString pos
  TUnit pos -> pure $ TyUnit pos
  TOpaque pos a -> pure $ TyOpaque pos $ valOf a
  TTuple pos bs -> TyTuple pos <$> mapM (evalType env) bs
  TRecord pos bs -> TyRecord pos . fromNEList <$> mapM (evalTField env) bs
  TSum pos bs -> TySum pos . fromNEList <$> mapM (evalTSum env) bs
  
  TChar pos -> pure $ XTyChar pos
  TFloat pos -> pure $ XTyFloat pos
  TInt pos -> pure $ XTyInt pos
  TUInt pos -> pure $ XTyUInt pos
  
  TSize pos a -> pure $ XTySizes pos $ NE.singleton $ valOf a
  TSizes pos bs -> XTySizes pos . concatNE <$> mapM (evalSize env) bs

fromNEList :: Ord k => NonEmpty (k, a) -> Map k a
fromNEList = Map.fromList . toList

evalTField :: TyEnv -> TField -> M (LIdent, Ty)
evalTField env (TField _ fld t) = (fld, ) <$> evalType env t

evalTSum :: TyEnv -> TSum -> M (UIdent, Maybe Ty)
evalTSum env (TCon _ c t) = (c, ) . Just <$> evalType env t
evalTSum _ (TEnum _ c) = pure (c, Nothing)

evalSize :: TyEnv -> Type -> M (NonEmpty Integer)
evalSize env x = do
  t <- evalType env x
  case t of
    XTySizes _ szs -> pure szs
    _ -> err101 "unexpected size type" x t

isRegisterTy :: Ty -> Bool
isRegisterTy x = case x of
  TyPointer _ a -> go a
  TyEnum{} -> True
  TyString{} -> True
  TyChar{} -> True
  TyFloat{} -> True
  TyInt{} -> True
  TyUInt{} -> True
  TyBool{} -> True
  _ -> False
  where
    go a = case a of
      TyArray _ _ b -> go b
      TyOpaque{} -> True
      _ -> isRegisterTy a

checkExtern :: MonadIO m => Type -> Ty -> m ()
checkExtern t t' = case t' of
  _ | isRegisterTy t' -> pure ()
  TyFun _ a b -> do
    case a of
      TyTuple _ cs | all isRegisterTy cs -> pure ()
      TyUnit _ -> pure ()
      _ | isRegisterTy a -> pure ()
      _ -> err101 "unsupported extern input type" t a
    case b of
      TyUnit _ -> pure ()
      _ | isRegisterTy b -> pure ()
      _ -> err101 "unsupported extern output type" t b
  _ -> err101 "unsupported extern type" t t'

isSwitchTy :: Ty -> Bool
isSwitchTy x = case x of
  TyEnum{} -> True
  TyChar{} -> True
  TyInt{} -> True
  TyUInt{} -> True
  _ -> False
