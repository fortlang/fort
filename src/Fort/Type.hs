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
  | XTyChar Position
  | XTyLoop Position
  | XTyFloat Position
  | XTyInt Position
  | XTyUInt Position
  | XTyPointer Position
  | XTyArray Position
  | XTyVector Position
  | XXTyVector Position Integer
  | XXTyArray Position (NonEmpty Integer)
  | XTySizes Position (NonEmpty Integer)
  | XTyPrimCall Position Text
  | XTyErr Position

  -- these should remain
  | TyFun Position Ty Ty
  | TyRecord Position (Map LIdent Ty)
  | TySum Position (Map UIdent (Maybe Ty))
  | TyTuple Position (NonEmpty2 Ty)
  | TyArray Position Sz Ty
  | TyVector Position SzVector Ty
  | TyUnit Position

  | TyType Position Ty
  | TyOpaque Position Text

  | TyPointer Position Ty

  | TyEnum Position (Set UIdent)
  | TyString Position
  | TyChar Position
  | TyFloat Position SzFloat
  | TyInt Position SzInt
  | TyUInt Position SzUInt
  | TyBool Position
  deriving (Show, Data)

class Bitsize a where
  szBitsize :: a -> Integer

data SzFloat = F32 | F64 deriving (Show, Eq, Data)
data SzInt = I8 | I16 | I32 | I64 deriving (Show, Eq, Data)
data SzUInt = U8 | U16 | U32 | U64 deriving (Show, Eq, Data)
data SzVector = V2 | V4 | V8 | V16 | V32 deriving (Show, Eq, Data)

szVector :: SzVector -> Sz
szVector x = case x of
    V2 -> 2
    V4 -> 4
    V8 -> 8
    V16 -> 16
    V32 -> 32

instance Pretty SzVector where
  pretty = pretty . szVector

instance Bitsize SzFloat where
  szBitsize x = case x of
    F32 -> 32
    F64 -> 64

instance Pretty SzFloat where
  pretty = pretty . szBitsize

instance Bitsize SzInt where
  szBitsize x = case x of
    I8 -> 8
    I16 -> 16
    I32 -> 32
    I64 -> 64

instance Pretty SzInt where
  pretty = pretty . szBitsize

instance Bitsize SzUInt where
  szBitsize x = case x of
    U8 -> 8
    U16 -> 16
    U32 -> 32
    U64 -> 64

instance Pretty SzUInt where
  pretty = pretty . szBitsize

instance Eq Ty where
  x == y = case (x, y) of
    (TySum _ m, TySum _ n) -> isEqualByKeys m n && and bs
      where
        bs = Map.elems $ Map.intersectionWith (==) m n
    (TyRecord _ m, TyRecord _ n) -> isEqualByKeys m n && and bs
      where
        bs = Map.elems $ Map.intersectionWith (==) m n
    (TyTuple _ bs, TyTuple _ cs) -> length2 bs == length2 cs && and (uncurry (==) <$> zip (toList bs) (toList cs))
    (TyArray _ sza a, TyArray _ szb b) -> sza == szb && a == b
    (TyVector _ sza a, TyVector _ szb b) -> sza == szb && a == b
    (TyFun _ a b, TyFun _ c d) -> a == c && b == d
    (TyUnit _, TyUnit _) -> True
    (TyType _ a, TyType _ b) -> a == b
    (TyOpaque _ a, TyOpaque _ b) -> a == b
    (TyPointer _ a, TyPointer _ b) -> a == b
    (TyEnum{}, TyEnum{}) -> True
    (TyString{}, TyString{}) -> True
    (TyChar{}, TyChar{}) -> True
    (TyFloat _ a, TyFloat _ b) -> a == b
    (TyInt _ a, TyInt _ b) -> a == b
    (TyUInt _ a, TyUInt _ b) -> a == b
    (TyBool{}, TyBool{}) -> True
    _ -> False

instance Positioned Ty where
  positionOf x = case x of
    XTyErr pos -> pos
    XTyTLam pos _ _ _ -> pos
    XTyLam pos _ _ _ -> pos
    XTyLoop pos -> pos
    XTyChar pos -> pos
    XTyFloat pos -> pos
    XTyInt pos -> pos
    XTyUInt pos -> pos
    XTyPointer pos -> pos
    XTyArray pos -> pos
    XXTyArray pos _ -> pos
    XTyVector pos -> pos
    XXTyVector pos _ -> pos
    XTySizes pos _ -> pos
    XTyPrimCall pos _ -> pos
    TyFun pos _ _ -> pos
    TyRecord pos _ -> pos
    TySum pos _ -> pos
    TyTuple pos _ -> pos
    TyArray pos _ _ -> pos
    TyVector pos _ _ -> pos
    TyUnit pos -> pos
    TyType pos _ -> pos
    TyOpaque pos _ -> pos
    TyPointer pos _ -> pos
    TyEnum pos _ -> pos
    TyString pos -> pos
    TyChar pos -> pos
    TyFloat pos _ -> pos
    TyInt pos _ -> pos
    TyUInt pos _ -> pos
    TyBool pos -> pos

