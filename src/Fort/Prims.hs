{- HLINT ignore "Redundant multi-way if" -}

module Fort.Prims
  ( Err
  , assertWithMessage
  , evalBlockM
  , evalIf
  , evalSwitch
  , exitPrim
  , fun
  , primCallTys
  , primCalls
  , store
  )

where

import Control.Monad.Except
import Fort.Type hiding (M)
import Fort.Utils
import Fort.Val
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified Data.List as List
import qualified Data.Set as Set

type Err a = Either (Doc ()) a

primCallTys :: Map LIdent (Ty -> Err Ty)
primCallTys = Map.fromList $ fmap f
  [ ("Prim.print", \_ -> pure TyUnit)
  , ("Prim.alloca", isTypeExpr allocaTC)
  , ("Prim.load", loadTC)
  , ("Prim.typeof", pure . TyType)
  , ("Prim.countof", countofTC)
  , ("Prim.index", isPair indexTC)
  , ("Prim.store", isPair storeTC)
  , ("Prim.assert", isPair assertTC)
  , ("Prim.eq", isPair eq)
  , ("Prim.ne", isPair eq)
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
  ]
  where
    f (nm, g) = (mkTok noPosition nm, g)

isTriple :: (Ty -> Ty -> Ty -> Err a) -> Ty -> Err a
isTriple f x = case x of
  TyTuple [a, b, c] -> f a b c
  _ -> throwError "expected 3-tuple of values"

isI32orI64Ty :: Ty -> Bool
isI32orI64Ty x = isIntTy x && (bitsize x == 32 || bitsize x == 64)

isI8Ty :: Ty -> Bool
isI8Ty x = isIntTy x && bitsize x == 8

memcpyTC :: Ty -> Ty -> Ty -> Err Ty
memcpyTC x y z = case (x, y) of
  (TyPointer a, TyPointer b) | isI8Ty a && isI8Ty b && isI32orI64Ty z -> pure TyUnit
  _ -> throwError "expected ptr i8, ptr i8, i32/i64 types to 'memcpy'"

memmoveTC :: Ty -> Ty -> Ty -> Err Ty
memmoveTC x y z = case (x, y) of
  (TyPointer a, TyPointer b) | isI8Ty a && isI8Ty b && isI32orI64Ty z -> pure TyUnit
  _ -> throwError "expected ptr i8, ptr, i32/i64 types to 'memmove'"

memsetTC :: Ty -> Ty -> Ty -> Err Ty
memsetTC x y z = case x of
  TyPointer a | isI8Ty a && isI8Ty y && isI32orI64Ty z -> pure TyUnit
  _ -> throwError "expected ptr i8, i8, i32/i64 types to 'memset'"

assertTC :: Ty -> Ty -> Err Ty
assertTC msg x = case (msg, x) of
  (TyString, TyBool) -> pure TyUnit
  _ -> throwError "incompatible types to 'assert'"

indexTC :: Ty -> Ty -> Err Ty
indexTC a ix = case a of
  _ | not $ isIntTy ix -> throwError "expected int indexing value"
  TyPointer (TyArray _ t) -> pure $ TyPointer t
  _ -> throwError "unexpected input type to 'index'"

isSubmapByKeys :: Ord k => Map k a -> Map k a -> Bool
isSubmapByKeys = Map.isSubmapOfBy (\_ _ -> True)

isEqualByKeys :: Ord k => Map k a -> Map k a -> Bool
isEqualByKeys a b = isSubmapByKeys a b && isSubmapByKeys b a

sumTyIsSmallerOrEq :: Maybe Ty -> Maybe Ty -> Bool
sumTyIsSmallerOrEq x y = case (x, y) of
  (Just a, Just b) -> a `isSmallerOrEq` b
  (Nothing, Nothing) -> True
  _ -> False

