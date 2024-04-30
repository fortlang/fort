{- HLINT ignore "Redundant multi-way if" -}
{-# LANGUAGE CApiFFI #-}

module Fort.Prims
  ( Err
  , assertWithMessage
  , evalBlockM
  , exitPrim
  , fun
  , primCallTys
  , primCalls
  , store
  , eqVal
  )

where

import Control.Monad.Except
import Foreign.C
import Foreign.LibFFI
import Fort.Type hiding (M)
import Fort.Utils
import Fort.Val
import System.Posix.DynamicLinker
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

type Err a = Either (Doc ()) a

primCallTys :: Map Text (Ty -> Err Ty)
primCallTys = Map.fromList $ fmap f
  [ ("Prim.print", \a -> pure $ TyUnit (positionOf a))
  , ("Prim.alloca", isTypeExpr allocaTC)
  , ("Prim.load", loadTC)
  , ("Prim.typeof", \t -> pure (TyType (positionOf t) t))
  , ("Prim.countof", countofTC)
  , ("Prim.index", isPair indexTC)
  , ("Prim.store", isPair storeTC)
  , ("Prim.assert", isPair assertTC)
  , ("Prim.eq", isPair eqTC)
  , ("Prim.ne", isPair eqTC)
  , ("Prim.exit", exit)
  , ("Prim.neg", neg)
  , ("Prim.add", isPair $ isSameSz arith)
  , ("Prim.sub", isPair $ isSameSz arith)
  , ("Prim.mul", isPair $ isSameSz arith)
  , ("Prim.div", isPair $ isSameSz signedArith)
  , ("Prim.rem", isPair $ isSameSz signedArith)
  , ("Prim.lt", isPair $ isSameSz cmp)
  , ("Prim.gt", isPair $ isSameSz cmp)
  , ("Prim.lte", isPair $ isSameSz cmp)
  , ("Prim.gte", isPair $ isSameSz cmp)
  , ("Prim.shl", isPair $ isSameSz bitop)
  , ("Prim.shr", isPair $ isSameSz bitop)
  , ("Prim.or", isPair $ isSameSz bitop)
  , ("Prim.and", isPair $ isSameSz bitop)
  , ("Prim.xor", isPair $ isSameSz bitop)
  , ("Prim.cast", isPair (isTypeExpr2 castTC))
  , ("Prim.abs", signedIntOrFloat)
  , ("Prim.sqrt", float)
  , ("Prim.sin", float)
  , ("Prim.cos", float)
  , ("Prim.floor", float)
  , ("Prim.ceil", float)
  , ("Prim.truncate", float)
  , ("Prim.round", float)
  , ("Prim.memcpy", isTriple memcpyTC)
  , ("Prim.memmove", isTriple memmoveTC)
  , ("Prim.memset", isTriple memsetTC)
  , ("Prim.append-build", appendBuildTC)
  , ("Prim.insert-element", isTriple insertElementTC)
  , ("Prim.typeof-element", typeofElementTC)
  , ("Prim.select", isTriple selectTC)
  , ("Prim.reduce-min", reduceMinTC)
  ]
  where
    f (nm, g) = (nm, g)

reduceMinTC :: Ty -> Err Ty
reduceMinTC x = case x of
  TyVector _ _ t -> pure t
  _ -> throwError "expected vector type"

selectTC :: Ty -> Ty -> Ty -> Err Ty
selectTC a b c = case (a, b, c) of
  (TyVector _ sza ta, TyVector _ szb tb, TyVector _ szc tc) | sza == szb && szb == szc && ta == tb && tb == tc -> pure b
  -- BAL: ^ break this up to give better errors
  _ -> throwError "unexpected inputs to 'select'"

insertElementTC :: Ty -> Ty -> Ty -> Err Ty
insertElementTC a b c = case a of
  TyVector _ _ t -> if
    | c /= t -> throwError "element doesn't match vector element type"
    | isI32Ty b -> pure a
    | otherwise -> throwError "expected i32 index"
  _ -> throwError "expected vector type"

isTriple :: (Ty -> Ty -> Ty -> Err a) -> Ty -> Err a
isTriple f x = case x of
  TyTuple _ (Cons2 a (b :| [c])) -> f a b c
  _ -> throwError "expected 3-tuple of values"

isI32orI64Ty :: Ty -> Bool
isI32orI64Ty x = isIntTy x && (bitsize x == 32 || bitsize x == 64)

isI32Ty :: Ty -> Bool
isI32Ty x = isIntTy x && bitsize x == 32

isI8Ty :: Ty -> Bool
isI8Ty x = isIntTy x && bitsize x == 8

memcpyTC :: Ty -> Ty -> Ty -> Err Ty
memcpyTC x y z = case (x, y) of
  (TyPointer pos a, TyPointer _ b) | isI8Ty a && isI8Ty b && isI32orI64Ty z -> pure $ TyUnit pos
  _ -> throwError "expected ptr i8, ptr i8, i32/i64 types to 'memcpy'"

memmoveTC :: Ty -> Ty -> Ty -> Err Ty
memmoveTC x y z = case (x, y) of
  (TyPointer pos a, TyPointer _ b) | isI8Ty a && isI8Ty b && isI32orI64Ty z -> pure $ TyUnit pos
  _ -> throwError "expected ptr i8, ptr, i32/i64 types to 'memmove'"

memsetTC :: Ty -> Ty -> Ty -> Err Ty
memsetTC x y z = case x of
  TyPointer pos a | isI8Ty a && isI8Ty y && isI32orI64Ty z -> pure $ TyUnit pos
  _ -> throwError "expected ptr i8, i8, i32/i64 types to 'memset'"

assertTC :: Ty -> Ty -> Err Ty
assertTC msg x = case (msg, x) of
  (TyString pos, TyBool _) -> pure $ TyUnit pos
  _ -> throwError "incompatible types to 'assert'"

indexTC :: Ty -> Ty -> Err Ty
indexTC a ix = case a of
  _ | not $ isIntTy ix -> throwError "expected int indexing value"
  TyPointer pos (TyArray _ _ t) | isAllocaTy t -> pure $ TyPointer pos t
  _ -> throwError "unexpected input type to 'index'"

storeScalarVal :: Val -> Val -> M Val
storeScalarVal p x = case typeOf p of
  TyPointer _ ta | isRegisterTy ta && typeOf x `isSmallerOrEq` ta -> do
    s <- toString (intTySyn $ typeOf x)
    let nm = "FORT_" <> "store" <> "_" <> s
    fun (TyUnit pos) nm $ VTuple pos $ fromList2 [ x, p ]
  t -> err111 "unexpected type to 'store'" t p noTCHint
  where
  pos = positionOf p

isEqTC :: Ty -> Ty -> Bool
isEqTC x y = case (x, y) of
  (TyEnum{}, TyEnum{}) -> True
  _ | isRegisterTy x -> x == y
  (TyArray _ sza a, TyArray _ szb b) -> sza == szb && isEqTC a b
  (TyTuple _ bs, TyTuple _ cs) -> length2 bs == length2 cs &&
    and (zipWith isEqTC (toList bs) (toList cs))
  (TyRecord _ m, TyRecord _ n) | n `isEqualByKeys` m ->
    Map.isSubmapOfBy isEqTC m n
  (TySum _ m, TySum _ n) -> and $ Map.elems $ Map.intersectionWith sumTyIsEqTC m n
  _ -> False

sumTyIsEqTC :: Maybe Ty -> Maybe Ty -> Bool
sumTyIsEqTC x y = case (x, y) of
  (Just a, Just b) -> a `isEqTC` b
  (Nothing, Nothing) -> True
  _ -> False

isSmallerOrEq :: Ty -> Ty -> Bool
isSmallerOrEq x y = case (x, y) of
  (TyEnum _ bs, TyEnum _ cs) -> bs `Set.isSubsetOf` cs
  _ | isRegisterTy x -> x == y
  (TyArray _ sza a, TyArray _ szb b) -> sza == szb && isSmallerOrEq a b
  (TyTuple _ bs, TyTuple _ cs) -> length2 bs == length2 cs &&
    and (zipWith isSmallerOrEq (toList bs) (toList cs))
  (TyRecord _ m, TyRecord _ n) | n `isEqualByKeys` m ->
    Map.isSubmapOfBy isSmallerOrEq m n
  (TySum _ m, TySum _ n) -> Map.isSubmapOfBy sumTyIsSmallerOrEq m n
  _ -> False

sumTyIsSmallerOrEq :: Maybe Ty -> Maybe Ty -> Bool
sumTyIsSmallerOrEq x y = case (x, y) of
  (Just a, Just b) -> a `isSmallerOrEq` b
  (Nothing, Nothing) -> True
  _ -> False

storeTC :: Ty -> Ty -> Err Ty
storeTC ptr ty = case ptr of
  TyPointer _ t
    | isAllocaTy t && isSmallerOrEq ty t -> pure $ TyUnit pos
    | otherwise -> throwError "incompatible types to 'store'"
  _ -> throwError "expected pointer type to 'store'"
  where pos = positionOf ptr

loadTC :: Ty -> Err Ty
loadTC x0 = case x0 of
  TyPointer _ TyArray{} -> throwError "unable to 'load' values of array type"
  TyPointer _ t | isAllocaTy t -> go t
  _ -> throwError "unexpected type to 'load'"
  where
    go x = case x of
      TyTuple pos ps -> TyTuple pos <$> mapM go ps
      TyRecord pos m -> TyRecord pos <$> mapM go m
      TySum pos m -> TySum pos <$> mapM (mapM go) m
      TyArray pos _ _ -> pure $ TyPointer pos x -- don't chase this reference
      _ | isRegisterTy x -> pure x
      _ -> throwError "unexpected type of value to 'load'"

eqTC :: Ty -> Ty -> Err Ty
eqTC a b = if
  | a `isEqTC` b -> case a of
      TyVector{} -> pure a
      _ -> pure $ TyBool $ positionOf a
  | otherwise -> throwError "expected the input values to have the same type"

exit :: Ty -> Err Ty
exit t = case t of
  TyUnit pos -> pure $ TyUnit pos
  TyInt pos I32 -> pure $ TyUnit pos
  _ -> throwError "expected int 32 or unit as exit value"

neg :: Ty -> Err Ty
neg t = if
  | isTyFloat t || isTyInt t -> pure t
  | otherwise -> throwError "expected float or signed int input value"

isPair :: (Ty -> Ty -> Err a) -> Ty -> Err a
isPair f t = case t of
  TyTuple _ (Cons2 a (b :| [])) -> f a b
  _ -> throwError "expected pair of values"

isSameSz :: (Ty -> Ty -> Err a) -> Ty -> Ty -> Err a
isSameSz f a b = do
  r <- f a b
  unless (bitsize a == bitsize b) $
    throwError "expected input values of the same size"
  pure r

isTypeExpr :: (Ty -> Err a) -> Ty -> Err a
isTypeExpr f t = case t of
  TyType _ a -> f a
  _ -> throwError "expected type expression value"

isTypeExpr2 :: (Ty -> Ty -> Err a) -> Ty -> Ty -> Err a
isTypeExpr2 f a t = case t of
  TyType _ b -> f a b
  _ -> throwError "expected type expression as second argument"

compatArithTys :: Ty -> Ty -> Bool
compatArithTys a b = isTyFloat a && isTyFloat b || isIntTy a && isIntTy b

cmp :: Ty -> Ty -> Err Ty
cmp a b = if
  | compatArithTys a b -> pure $ TyBool $ positionOf a
  | otherwise -> throwError "expected matching int or float input types to comparison function"

signedArith :: Ty -> Ty -> Err Ty
signedArith a b = if
  | isTyFloat a && isTyFloat b ||
    isTyInt a && isTyInt b ||
    isUIntTy a && isUIntTy b -> pure a
  | otherwise -> throwError "expected matching int or float input types to signed arithmetic function"

arith :: Ty -> Ty -> Err Ty
arith a b = if
  | compatArithTys a b -> pure a
  | otherwise -> throwError "expected matching int or float input types to arithmetic function"

bitop :: Ty -> Ty -> Err Ty
bitop a b = if
  | isIntTy a && isIntTy b -> pure a
  | otherwise -> throwError "expected int types to bitwise function"

isTyPointer :: Ty -> Bool
isTyPointer x = case x of
  TyPointer{} -> True
  _ -> False

isTyFloat :: Ty -> Bool
isTyFloat x = case x of
  TyFloat{} -> True
  _ -> False

andVal :: Val -> Val -> M Val
andVal x y = evalIf x (pure y) (pure $ VScalar pos $ VBool pos False)
  where pos = positionOf x

orVal :: Val -> Val -> M Val
orVal x y = evalIf x (pure $ VScalar pos $ VBool pos True) (pure y)
  where pos = positionOf x

primCalls :: Map Text (Val -> M Val)
primCalls = Map.fromList $ fmap f
  [ ("Prim.print", \_ v -> printVal v >> pure (VUnit $ positionOf v))
  , ("Prim.alloca", \_ v -> alloca v)
  , ("Prim.load", \_ v -> load v)
  , ("Prim.index", \_ v -> pairFun index v)
  , ("Prim.store", \_ v -> pairFun store v >> pure (VUnit $ positionOf v))
  , ("Prim.assert", \_ v -> pairFun assert v >> pure (VUnit $ positionOf v))
  , ("Prim.typeof", \_ v -> pure $ VType (positionOf v) $ typeOf v)
  , ("Prim.countof", \_ v -> countof v)
  , ("Prim.eq", \_ v -> pairFun eqVal v)
  , ("Prim.ne", \_ v -> pairFun neVal v)
  , ("Prim.exit", \_ v -> exitPrim v)
  , ("Prim.neg", \_ v -> negVal v)
  , ("Prim.lt", \_ -> pairFun $ boolCall2SynPure "lt")
  , ("Prim.gt", \_ -> pairFun $ boolCall2SynPure "gt")
  , ("Prim.lte", \_ -> pairFun $ boolCall2SynPure "lte")
  , ("Prim.gte", \_ -> pairFun $ boolCall2SynPure "gte")

  , ("Prim.add", \_ -> pairFun $ idCall2Syn "add")
  , ("Prim.sub", \_ -> pairFun $ idCall2Syn "sub")
  , ("Prim.mul", \_ -> pairFun $ idCall2Syn "mul")
  , ("Prim.shl", \_ -> pairFun $ idCall2Syn "shl")
  , ("Prim.shr", \_ -> pairFun $ idCall2Syn "shr")
  , ("Prim.and", \_ -> pairFun $ idCall2Syn "and")
  , ("Prim.xor", \_ -> pairFun $ idCall2Syn "xor")
  , ("Prim.or", \_ -> pairFun $ idCall2Syn "or")

  , ("Prim.div", \_ -> pairFun $ idCall2 "div")
  , ("Prim.rem", \_ -> pairFun $ idCall2 "rem")

  , ("Prim.abs", \_ -> idCall "abs")
  , ("Prim.sqrt", \_ -> idCall "sqrt")
  , ("Prim.sin", \_ -> idCall "sin")
  , ("Prim.cos", \_ -> idCall "cos")
  , ("Prim.floor", \_ -> idCall "floor")
  , ("Prim.ceil", \_ -> idCall "ceil")
  , ("Prim.truncate", \_ -> idCall "trunc")
  , ("Prim.round", \_ -> idCall "round")

  , ("Prim.cast", \_ -> pairFun cast)
  , ("Prim.memcpy", \_ -> tripleFun $ memCall "memcpy")
  , ("Prim.memmove", \_ -> tripleFun $ memCall "memmove")
  , ("Prim.memset", \_ -> tripleFun $ memCall "memset")
  , ("Prim.append-build", \_ -> appendBuild)
  , ("Prim.insert-element", \_ -> tripleFun insertElement)
  , ("Prim.typeof-element", \_ -> typeofElement)
  , ("Prim.select", \_ -> tripleFun select)
  , ("Prim.reduce-min", \_ -> reduceMin)
  ]
  where
    f (n, g) = (n, g n)

mul :: Val -> Val -> M Val
mul = idCall2Syn "mul"

sub :: Val -> Val -> M Val
sub = idCall2Syn "sub"

idCall2Syn :: Text -> Val -> Val -> M Val
idCall2Syn n x y = do
  s <- toString (intTySyn t)
  let nm = "FORT_" <> n <> "_" <> s
  fun t nm $ VTuple pos $ fromList2 [x, y]
  where
  t = typeOf x
  pos = positionOf x

pureF :: M a -> M a
pureF m = do
  r <- gets isPure
  modify' $ \st -> st{ isPure = False }
  a <- m
  modify' $ \st -> st{ isPure = r }
  pure a

boolCall2SynPure :: Text -> Val -> Val -> M Val
boolCall2SynPure n x y = do
  s <- toString (intTySyn t)
  let nm = "FORT_" <> n <> "_" <> s
  pureF $ fun rt nm $ VTuple pos $ fromList2 [x, y]
  where
  t = typeOf x
  pos = positionOf x
  rt = case t of
    TyVector{} -> t
    _ -> TyBool pos

gte :: Val -> Val -> M Val
gte = boolCall2SynPure "gte"

lt :: Val -> Val -> M Val
lt = boolCall2SynPure "lt"

loadScalarVal :: Val -> M Val
loadScalarVal x = case typeOf x of
  TyPointer _ t | isRegisterTy t -> do
    s <- toString (intTySyn t)
    let nm = "FORT_" <> "load" <> "_" <> s
    fun t nm x
  t -> err111 "unexpected type to 'load'" x t noTCHint

reduceMin :: Val -> M Val
reduceMin x = case t of
  TyVector _ _ a -> do
    s <- toString (intTySyn t)
    let nm = "FORT_reduce_min_" <> s
    fun a nm x
  _ -> err111 "unexpected type to 'reduce-min'" x t noTCHint
  where
  t = typeOf x

select :: Val -> Val -> Val -> M Val
select x y z = do
  s <- toString (intTySyn t)
  let nm = "FORT_select_" <> s
  fun t nm $ VTuple pos $ fromList2 [x, y, z]
  where
  pos = positionOf x
  t = typeOf y

insertElement :: Val -> Val -> Val -> M Val
insertElement x y z = do
  s <- toString (intTySyn t)
  let nm = "FORT_insert_element_" <> s
  fun t nm $ VTuple pos $ fromList2 [x, y, z]
  where
  pos = positionOf x
  t = typeOf x

memCall :: Text -> Val -> Val -> Val -> M Val
memCall n x y z = do
  s <- toString (intTySyn t)
  let nm = "FORT_" <> n <> "_" <> s
  fun (TyUnit pos) nm $ VTuple pos $ fromList2 [x, y, z]
  where
  t = typeOf z
  pos = positionOf x

intTySyn :: Ty -> Ty
intTySyn x = case x of
  TyUInt pos sz -> case sz of
    U8 -> TyInt pos I8
    U16 -> TyInt pos I16
    U32 -> TyInt pos I32
    U64 -> TyInt pos I64
  TyChar pos -> TyInt pos I8
  TyString pos -> TyPointer pos (TyChar pos)
  TyVector pos sz t -> TyVector pos sz $ intTySyn t
  _ -> x

negVal :: Val -> M Val
negVal x = case typeOf x of
  TyFloat{} -> idCall "neg" x
  _ -> do
    i <- iconst 0 $ typeOf x
    sub i x

idCall :: Text -> Val -> M Val
idCall n x = do
  s <- toString t
  let nm = "FORT_" <> n <> "_" <> s
  fun t nm x
  where
  t = typeOf x

toString :: Ty -> M Text
toString t = case t of
  TyFloat _ F32 -> pure "float"
  TyFloat _ F64 -> pure "double"
  TyInt _ sz -> pure ("i" <> Text.pack (show $ szBitsize sz))
  TyUInt _ sz -> pure ("u" <> Text.pack (show $ szBitsize sz))
  TyChar _ -> pure "c8"
  TyPointer{} -> pure "ptr"
  TyEnum{} -> pure "i32"
  TyString{} -> pure "ptr"
  TyBool{} -> pure "i1"
  TyVector _ sz a -> do
    s <- toString a
    pure ("v" <> Text.pack (show $ szVector sz) <> "_" <> s)
  _ -> err101 "unexpected type" t noTCHint

exitPrim :: Val -> M Val
exitPrim v = fun1 (const $ TyUnit pos) "Prim.exit" v
  where
  pos = positionOf v

iconst :: Integer -> Ty -> M Val
iconst i x = case x of
  TyInt _ sz -> ok $ VInt pos $ case sz of
    I8 -> VInt8 $ fromInteger i
    I16 -> VInt16 $ fromInteger i
    I32 -> VInt32 $ fromInteger i
    I64 -> VInt64 $ fromInteger i
  TyUInt _ sz -> ok $ VUInt pos $ case sz of
    U8 -> VUInt8 $ fromInteger i
    U16 -> VUInt16 $ fromInteger i
    U32 -> VUInt32 $ fromInteger i
    U64 -> VUInt64 $ fromInteger i
  _ -> err101 "expected signed or unsigned integer type" x noTCHint
  where
    ok = pure . VScalar pos
    pos = positionOf x

appendBuildTC :: Ty -> Err Ty
appendBuildTC x = case x of
  TyString pos -> pure $ TyUnit pos
  _ -> throwError "expected string input type"

float :: Ty -> Err Ty
float a = if
  | isTyFloat a -> pure a
  | otherwise -> throwError "expected float input type"

signedIntOrFloat :: Ty -> Err Ty
signedIntOrFloat a = if
  | isTyInt a || isTyFloat a -> pure a
  | otherwise -> throwError "expected signed int or float input type"

neSumDataVals :: Map UIdent (Maybe Val) -> (UIdent, Maybe Val) -> M Val
neSumDataVals m (c, mv) = case (mv, Map.lookup c m) of
  (Just v, Just (Just v')) -> neVal v v'
  (Nothing, Just Nothing) -> pure $ VScalar pos $ VBool pos False
  _ -> pure $ VScalar pos $ VBool pos True
  where
  pos = positionOf c

eqSumDataVals :: Map UIdent (Maybe Val) -> (UIdent, Maybe Val) -> M Val
eqSumDataVals m (c, mv) = case (mv, Map.lookup c m) of
  (Just v, Just (Just v')) -> eqVal v v'
  (Nothing, Just Nothing) -> pure $ VScalar pos $ VBool pos True
  _ -> pure $ VScalar pos $ VBool pos False
  where
  pos = positionOf c

neVal :: Val -> Val -> M Val
neVal x y = case (x, y) of
  (VTuple pos bs, VTuple _ cs) -> do
    vs <- zipWithM neVal (toList bs) (toList cs)
    foldM orVal (VScalar pos $ VBool pos False) vs
  (VRecord pos m, VRecord _ n) | isEqualByKeys m n -> do
    vs <- intersectionWithM neVal m n
    foldM orVal (VScalar pos $ VBool pos False) $ Map.elems vs
  (VSum pos b m, VSum _ c n) | isValEnum b && isValEnum c -> do
      eqv <- eqVal b c
      evalIf eqv (evalSumAlts b m $ neSumDataVals n) (pure $ VScalar pos $ VBool pos True)
  _ | isRegisterVal x && isRegisterVal y -> boolCall2SynPure "neq" x y
  _ -> err111 "unexpected values to Prim.ne" x y noTCHint

eqVal :: Val -> Val -> M Val
eqVal x y = case (x, y) of
  (VTuple pos bs, VTuple _ cs) -> do
    vs <- zipWithM eqVal (toList bs) (toList cs)
    foldM andVal (VScalar pos $ VBool pos True) vs
  (VRecord pos m, VRecord _ n) | isEqualByKeys m n -> do
    vs <- intersectionWithM eqVal m n
    foldM andVal (VScalar pos $ VBool pos True) $ Map.elems vs
  (VSum pos b m, VSum _ c n) | isValEnum b && isValEnum c -> do
    eqv <- eqVal b c
    evalIf eqv (evalSumAlts b m $ eqSumDataVals n) (pure $ VScalar pos $ VBool pos False)
  _ | isRegisterVal x && isRegisterVal y -> boolCall2SynPure "equ" x y
  _ -> err111 "unexpected values to Prim.eq" x y noTCHint

appendBuild :: Val -> M Val
appendBuild x = case x of
  VScalar _ (VString pos s) -> do
    modify' $ \st -> st{ buildCmd = s : buildCmd st }
    pure $ VUnit pos
  _ -> err101 "expected immutable String value to Prim.append-build" x noTCHint

printPrim :: Val -> M ()
printPrim v = case typeOf v of
  _ | TyEnum{} <- typeOf v, VScalar _ (VUndef _ _) <- v ->
    unreachable001 "unable to print undef value" (v, typeOf v)
  TyPointer _ (TyChar _) -> f "Pointer"
  TyPointer{} -> do
    a <- cast v $ VType pos $ TyPointer pos (TyChar pos)
    printPrim a
  _ -> f $ Text.pack (filter (' ' /=) $ show $ pretty (typeOf v))
  where
    f nm = pushDecl $ VLet (VUnit pos) $ VCall ("FORT_print_" <> nm) v
    pos = positionOf v

printFld :: (LIdent, Val) -> M ()
printFld (k, v) = do
  printStrLit $ textOf k
  printStrLit " = "
  printVal v

printSumAlt :: (UIdent, Maybe Val) -> M Val
printSumAlt (c, mv) = do
  printStrLit (textOf c)
  case mv of
    Nothing -> pure ()
    Just v -> do
      printChLit ' '
      printVal v
  pure $ VUnit $ positionOf c

printSep :: Text -> (a -> M ()) -> [a] -> M ()
printSep _ _ [] = unreachable001 "empty list passed to printSep" ()
printSep s f (v : vs) = do
  f v
  sequence_ [ printStrLit s >> f a | a <- vs ]

allocaTC :: Ty -> Err Ty
allocaTC x = if
  | isAllocaTy x -> pure $ TyPointer (positionOf x) x
  | otherwise -> throwError "unexpected type to alloca"

isAllocaTy :: Ty -> Bool
isAllocaTy x = case x of
  TyFun _ a b -> go [a, b]
  TyRecord _ m -> go $ Map.elems m
  TySum _ m -> go $ catMaybes $ Map.elems m
  TyTuple _ bs -> go $ toList bs
  TyArray _ _ a -> isAllocaTy a
  TyPointer _ a -> isAllocaTy a
  TyVector _ _ a -> isRegisterTy a
  TyEnum{} -> True
  TyString{} -> True
  TyChar{} -> True
  TyFloat{} -> True
  TyInt{} -> True
  TyUInt{} -> True
  TyBool{} -> True
  _ -> False
  where
  go :: [Ty] -> Bool
  go = and . fmap isAllocaTy

alloca :: Val -> M Val
alloca x = case x of
  VType pos ty -> VPtr pos (TyPointer pos ty) <$> allocaTy id ty
  _ -> err101 "expected a type value in 'alloca'" x noTCHint

allocaTy :: (Ty -> Ty) -> Ty -> M Val
allocaTy f x = case x of
  TyArray pos sz a -> VIndexed pos x sz <$> allocaTy (f . TyArray pos sz) a
  TyTuple pos ts -> VTuple pos <$> mapM go ts
  TyRecord pos m -> VRecord pos <$> mapM go m
  TySum pos m -> VSum pos <$> allocaRegisterTy (f $ mkTyEnum pos $ Map.keys m) <*> mapM (mapM go) m
  _ | isRegisterTy x -> allocaRegisterTy $ f x
  _ -> err101 "unexpected type in call to 'alloca'" x noTCHint
  where
    go = allocaTy f

evalSumAlts :: Val -> Map UIdent (Maybe Val) -> ((UIdent, Maybe Val) -> M Val) -> M Val
evalSumAlts c0 m f | isValEnum c0 = do
  let xs = sortByFst $ Map.toList m
  blks <- mapM (evalBlockM . f) xs
  cons <- mapM (evalCon . fst) xs
  case zip cons blks of
    [] -> unreachable100 "empty sum type" c0
    (_, dflt) : alts -> switch c0 alts dflt
evalSumAlts c0 _ _ = unreachable001 "expected enum val" (typeOf c0)

typeofElementTC :: Ty -> Err Ty
typeofElementTC x = case x of
  TyType _ t -> typeofElementTC t
  TyPointer _ t -> ok t
  TyArray _ _ t -> ok t
  TyVector _ _ t -> ok t
  TyString{} -> ok $ TyChar (positionOf x)
  _ -> throwError "unexpected type to 'typeof-element'"
  where
    ok = pure . TyType (positionOf x)

countofTC :: Ty -> Err Ty
countofTC x = case x of
  TyType _ t -> countofTC t
  TyPointer _ TyArray{} -> ok
  TyArray{} -> ok
  TyVector{} -> ok
  TyString{} -> ok
  _ -> throwError "unexpected type to 'countof'"
  where
    ok = pure $ TyInt (positionOf x) I32

typeofElement :: Val -> M Val
typeofElement x = case x of
  VType _ t -> typeofElementTy t
  _ -> typeofElementTy $ typeOf x

typeofElementTy :: Ty -> M Val
typeofElementTy x = case x of
  TyVector _ _ t -> ok t
  _ -> err101 "expected vector type" x noTCHint
  where
    ok = pure . VType pos
    pos = positionOf x

countof :: Val -> M Val
countof x = do
  sz <- case x of
    VScalar _ (VString _ s) -> pure $ fromIntegral $ Text.length s
    VType _ t -> countofType t
    _ -> countofType $ typeOf x
  pure $ VScalar pos $ VInt pos $ VInt32 $ fromInteger sz
  where
  pos = positionOf x

countofType :: Ty -> M Sz
countofType x = case x of
  TyPointer _ (TyArray _ sz _) -> pure sz
  TyArray _ sz _ -> pure sz
  TyVector _ _ t -> pure (bitsize x `div` bitsize t)
  _ -> err101 "unexpected type to 'countof'" x noTCHint

load :: Val -> M Val
load x0 = case x0 of
  VPtr _ _ p -> go p
  VScalar{} -> loadScalarVal x0
  _ -> err101 "expected pointer value to 'load'" x0 noTCHint
  where
    go x = case x of
      VTuple pos ps -> VTuple pos <$> mapM go ps
      VRecord pos m -> VRecord pos <$> mapM go m
      VSum pos k m -> do
        con <- go k
        evalSumAlts con m $ \(c, mp) ->
          VSum pos con . Map.singleton c <$> case mp of
            Just a -> Just <$> go a
            Nothing -> pure Nothing
      VScalar{} -> loadScalarVal x
      VIndexed{} -> pure $ VPtr xpos (TyPointer xpos $ typeOf x) x -- don't chase this reference
      _ -> unreachable100 "unexpected value to 'load'" x
      where
      xpos = positionOf x

store :: Val -> Val -> M Val
store p0 x0 = case p0 of
  VPtr _ _ p -> go p x0
  VScalar{} -> storeScalarVal p0 x0
  _ -> err111 "expected pointer value to 'store'" p0 x0 noTCHint
  where
    go p x = case (p, x) of
      (VTuple pos ps, VTuple _ bs) -> do
        zipWithM_ go (toList ps) $ toList bs
        pure $ VUnit pos
      (VRecord pos ps, VRecord _ bs) | isEqualByKeys ps bs -> do
        void $ intersectionWithM go ps bs
        pure $ VUnit pos
      (VSum pos j m, VSum _ k n) -> do
        void $ go j k
        void $ intersectionWithM goSumDataVal m n
        pure $ VUnit pos
      (VScalar{}, _) -> storeScalarVal p x
      (VIndexed pos _ sz r, VArray _ _ vs) | List.genericLength (toList vs) == sz -> do
          zipWithM_ (goValAtIndex r) (toList vs) [0..]
          pure $ VUnit pos
      _ -> err111 "unexpected values to 'store'" p x noTCHint

    goSumDataVal x y = case (x, y) of
      (Just p, Just v) -> Just <$> go p v
      (Nothing, Nothing) -> pure Nothing
      (Just p, Nothing) -> err101 "sum/enum mismatch in call to 'store'" p noTCHint
      (Nothing, Just v) -> err101 "sum/enum mismatch in call to 'store'" v noTCHint

    goValAtIndex r v i = do
      let pos = positionOf v
      p <- transformIndexVal r (VScalar pos (VInt pos $ VInt32 i))
      go p v

transformIndexVal :: Val -> Val -> M Val
transformIndexVal x i = transformM f x
  where
    f val = case val of
      VScalar{} -> indexScalarVal val i
      _ -> pure val

index :: Val -> Val -> M Val
index x0 i = case x0 of
  VPtr pos _ (VIndexed _ _ sz a) -> do
    indexAsserts i sz
    v <- transformIndexVal a i
    pure $ VPtr pos (TyPointer pos $ typeOf a) v
  VScalar{} -> indexScalarVal x0 i
  _ -> err111 "unexpected value to 'index'" x0 (typeOf x0) noTCHint

dimensions :: Ty -> [Sz]
dimensions x = case x of
  TyArray _ sz t -> sz : dimensions t
  _ -> []

muldims :: [Integer] -> Integer
muldims = foldr (*) 1

baseTy :: Ty -> Ty
baseTy x = case x of
  TyArray _ _ t -> baseTy t
  _ -> x

allocaRegisterTy :: Ty -> M Val
allocaRegisterTy ty = freshGlobalVal (TyPointer (positionOf ty) ty) 

indexScalarVal :: Val -> Val -> M Val
indexScalarVal x i = case typeOf x of
  TyPointer _ (TyArray _ sz t) -> do
    indexAsserts i sz
    let offset = muldims (dimensions t)
    j <- iconst offset (typeOf i) >>= mul i
    s1 <- toString (intTySyn $ baseTy t)
    s2 <- toString (intTySyn $ typeOf i)
    let nm = "FORT_" <> "index" <> "_" <> s1 <> "_" <> s2
    fun (TyPointer pos t) nm $ VTuple pos $ fromList2 [x, j]

  t -> err111 "unexpected type of value to 'index'" t x noTCHint
  where
  pos = positionOf x

indexAsserts :: Val -> Sz -> M ()
indexAsserts v sz = if
  | isIntTy t -> do
    void $ iconst 0 t >>= gte v >>= assertWithMessage "index underflow"
    void $ iconst sz t >>= lt v >>= assertWithMessage "index overflow"
  | otherwise -> err111 "unexpected type for 'index' input value" t v noTCHint
  where
  t = typeOf v

assertWithMessage :: Text -> Val -> M Val
assertWithMessage msg val = assert (VScalar pos $ VString pos msg) val
  where pos = positionOf val

assert :: Val -> Val -> M Val
assert msg x = do
  ssb <- gets isSlowSafeBuild
  if
    | ssb -> do
        evalIf x (pure $ VUnit pos) $ do
          printVal $ VScalar pos $ VString pos "assertion failed:"
          printVal msg
          exitPrim $ VScalar pos $ VInt pos $ VInt32 1
    | otherwise -> pure $ VUnit pos
  where
    pos = positionOf msg

printVal :: Val -> M ()
printVal x = case x of
  VTuple _ bs -> do
    printChLit '('
    printSep ", " printVal $ toList bs
    printChLit ')'

  VRecord _ m -> do
    printChLit '{'
    printSep "; " printFld $ sortByFst $ Map.toList m
    printChLit '}'
  
  VSum _ c m -> case typeOf c of
    TyEnum{} -> void $ evalSumAlts c m printSumAlt
    _ -> do
      printChLit '{'
      printStrLit "TAGS = "
      printVal c
      printStrLit "; "
      printSep "; " (void . printSumAlt) $ sortByFst $ Map.toList m
      printChLit '}'

  VArray _ _ vs -> do
    printChLit '['
    printSep ", " printVal $ toList vs
    printChLit ']'

  VUnit _ -> printStrLit "()"
  VScalar _ _ -> printPrim x
  VType _ t -> printStrLit $ Text.pack $ show $ pretty t
  VPtr _ _ a -> printVal a
  VIndexed _ _ sz a -> do
    printChLit '{'
    printStrLit "Size = "
    printStrLit $ Text.pack $ show sz
    printStrLit "; "
    printVal a
    printStrLit "; "
    printChLit '}'

  _-> err100 "unable to 'print' internal value" x

printChLit :: Char -> M ()
printChLit = printPrim . VScalar noPosition . VChar noPosition

printStrLit :: Text -> M ()
printStrLit = printPrim . VScalar noPosition . VString noPosition

castTC :: Ty -> Ty -> Err Ty
castTC a b = if
  | isTyFloat a && isIntTy b ||
    isIntTy a && isTyFloat b ||
    isIntTy a && isTyFloat b ||
    isIntTy a && isTyPointer b ||
    isIntTy a && isUIntTy b ||
    isTyPointer a && isIntTy b -> pure b -- vanilla cast
  | isRegisterTy a && isRegisterTy b -> pure b -- bitcast, trunc, or ext
  | a `isSmallerOrEq` b -> pure b
  | otherwise -> throwError "unexpected cast types"

idCall2 :: Text -> Val -> Val -> M Val
idCall2 n x y = do
  s <- toString t
  let nm = "FORT_" <> n <> "_" <> s
  fun t nm $ VTuple pos $ fromList2 [x, y]
  where
  t = typeOf x
  pos = positionOf x

casttoCall :: Text -> Val -> Ty -> M Val
casttoCall n x ty = do
  s1 <- toString (charTySyn t)
  s2 <- toString (charTySyn ty)
  let nm = "FORT_" <> n <> "_" <> s1 <> "_" <> s2
  fun ty nm x
  where
  t = typeOf x

charTySyn :: Ty -> Ty
charTySyn x = case x of
  TyChar pos -> TyUInt pos U8
  _ -> x

casttoCallSyn :: Text -> Val -> Ty -> M Val
casttoCallSyn n x ty = do
  s1 <- toString (intTySyn t)
  s2 <- toString (intTySyn ty)
  let nm = "FORT_" <> n <> "_" <> s1 <> "_" <> s2
  fun ty nm x
  where
  t = typeOf x

isPointerTy :: Ty -> Bool
isPointerTy x = case x of
  TyPointer{} -> True
  TyString{} -> True
  _ -> False

castCall :: Val -> Ty -> M Val
castCall x ty = if
  | tx == ty -> pure x
  | isPointerTy tx && isIntTy ty -> casttoCall "fromto" x ty
  | isIntTy tx && isPointerTy ty -> casttoCall "fromto" x ty
  | isTyFloat tx && isIntTy ty -> casttoCall "fromto" x ty
  | isIntTy tx && isTyFloat ty -> casttoCall "fromto" x ty
  | bitsize tx > bitsize ty -> casttoCallSyn "truncto" x ty
  | bitsize tx < bitsize ty -> casttoCall "extto" x ty
  | bitsize tx == bitsize ty -> casttoCallSyn "bitcast" x ty
  | otherwise -> unreachable110 "incompatible cast value/type" x ty
  where
    tx = typeOf x

cast :: Val -> Val -> M Val
cast x y = do
  ty <- vTypeToTy y
  if
    | isRegisterVal x && isRegisterTy ty -> castCall x ty
    | typeOf x `isSmallerOrEq` ty -> do
        v <- freshUndefVal ty
        unionVals x v
    | otherwise -> err111 "unexpected values to 'cast'" x y noTCHint

freshUndefVal :: Ty -> M Val
freshUndefVal t = transform f <$> freshVal t
  where
  f x = if
    | isRegisterVal x -> VScalar pos (VUndef pos $ typeOf x)
    | otherwise -> x
    where pos = positionOf x

vTypeToTy :: Val -> M Ty
vTypeToTy x = case x of
  VType _ t -> pure t
  _ -> err100 "expected type expression argument" x

tripleFun :: (Val -> Val -> Val -> M Val) -> Val -> M Val
tripleFun f x = case x of
  VTuple _ (Cons2 a (b :| [c])) -> f a b c
  _ -> err101 "expected 3-tuple argument" x noTCHint

pairFun :: (Val -> Val -> M Val) -> Val -> M Val
pairFun f x = case x of
  VTuple _ (Cons2 a (b :| [])) -> f a b
  _ -> err101 "expected pair argument" x noTCHint

fun1 :: (Ty -> Ty) -> Text -> Val -> M Val
fun1 resTy nm v = fun (resTy $ typeOf v) nm v

callFFIM :: Text -> Val -> RetType a -> M a
callFFIM nm x r = do
  args <- valToArgs x
  dl <- getDynLib
  funPtr <- liftIO $ dlsym dl $ Text.unpack nm
  liftIO $ callFFI funPtr r args

dynCall :: Ty -> Text -> Val -> M Val
dynCall rt nm x = case rt of
    TyUnit{} -> do
      f retVoid
      pure $ VUnit pos
    TyPointer{} -> VScalar pos . VPointer pos rt <$> f (retPtr retVoid)
    TyBool{} -> do
      r <- f retWord8
      pure $ VScalar pos $ VBool pos $ r /= 0
    TyString{} -> do
      r <- f retCString
      VScalar pos . VString pos . Text.pack <$> liftIO (peekCString r)
    TyFloat _ F32 -> VScalar pos . VFloat pos . VFloat32 . realToFrac <$> f retCFloat
    TyFloat _ F64 -> VScalar pos . VFloat pos . VFloat64 . realToFrac <$> f retCDouble
    TyChar _ -> VScalar pos . VChar pos . toEnum . fromIntegral <$> f retWord8
    TyInt _ I8 -> VScalar pos . VInt pos . VInt8 <$> f retInt8
    TyUInt _ U8 -> VScalar pos . VUInt pos . VUInt8 <$> f retWord8
    TyInt _ I16 -> VScalar pos . VInt pos . VInt16 <$> f retInt16
    TyUInt _ U16 -> VScalar pos . VUInt pos . VUInt16 <$> f retWord16
    TyInt _ I32 -> VScalar pos . VInt pos . VInt32 <$> f retInt32
    TyUInt _ U32 -> VScalar pos . VUInt pos . VUInt32 <$> f retWord32
    TyInt _ I64 -> VScalar pos . VInt pos . VInt64 <$> f retInt64
    TyUInt _ U64 -> VScalar pos . VUInt pos . VUInt64 <$> f retWord64
    _ -> err100 "unexpected return type during compile time evaluation" rt
  where
    f :: RetType a -> M a
    f = callFFIM nm x
    pos = positionOf x

getDynLib :: M DL
getDynLib = do
  mdl <- gets mDynLib
  case mdl of
    Nothing -> do
      dl <- liftIO $ dlopen "fort-ffi.dylib" []
      modify' $ \st -> st{ mDynLib = Just dl }
      pure dl
    Just dl -> pure dl

valToArgs :: Val -> M [Arg]
valToArgs x = case x of
  VTuple _ vs -> mapM f $ toList vs
  _ -> (:[]) <$> f x
  where
    f :: Val -> M Arg
    f v = case v of
      VScalar _ a -> case a of
        VString _ t -> pure $ argString $ Text.unpack t
        VPointer _ _ p -> pure $ argPtr p
        VBool _ b -> pure $ argWord8 $ fromIntegral $ fromEnum b
        VChar _ c -> pure $ argWord8 $ fromIntegral $ fromEnum c
        VFloat _ i -> case i of
          VFloat32 b -> pure $ argCFloat $ realToFrac b
          VFloat64 b -> pure $ argCDouble $ realToFrac b
        VInt _ i -> case i of
          VInt8 b -> pure $ argInt8 b
          VInt16 b -> pure $ argInt16 b
          VInt32 b -> pure $ argInt32 b
          VInt64 b -> pure $ argInt64 b
        VUInt _ i -> case i of
          VUInt8 b -> pure $ argWord8 b
          VUInt16 b -> pure $ argWord16 b
          VUInt32 b -> pure $ argWord32 b
          VUInt64 b -> pure $ argWord64 b
        VUndef{} -> err100 "undefined value encountered during compile time evaluation" v
        VEnum _ _ i -> pure $ argWord32 $ fromInteger i
        _ -> err100 "unexpected scalar value encountered during compile time evaluation" v
      _ -> err100 "unexpected value encountered during compile time evaluation" v

fun :: Ty -> Text -> Val -> M Val
fun rt nm v = if
  | isExternArgTy (typeOf v) && isExternResultTy rt -> do
      isP <- gets isPure
      if isP
        then do
          isFE <- isFullyEvaluated v
          if isFE
            then dynCall rt nm v
            else ok
        else ok
  | otherwise -> ok
  where
    ok = case rt of
      TyUnit pos -> do
        pushDecl $ VLet (VUnit pos) $ VCall nm v
        pure $ VUnit pos
      _ -> do
        r <- freshRegisterVal rt
        pushDecl $ VLet r $ VCall nm v
        pure r

isFullyEvaluated :: Val -> M Bool
isFullyEvaluated x = case x of
  VType{} -> pure True
  VUnit{} -> pure True
  VScalar _ a -> pure $ isVScalarEvaluated a
  VArray _ _ bs -> and <$> mapM go bs
  VRecord _ bs -> and <$> mapM go (Map.elems bs)
  VSum _ v bs -> (&&) <$> go v <*> (and <$> mapM go (catMaybes $ Map.elems bs))
  VTuple _ bs -> and <$> mapM go bs
  VIndexed _ _ _ v -> go v
  VPtr _ _ v -> go v
  _ -> pure False
  where
    go = isFullyEvaluated

isVScalarEvaluated :: VScalar -> Bool
isVScalarEvaluated v = case v of
   VUndef{} -> False
   XVFreshRegVal{} -> False
   VRegister{} -> False
   VExtern{} -> False
   _ -> True


