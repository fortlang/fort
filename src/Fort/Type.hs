{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant multi-way if" #-}
module Fort.Type (module Fort.Type) where

import Fort.Utils
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
  , constraints :: Map Int (LIdent, (Position, Ty))
  , traceTC :: Bool
  }

data Ty
  -- these should be eliminated during evalType
  = XTyTLam TyEnv [LIdent] Type
  | XTyLam TyEnv [Binding] Exp
  | XTyTailRecDecls TyEnv [TailRecDecl] LIdent
  | XTyUnknown LIdent Int
  | XTyChar
  | XTyFloat
  | XTyInt
  | XTyUInt
  | XTyPointer
  | XTyArray
  | XXTyArray [Integer]
  | XTySizes [Integer]
  | XTyPrimCall LIdent

  -- these should remain
  | TyNone -- the type of 'undef' and looping tailrec calls
  | TyFun Ty Ty
  | TyRecord (Map LIdent Ty)
  | TySum (Map UIdent (Maybe Ty))
  | TyTuple [Ty] -- two or more
  | TyArray Sz Ty
  | TyUnit

  | TyType Ty
  | TyOpaque Text

  | TyPointer Ty

  | TyEnum (Set UIdent)
  | TyString
  | TyChar Sz
  | TyFloat Sz
  | TyInt Sz
  | TyUInt Sz
  | TyBool
  deriving (Show, Eq, Data)

instance Pretty Ty where
  pretty x = case x of
    XTyTailRecDecls{} -> "<tytailrecdecls>"
    XTyUnknown fn i -> "<tyunknown =" <+> pretty fn <+> pretty i <> ">"
    TyFun a b -> pretty a <+> "->" <+> f b
    TyArray sz t -> "Array" <+> pretty sz <+> f t

    XTyTLam{} -> "<tylam>"
    XTyLam{} -> "<lam>"
    XTyPrimCall nm -> "<primcall = " <> pretty nm <> ">"
    XTyChar{} -> "<tychar>"
    XTyFloat{} -> "<tyfloat>"
    XTyInt{} -> "<tyint>"
    XTyUInt{} -> "<tyuint>"
    XTyPointer{} -> "<typointer>"
    XTyArray{} -> "<tyarray>"
    XXTyArray{} -> "<tyarray sizes>"
    XTySizes{} -> "<tysizes>"

    -- these should remain
    TyNone -> "TyNone"
    TyType t -> "<Type = " <> pretty t <> ">"
    TyOpaque n -> "<Opaque" <+> pretty n <> ">"

    TyRecord m -> "Record" <+> pretty m
    TySum m -> "Sum" <+> pretty m
    TyTuple ts -> tupled (fmap pretty ts)
    TyUnit -> "()"

    TyPointer t -> "Pointer" <+> f t
    TyEnum bs -> ppTyEnum bs

    TyString -> "String"
    TyChar sz -> "C" <+> pretty sz
    TyFloat sz -> "F" <+> pretty sz
    TyInt sz -> "I" <+> pretty sz
    TyUInt sz -> "U" <+> pretty sz
    TyBool -> "Bool"
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
  TyUInt _ -> True
  TyChar _ -> True
  TyEnum _ -> True -- True but unreachable as TyEnum is always part of a Sum type
  TyBool -> True
  _ -> False

isIntTy :: Ty -> Bool
isIntTy x = isTyInt x || isUIntTy x

isTyInt :: Ty -> Bool
isTyInt x = case x of
  TyInt _ -> True
  _ -> False

isTySum :: Ty -> Bool
isTySum x = case x of
  TySum{} -> True
  _ -> False