isSmallerOrEq :: Ty -> Ty -> Bool
isSmallerOrEq x y = case (x, y) of
  (TyEnum bs, TyEnum cs) -> bs `Set.isSubsetOf` cs
  _ | isRegisterTy x -> x == y
  (TyArray sza a, TyArray szb b) -> sza == szb && isSmallerOrEq a b
  (TyTuple bs, TyTuple cs) -> length bs == length cs &&
    and (zipWith isSmallerOrEq bs cs)
  (TyRecord m, TyRecord n) | n `isEqualByKeys` m ->
    Map.isSubmapOfBy isSmallerOrEq m n
  (TySum m, TySum n) -> Map.isSubmapOfBy sumTyIsSmallerOrEq m n
  _ -> False

storeTC :: Ty -> Ty -> Err Ty
storeTC ptr ty = case ptr of
  TyPointer t
    | isSmallerOrEq ty t -> pure TyUnit
    | otherwise -> throwError "incompatible types to 'store'"
  _ -> throwError "expected pointer type to 'store'"

loadTC :: Ty -> Err Ty
loadTC x0 = case x0 of
  TyPointer TyArray{} -> throwError "unable to 'load' values of array type"
  TyPointer t -> go t
  _ -> throwError "expected pointer type to 'load'"
  where
    go x = case x of
      TyTuple ps -> TyTuple <$> mapM go ps
      TyRecord m -> TyRecord <$> mapM go m
      TySum m -> TySum <$> mapM (mapM go) m
      TyArray{} -> pure $ TyPointer x -- don't chase this reference
      _ | isRegisterTy x -> pure x
      _ -> throwError "unexpected type of value to 'load'"

eq :: Ty -> Ty -> Err Ty
eq a b = if
  | eqTys a b -> pure TyBool
  | otherwise -> throwError "expected the input values to have the same type"

eqMaybes :: Maybe Ty -> Maybe Ty -> Bool
eqMaybes x y = case (x, y) of
  (Nothing, Nothing) -> True
  (Just a, Just b) -> eqTys a b
  _ -> False

eqTys :: Ty -> Ty -> Bool
eqTys x y = case (x, y) of
  (TySum m, TySum n) -> and $ Map.elems $ Map.intersectionWith eqMaybes m n
  (TyRecord m, TyRecord n) -> List.sort (Map.keys m) == List.sort (Map.keys n) && and bs
    where
      bs = Map.elems $ Map.intersectionWith eqTys m n
  (TyTuple bs, TyTuple cs) -> length bs == length cs && and (uncurry eqTys <$> zip bs cs)
  (TyArray sza a, TyArray szb b) -> sza == szb && eqTys a b
  _ -> x == y

exit :: Ty -> Err Ty
exit t = if
  | t == TyUnit || t == TyInt 32 -> pure TyUnit
  | otherwise -> throwError "expected int 32 or unit as exit value"

neg :: Ty -> Err Ty
neg t = if
  | isTyFloat t || isTyInt t -> pure t
  | otherwise -> throwError "expected float or signed int input value"

isPair :: (Ty -> Ty -> Err a) -> Ty -> Err a
isPair f t = case t of
  TyTuple [a, b] -> f a b
  _ -> throwError "expected pair of values"

isSameSz :: (Ty -> Ty -> Err a) -> Ty -> Ty -> Err a
isSameSz f a b = do
  r <- f a b
  unless (bitsize a == bitsize b) $
    throwError "expected input values of the same size"
  pure r

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

isTypeExpr :: (Ty -> Err a) -> Ty -> Err a
isTypeExpr f t = case t of
  TyType a -> f a
  _ -> throwError "expected type expression value"

isTypeExpr2 :: (Ty -> Ty -> Err a) -> Ty -> Ty -> Err a
isTypeExpr2 f a t = case t of
  TyType b -> f a b
  _ -> throwError "expected type expression as second argument"

compatArithTys :: Ty -> Ty -> Bool
compatArithTys a b = isTyFloat a && isTyFloat b || isIntTy a && isIntTy b

cmp :: Ty -> Ty -> Err Ty
cmp a b = if
  | compatArithTys a b -> pure TyBool
  | otherwise -> throwError "expected int or float input values to comparison function"