instance Pretty Ty where
  pretty x = case x of
    TyFun _ a b -> pretty a <+> "->" <+> f b

    XTyErr{} -> "<tyerr>"
    XTyTLam{} -> "<tylam>"
    XTyLoop{} -> "<loop>"
    XTyLam{} -> "<lam>"
    XTyPrimCall _ nm -> "<primcall = " <> pretty nm <> ">"
    XTyChar{} -> "<tychar>"
    XTyFloat{} -> "<tyfloat>"
    XTyInt{} -> "<tyint>"
    XTyUInt{} -> "<tyuint>"
    XTyPointer{} -> "<typointer>"
    XTyArray{} -> "<tyarray>"
    XXTyArray{} -> "<tyarray sizes>"
    XXTyVector{} -> "<tyvector size>"
    XTyVector{} -> "<tyvector>"
    XTySizes{} -> "<tysizes>"

    TyType _ t -> "<Type = " <> pretty t <> ">"
    TyOpaque _ n -> "<Opaque" <+> pretty n <> ">"

    TyArray _ sz t -> "Array" <+> pretty sz <+> f t
    TyVector _ sz t -> "Vector" <+> pretty sz <+> pretty t

    TyRecord _ m -> "Record" <+> pretty m
    TySum _ m -> "Sum" <+> pretty m
    TyTuple _ ts -> tupled2 (fmap pretty ts)
    TyUnit{} -> "()"

    TyPointer _ t -> "Pointer" <+> f t
    TyEnum _ bs -> ppTyEnum bs

    TyString{} -> "String"
    TyChar _ -> "C8"
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
        TyVector{} -> parens (pretty ty)
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
      TyVector pos sz a -> TyVector pos sz <$> go a
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
      (XTyChar pos, XTySizes _ (sz :| [])) -> case sz of
        8 -> pure $ TyChar pos
        _ -> err101 "unsupported Char size" b sz
      (XTyFloat pos, XTySizes _ (sz :| [])) -> case sz of
        32 -> pure $ TyFloat pos F32
        64 -> pure $ TyFloat pos F64
        _ -> err101 "unsupported Float size" b sz

      (XTyInt pos, XTySizes _ (sz :| [])) -> case sz of
        8 -> pure $ TyInt pos I8
        16 -> pure $ TyInt pos I16
        32 -> pure $ TyInt pos I32
        64 -> pure $ TyInt pos I64
        _ -> err101 "unsupported Int size" b sz

      (XTyUInt pos, XTySizes _ (sz :| [])) -> case sz of
        8 -> pure $ TyUInt pos U8
        16 -> pure $ TyUInt pos U16
        32 -> pure $ TyUInt pos U32
        64 -> pure $ TyUInt pos U64
        _ -> err101 "unsupported UInt size" b sz
      (XXTyArray pos szs, _) -> pure $ foldr (TyArray pos) tb szs
      (XTyArray pos, XTySizes _ szs) -> pure $ XXTyArray pos szs
      (XTyVector pos , XTySizes _ (sz :| [])) -> pure $ XXTyVector pos sz
      (XXTyVector pos sz, _) -> if
        | n == 128 || n == 256 -> case sz of
            2 -> pure $ TyVector pos V2 tb
            4 -> pure $ TyVector pos V4 tb
            8 -> pure $ TyVector pos V8 tb
            16 -> pure $ TyVector pos V16 tb
            32 -> pure $ TyVector pos V32 tb
            _ -> vecErr
        | otherwise -> vecErr
          where
            vecErr = err111 "expected vector size to be 128 or 256" a b sz
            n = sz * bitsize tb
      _ -> err101 "unexpected type in type application" a ta

  TPointer pos -> pure $ XTyPointer pos
  TArray pos -> pure $ XTyArray pos
  TVector pos -> pure $ XTyVector pos

  TFun pos a b -> TyFun pos <$> evalType env a <*> evalType env b
  TParens _ t -> evalType env t
  TBool pos -> pure $ TyBool pos
  TString pos -> pure $ TyString pos
  TUnit pos -> pure $ TyUnit pos
  TOpaque pos a -> pure $ TyOpaque pos a
  TTuple pos bs -> TyTuple pos <$> mapM (evalType env) bs
  TRecord pos bs -> TyRecord pos . fromNEList <$> mapM (evalTField env) bs
  TSum pos bs -> TySum pos . fromNEList <$> mapM (evalTSum env) bs
  
  TChar pos -> pure $ XTyChar pos
  TFloat pos -> pure $ XTyFloat pos
  TInt pos -> pure $ XTyInt pos
  TUInt pos -> pure $ XTyUInt pos
  
  TSize pos a -> pure $ XTySizes pos $ NE.singleton a
  TSizes pos bs -> XTySizes pos . concatNE <$> mapM (evalSize env) bs

bitsize :: Ty -> Sz
bitsize x = case x of
  TyChar _ -> 8
  TyFloat _ sz -> szBitsize sz
  TyInt _ sz -> szBitsize sz
  TyUInt _ sz -> szBitsize sz
  TyBool{} -> 1
  TyPointer _ _ | isRegisterTy x -> bitsizePointer
  TyString _ -> bitsizePointer
  TyEnum{} -> 32
  TyVector _ sz t -> szVector sz * bitsize t
  _ -> unreachable "unexpected type as input to bitsize" x

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
  TyVector{} -> True
  _ -> False
  where
    go a = case a of
      TyArray _ _ b -> go b
      TyOpaque{} -> True
      _ -> isRegisterTy a

isExternArgTy :: Ty -> Bool
isExternArgTy x = case x of
  TyUnit{} -> True
  TyTuple _ cs -> all isRegisterTy cs
  _ -> isRegisterTy x

isExternResultTy :: Ty -> Bool
isExternResultTy x = case x of
  TyUnit{} -> True
  _ -> isRegisterTy x

isExternTy :: Ty -> Bool
isExternTy t = case t of
  TyFun _ a b -> isExternArgTy a && isExternResultTy b
  _ -> isRegisterTy t

checkExtern :: MonadIO m => Ty -> m ()
checkExtern t = if
  | isExternTy t -> pure ()
  | otherwise -> err100 "unsupported extern type" t

isSwitchTy :: Ty -> Bool
isSwitchTy x = case x of
  TyEnum{} -> True
  TyChar{} -> True
  TyInt{} -> True
  TyUInt{} -> True
  _ -> False