evalType_ :: Type -> M Ty
evalType_ t = evalType mempty t >>= go
  where
    go ty = case ty of
      TyFun a b -> TyFun <$> go a <*> go b
      TyRecord m -> TyRecord <$> mapM go m
      TySum m -> TySum <$> mapM (mapM go) m
      TyTuple ts -> TyTuple <$> mapM go ts
      TyArray sz a -> TyArray sz <$> go a
      TyPointer a -> TyPointer <$> go a
      TyUnit -> pure ty
      TyOpaque{} -> pure ty
      TyString -> pure ty
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

  TLam _ vs t -> pure $ XTyTLam env vs t
 
  TVar _ v ->
    case Map.lookup v env of
      Nothing -> err101 "unknown type variable" v env
      Just t -> pure t
 
  TApp _ a b -> do
    ta <- evalType env a
    tb <- evalType env b
    case (ta, tb) of
      (XTyTLam env' vs t, _) -> case vs of
          [] -> unreachable101 "empty type lambda" a ta
          v : rest -> do
            let env'' = Map.insert v tb env'
            case rest of
              [] -> evalType env'' t
              _ -> pure $ XTyTLam env'' rest t

      (XTyPointer, _) -> pure $ TyPointer tb
      (XTyChar, XTySizes [sz]) -> pure $ TyChar sz
      (XTyFloat, XTySizes [sz]) -> if
        | sz `elem` [16, 32, 64] -> pure $ TyFloat sz
        | otherwise -> err101 "unsupported Float size" b sz
      (XTyInt, XTySizes [sz]) -> pure $ TyInt sz
      (XTyUInt, XTySizes [sz]) -> pure $ TyUInt sz
      (XXTyArray szs, _) -> pure $ foldr TyArray tb szs
      (XTyArray, XTySizes szs) -> pure $ XXTyArray szs
      _ -> err101 "unexpected type in type application" a ta

  TPointer _ -> pure XTyPointer
  TArray _ -> pure XTyArray

  TFun _ a b -> TyFun <$> evalType env a <*> evalType env b
  TParens _ t -> evalType env t
  TBool _ -> pure TyBool
  TString _ -> pure TyString
  TUnit _ -> pure TyUnit
  TOpaque _ a -> pure $ TyOpaque $ valOf a
  TTuple _ a bs -> TyTuple <$> mapM (evalType env) (fmap newtypeOf (a:bs))
  TRecord _ bs -> TyRecord . Map.fromList <$> mapM (evalTField env) (fmap newtypeOf bs)
  TSum _ bs -> TySum . Map.fromList <$> mapM (evalTSum env) (fmap newtypeOf bs)
  
  TChar _ -> pure XTyChar
  TFloat _ -> pure XTyFloat
  TInt _ -> pure XTyInt
  TUInt _ -> pure XTyUInt
  
  TSize _ a -> pure $ XTySizes [valOf a]
  TSizes _ bs -> XTySizes . concat <$> mapM (evalSize env) bs

evalTField :: TyEnv -> TField -> M (LIdent, Ty)
evalTField env (TField _ fld t) = (fld, ) <$> evalType env t

evalTSum :: TyEnv -> TSum -> M (UIdent, Maybe Ty)
evalTSum env (TCon _ c t) = (c, ) . Just <$> evalType env t
evalTSum _ (TEnum _ c) = pure (c, Nothing)

evalSize :: TyEnv -> Size -> M [Integer]
evalSize env x = case x of
  SzNat _ a -> pure [valOf a]
  SzVar pos v -> do
    t <- evalType env $ TVar pos v
    case t of
      XTySizes szs -> pure szs
      _ -> err101 "unexpected size variable" x t

isRegisterTy :: Ty -> Bool
isRegisterTy x = case x of
  TyPointer a -> go a
  TyEnum _ -> True
  TyString -> True
  TyChar _ -> True
  TyFloat _ -> True
  TyInt _ -> True
  TyUInt _ -> True
  TyBool -> True
  _ -> False
  where
    go a = case a of
      TyArray _ b -> go b
      TyOpaque{} -> True
      _ -> isRegisterTy a

checkExtern :: MonadIO m => Type -> Ty -> m ()
checkExtern t t' = case t' of
  _ | isRegisterTy t' -> pure ()
  TyFun a b -> do
    case a of
      TyTuple cs | all isRegisterTy cs -> pure ()
      TyUnit -> pure ()
      _ | isRegisterTy a -> pure ()
      _ -> err101 "unsupported extern input type" t a
    case b of
      TyUnit -> pure ()
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