signedArith :: Ty -> Ty -> Err Ty
signedArith a b = if
  | isTyFloat a && isTyFloat b ||
    isTyInt a && isTyInt b ||
    isUIntTy a && isUIntTy b -> pure a
  | otherwise -> throwError "expected compatible int or float input values to arithmetic function"

arith :: Ty -> Ty -> Err Ty
arith a b = if
  | compatArithTys a b -> pure a
  | otherwise -> throwError "expected int or float input values to arithmetic function"

bitop :: Ty -> Ty -> Err Ty
bitop a b = if
  | isIntTy a && isIntTy b -> pure a
  | otherwise -> throwError "expected int values to bitwise function"

isTyPointer :: Ty -> Bool
isTyPointer x = case x of
  TyPointer _ -> True
  _ -> False

isTyFloat :: Ty -> Bool
isTyFloat x = case x of
  TyFloat _ -> True
  _ -> False

primCall2 :: Text -> Val -> Val -> M Val
primCall2 nm a b = lookup_ (mkTok noPosition nm) primCalls $ VTuple [a, b]

gte :: Val -> Val -> M Val
gte = primCall2 "Prim.gte"

lt :: Val -> Val -> M Val
lt = primCall2 "Prim.lt"

andVal :: Val -> Val -> M Val
andVal = primCall2 "Prim.and"

orVal :: Val -> Val -> M Val
orVal = primCall2 "Prim.or"

primCalls :: Map LIdent (Val -> M Val)
primCalls = Map.fromList $ fmap f
  [ ("Prim.print", \_ v -> printVal v >> pure VUnit)
  , ("Prim.alloca", \_ v -> alloca v)
  , ("Prim.load", \_ v -> load v)
  , ("Prim.index", \_ v -> pairFun index v)
  , ("Prim.store", \_ v -> pairFun store v >> pure VUnit)
  , ("Prim.assert", \_ v -> pairFun assert v >> pure VUnit)
  , ("Prim.typeof", \_ v -> pure $ VType $ typeOf v)
  , ("Prim.countof", \_ v -> countof v)
  , ("Prim.eq", \_ v -> pairFun eqVal v)
  , ("Prim.ne", \_ v -> pairFun neVal v)
  , ("Prim.exit", \_ v -> exitPrim v)
  , ("Prim.neg", \_ v -> negVal v)
  , ("Prim.add", idFun2)
  , ("Prim.sub", idFun2)
  , ("Prim.mul", idFun2)
  , ("Prim.div", idFun2)
  , ("Prim.rem", idFun2)
  , ("Prim.lt", boolFun2)
  , ("Prim.gt", boolFun2)
  , ("Prim.lte", boolFun2)
  , ("Prim.gte", boolFun2)
  , ("Prim.shl", idFun2)
  , ("Prim.shr", idFun2)
  , ("Prim.or", idFun2)
  , ("Prim.and", idFun2)
  , ("Prim.xor", idFun2)
  , ("Prim.cast", \_ v -> pairFun cast v)
  , ("Prim.abs", idFun1)
  , ("Prim.sqrt", idFun1)
  , ("Prim.sin", idFun1)
  , ("Prim.cos", idFun1)
  , ("Prim.floor", idFun1)
  , ("Prim.ceil", idFun1)
  , ("Prim.truncate", idFun1)
  , ("Prim.round", idFun1)
  , ("Prim.memcpy", memFun)
  , ("Prim.memmove", memFun)
  , ("Prim.memset", memFun)
  ]
  where
    f (n, g) = (mkTok noPosition n, g n)

exitPrim :: Val -> M Val
exitPrim = fun1 (const TyUnit) "Prim.exit"

sub :: Val -> Val -> M Val
sub = primCall2 "Prim.sub"

negVal :: Val -> M Val
negVal x = case typeOf x of
  TyFloat{} -> fun1 id "Prim.neg" x
  _ -> sub (VScalar (VInt 0)) x

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
  (Nothing, Nothing) -> pure $ VScalar $ VBool False
  _ -> pure $ VScalar $ VBool True

neVal :: Val -> Val -> M Val
neVal x y = case (x, y) of
  (VTuple bs, VTuple cs) -> do
    vs <- zipWithM neVal bs cs
    foldM orVal (VScalar $ VBool False) vs
  (VRecord m, VRecord n) -> do
    vs <- intersectionWithM neVal m n
    foldM orVal (VScalar $ VBool False) $ Map.elems vs
  (VSum b m, VSum c n) | isValEnum b && isValEnum c -> do
      eqv <- eqVal b c
      blkt <- evalBlockM (evalSumAlts b m $ neSumDataVals n)
      blkf <- evalBlockM (pure $ VScalar $ VBool True)
      evalIf eqv blkt blkf
  _ | isRegisterVal x && isRegisterVal y -> boolFun2 "Prim.ne" $ VTuple [x, y]
  _ -> err101 "unexpected values to Prim.ne" (noPos (x, y)) noTCHint

eqSumDataVals :: Map UIdent (Maybe Val) -> (UIdent, Maybe Val) -> M Val
eqSumDataVals m (c, mv) = case (mv, Map.lookup c m) of
  (Just v, Just (Just v')) -> eqVal v v'
  (Nothing, Just Nothing) -> pure $ VScalar $ VBool True
  _ -> pure $ VScalar $ VBool False

eqVal :: Val -> Val -> M Val
eqVal x y = case (x, y) of
  (VTuple bs, VTuple cs) -> do
    vs <- zipWithM eqVal bs cs
    foldM andVal (VScalar $ VBool True) vs
  (VRecord m, VRecord n) -> do
    vs <- intersectionWithM eqVal m n
    foldM andVal (VScalar $ VBool True) $ Map.elems vs
  (VSum b m, VSum c n) | isValEnum b && isValEnum c -> do
    eqv <- eqVal b c
    blkt <- evalBlockM (evalSumAlts b m $ eqSumDataVals n)
    blkf <- evalBlockM (pure $ VScalar $ VBool False)
    evalIf eqv blkt blkf
  _ | isRegisterVal x && isRegisterVal y -> boolFun2 "Prim.eq" $ VTuple [x, y]
  _ -> err101 "unexpected values to Prim.eq" (noPos (x, y)) noTCHint

printPrim :: Val -> M ()
printPrim v = case typeOf v of
  _ | TyEnum{} <- typeOf v, VScalar (VUndef _) <- v ->
    unreachable001 "unable to print undef value" (v, typeOf v)
  TyPointer (TyChar 8) -> f "Pointer"
  TyPointer{} -> do
    a <- cast v $ VType $ TyPointer (TyChar 8)
    printPrim a
  _ -> f $ Text.pack (filter (' ' /=) $ show $ pretty (typeOf v))
  where
    f nm = pushDecl $ VLet VUnit $ VCall (mkTok noPosition ("FORT_print_" <> nm)) v

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
  pure VUnit

printSep :: Text -> (a -> M ()) -> [a] -> M ()
printSep _ _ [] = unreachable001 "empty list passed to printSep" ()
printSep s f (v : vs) = do
  f v
  sequence_ [ printStrLit s >> f a | a <- vs ]

allocaTC :: Ty -> Err Ty
allocaTC = pure . TyPointer

alloca :: Val -> M Val
alloca x = case x of
  VType ty -> VPtr (TyPointer ty) <$> allocaTy id ty
  _ -> err101 "expected a type value in 'alloca'" (noPos x) noTCHint

allocaTy :: (Ty -> Ty) -> Ty -> M Val
allocaTy f x = case x of
  TyArray sz a -> VIndexed x sz <$> allocaTy (f . TyArray sz) a
  TyTuple ts -> VTuple <$> mapM go ts
  TyRecord m -> VRecord <$> mapM go m
  TySum m -> VSum <$> allocaRegisterTy (f $ mkTyEnum $ Map.keys m) <*> mapM (mapM go) m
  _ | isRegisterTy x -> allocaRegisterTy $ f x
  _ -> err101 "unexpected type in call to 'alloca'" (noPos x) noTCHint
  where
    go = allocaTy f

allocaRegisterTy :: Ty -> M Val
allocaRegisterTy ty = do
  v <- freshRegisterVal (TyPointer ty) 
  pushDecl $ VLet v $ VCall (mkTok noPosition "Prim.alloca") $ VType ty
  pure v
 
evalSumAlts :: Val -> Map UIdent (Maybe Val) -> ((UIdent, Maybe Val) -> M Val) -> M Val
evalSumAlts c0 m f | isValEnum c0 = do
  let xs = sortByFst $ Map.toList m
  blks <- mapM (evalBlockM . f) xs
  cons <- mapM (evalCon . fst) xs
  evalSwitch c0 [ AltScalar c blk | (c, blk) <- zip cons blks ]
evalSumAlts c0 _ _ = unreachable001 "expected enum val" (typeOf c0)

countofTC :: Ty -> Err Ty
countofTC x = case x of
  TyType t -> countofTC t
  TyPointer TyArray{} -> pure $ TyInt 32
  TyArray{} -> pure $ TyInt 32
  TyString{} -> pure $ TyInt 32
  _ -> throwError "unexpected type to 'countof'"

countof :: Val -> M Val
countof x = do
  sz <- case x of
    VScalar (VString s) -> pure $ fromIntegral $ Text.length s
    VType t -> countofType t
    _ -> countofType $ typeOf x
  pure $ VScalar $ VInt sz

countofType :: Ty -> M Sz
countofType x = case x of
  TyPointer (TyArray sz _) -> pure sz
  TyArray sz _ -> pure sz
  t -> err111 "unexpected type to 'countof'" (noPos t) (noPos x) noTCHint

load :: Val -> M Val
load x0 = case x0 of
  VPtr _ p -> go p
  VScalar a -> loadScalar a
  _ -> err101 "expected pointer value to 'load'" (noPos x0) noTCHint
  where
    go x = case x of
      VTuple ps -> VTuple <$> mapM go ps
      VRecord m -> VRecord <$> mapM go m
      VSum k m -> do
        con <- go k
        evalSumAlts con m $ \(c, mp) ->
          VSum con . Map.singleton c <$> case mp of
            Just a -> Just <$> go a
            Nothing -> pure Nothing
      VScalar a -> loadScalar a
      VIndexed{} -> pure $ VPtr (TyPointer $ typeOf x) x -- don't chase this reference
      _ -> unreachable100 "unexpected value to 'load'" (noPos x)

loadScalar :: VScalar -> M Val
loadScalar x = case typeOf x of
  TyPointer t | isRegisterTy t -> fun1 (const t) "Prim.load" $ VScalar x
  t -> err111 "unexpected type to 'load'" (noPos t) (noPos x) noTCHint

store :: Val -> Val -> M Val
store p0 x0 = case p0 of
  VPtr _ p -> go p x0
  VScalar a -> storeScalar a x0
  _ -> err101 "expected pointer value to 'store'" (noPos p0) noTCHint
  where
    go p x = case (p, x) of
      (VTuple ps, VTuple bs) -> do
        zipWithM_ go ps bs
        pure VUnit
      (VRecord ps, VRecord bs) -> do
        void $ intersectionWithM go ps bs
        pure VUnit
      (VSum j m, VSum k n) -> do
        void $ go j k
        void $ intersectionWithM goSumDataVal m n
        pure VUnit
      (VScalar a, _) -> storeScalar a x
      (VIndexed _ sz r, VArray vs) | List.genericLength vs == sz -> do
          zipWithM_ (goValAtIndex r) vs [0..]
          pure VUnit
      _ -> err111 "unexpected values to 'store'" (noPos p) (noPos x) noTCHint

    goSumDataVal x y = case (x, y) of
      (Just p, Just v) -> Just <$> go p v
      (Nothing, Nothing) -> pure Nothing
      _ -> err111 "sum/enum mismatch in call to 'store'" (noPos x) (noPos y) noTCHint

    goValAtIndex r v i = do
      p <- transformIndexVal r (VScalar (VInt i))
      go p v

storeScalar :: VScalar -> Val -> M Val
storeScalar p x = case typeOf p of
  TyPointer ta | isRegisterTy ta && typeOf x `isSmallerOrEq` ta ->
    fun2 (\_ _ -> pure TyUnit) "Prim.store" $ VTuple [ VScalar p, x ]
  t -> err111 "unexpected type to 'store'" (noPos t) (noPos p) noTCHint

bitsize :: Ty -> Sz
bitsize x = case x of
  TyChar sz -> sz
  TyFloat sz -> sz
  TyInt sz -> sz
  TyUInt sz -> sz
  TyBool -> 1
  TyPointer _ | isRegisterTy x -> bitsizePointer
  TyString -> bitsizePointer
  _ -> unreachable "unexpected type as input to bitsize" x

transformIndexVal :: Val -> Val -> M Val
transformIndexVal x i = transformM f x
  where
    f val = case val of
      VScalar a -> indexScalar a i
      _ -> pure val

index :: Val -> Val -> M Val
index x0 i = case x0 of
  VPtr _ (VIndexed _ sz a) -> do
    indexAsserts i sz
    v <- transformIndexVal a i
    pure $ VPtr (TyPointer $ typeOf a) v
  VScalar a -> indexScalar a i
  _ -> err111 "unexpected value to 'index'" (noPos x0) (noPos $ typeOf x0) noTCHint

indexScalar :: VScalar -> Val -> M Val
indexScalar x i = case typeOf x of
  TyPointer (TyArray sz t) -> do
    indexAsserts i sz
    fun2 (\_ _ -> pure $ TyPointer t) "Prim.index" $ VTuple [VScalar x, i]
  t -> err111 "unexpected type of value to 'index'" (noPos t) (noPos x) noTCHint

indexAsserts :: Val -> Sz -> M ()
indexAsserts i sz = case typeOf i of
  t | isIntTy t -> do
    void $ gte i (VScalar $ VInt 0) >>= assertWithMessage "index underflow"
    void $ lt i (VScalar $ VInt sz) >>= assertWithMessage "index overflow"
    | otherwise -> err111 "unexpected type for 'index' input value" (noPos t) (noPos i) noTCHint

assertWithMessage :: Text -> Val -> M Val
assertWithMessage msg = assert (VScalar $ VString msg)

assert :: Val -> Val -> M Val
assert msg x = do
  ssb <- gets isSlowSafeBuild
  if
    | ssb -> do
        blkt <- evalBlockM $ pure VUnit
        blkf <- evalBlockM $ do
          printVal $ VScalar $ VString "assertion failed:"
          printVal msg
          exitPrim $ VScalar $ VInt 1
        evalIf x blkt blkf
    | otherwise -> pure VUnit

printVal :: Val -> M ()
printVal x = case x of
  VTuple bs -> do
    printChLit '('
    printSep ", " printVal bs
    printChLit ')'

  VRecord m -> do
    printChLit '{'
    printSep "; " printFld $ sortByFst $ Map.toList m
    printChLit '}'
  
  VSum c m -> case typeOf c of
    TyEnum{} -> void $ evalSumAlts c m printSumAlt
    _ -> do
      printChLit '{'
      printStrLit "TAGS = "
      printVal c
      printStrLit "; "
      printSep "; " (void . printSumAlt) $ sortByFst $ Map.toList m
      printChLit '}'

  VArray vs -> do
    printChLit '['
    printSep ", " printVal vs
    printChLit ']'

  VUnit -> printStrLit "()"
  VScalar _ -> printPrim x
  VType t -> printStrLit $ Text.pack $ show $ pretty t
  VPtr _ a -> printVal a
  VIndexed _ sz a -> do
    printChLit '{'
    printStrLit "Size = "
    printStrLit $ Text.pack $ show sz
    printStrLit "; "
    printVal a
    printStrLit "; "
    printChLit '}'

  _-> unreachable001 "unable to 'print' internal value" x

printChLit :: Char -> M ()
printChLit = printPrim . VScalar . VChar

printStrLit :: Text -> M ()
printStrLit = printPrim . VScalar . VString

cast :: Val -> Val -> M Val
cast x y = do
  t <- vTypeToTy y
  if
    | isRegisterVal x && isRegisterTy t -> fun2 (\_ b -> vTypeToTy b) "Prim.cast" $ VTuple [x, y]
    | typeOf x `isSmallerOrEq` t -> do
        v <- freshUndefVal t
        unionVals x v
    | otherwise -> err111 "unexpected values to 'cast'" (noPos x) (noPos y) noTCHint

freshUndefVal :: Ty -> M Val
freshUndefVal t = transform f <$> freshVal t
  where
  f x = if
    | isRegisterVal x -> VScalar (VUndef $ typeOf x)
    | otherwise -> x

vTypeToTy :: Val -> M Ty
vTypeToTy x = case x of
  VType t -> pure t
  _ -> err100 "expected type expression argument" (noPos x)

idFun2 :: Text -> Val -> M Val
idFun2 = fun2 (\t _ -> pure t)

idFun1 :: Text -> Val -> M Val
idFun1 = fun1 id

memFun :: Text -> Val -> M Val
memFun nm x = case x of
  VTuple [a, b, c] -> do
    pushDecl $ VLet VUnit $ VCall (mkTok noPosition nm) $ VTuple [a, b, c, VScalar $ VBool False]
    pure VUnit
  _ -> err101 "expected 3-tuple argument to memFun" (noPos x) noTCHint

pairFun :: (Val -> Val -> M Val) -> Val -> M Val
pairFun f x = case x of
  VTuple [a, b] -> f a b
  _ -> err101 "expected pair argument to pairFun" (noPos x) noTCHint

fun1 :: (Ty -> Ty) -> Text -> Val -> M Val
fun1 resTy nm v = fun (resTy $ typeOf v) (mkTok noPosition nm) v

fun :: Ty -> LIdent -> Val -> M Val
fun rt nm v = case rt of
  TyUnit -> do
    pushDecl $ VLet VUnit $ VCall nm v
    pure VUnit
  _ -> do
    r <- freshRegisterVal rt
    pushDecl $ VLet r $ VCall nm v
    pure r

boolFun2 :: Text -> Val -> M Val
boolFun2 = fun2 (\_ _ -> pure TyBool)

fun2 :: (Ty -> Val -> M Ty) -> Text -> Val -> M Val
fun2 resTy nm = pairFun $ \a b -> do
  rt <- resTy (typeOf a) b
  fun rt (mkTok noPosition nm) $ VTuple [a, b]

switchValOf :: Val -> M Val
switchValOf x = case x of
  VSum c _ | isSwitchVal c -> pure c
  VScalar _ | isSwitchVal x -> pure x
  _ -> err101 "unexpected switch value in 'case' expression" (noPos x) noTCHint

evalSwitch :: Val -> [Alt] -> M Val
evalSwitch val xs = do
  tg <- switchValOf val
  if
    | null xs -> err101 "empty alternatives" (noPos val) noTCHint
    | (alts, AltDefault dflt : _) <- break isAltDefault xs -> switch tg alts dflt
    | AltScalar sclr blk <- last xs -> do
        blk' <- evalBlockM (eqVal tg (VScalar sclr) >>= assertWithMessage "unmatched 'case' alternative")
        switch tg (init xs) blk{ blockDecls = blockDecls blk' ++ blockDecls blk }
    | otherwise -> unreachable001 "unexpected alternatives" val
  where
    switch :: Val -> [Alt] -> Block -> M Val
    switch tg alts dflt = do
      (r, rdflt : ralts) <- joinVals $ blockResult dflt : [ blockResult b | AltScalar _ b <- alts ]
      pushDecl $ VLet r $ VSwitch tg (dflt{ blockResult = rdflt }) [ AltScalar a b{ blockResult = rb } | (rb, AltScalar a b) <- zip ralts alts ]
      pure r

    isAltDefault :: Alt -> Bool
    isAltDefault x = case x of
      AltDefault{} -> True
      _ -> False

