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

primCallTys :: Map AString (Ty -> Err Ty)
primCallTys = Map.fromList $ fmap f
  [ ("Prim.print", \a -> pure $ TyUnit (positionOf a))
  , ("Prim.alloca", isTypeExpr allocaTC)
  , ("Prim.load", loadTC)
  , ("Prim.typeof", \t -> pure (TyType (positionOf t) t))
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
    f (nm, g) = (AString noPosition nm, g)

isTriple :: (Ty -> Ty -> Ty -> Err a) -> Ty -> Err a
isTriple f x = case x of
  TyTuple _ (Cons2 a (b :| [c])) -> f a b c
  _ -> throwError "expected 3-tuple of values"

isI32orI64Ty :: Ty -> Bool
isI32orI64Ty x = isIntTy x && (bitsize x == 32 || bitsize x == 64)

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
  TyPointer pos (TyArray _ _ t) -> pure $ TyPointer pos t
  _ -> throwError "unexpected input type to 'index'"

sumTyIsSmallerOrEq :: Maybe Ty -> Maybe Ty -> Bool
sumTyIsSmallerOrEq x y = case (x, y) of
  (Just a, Just b) -> a `isSmallerOrEq` b
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

storeTC :: Ty -> Ty -> Err Ty
storeTC ptr ty = case ptr of
  TyPointer _ t
    | isSmallerOrEq ty t -> pure $ TyUnit pos
    | otherwise -> throwError "incompatible types to 'store'"
  _ -> throwError "expected pointer type to 'store'"
  where pos = positionOf ptr

loadTC :: Ty -> Err Ty
loadTC x0 = case x0 of
  TyPointer _ TyArray{} -> throwError "unable to 'load' values of array type"
  TyPointer _ t -> go t
  _ -> throwError "expected pointer type to 'load'"
  where
    go x = case x of
      TyTuple pos ps -> TyTuple pos <$> mapM go ps
      TyRecord pos m -> TyRecord pos <$> mapM go m
      TySum pos m -> TySum pos <$> mapM (mapM go) m
      TyArray pos _ _ -> pure $ TyPointer pos x -- don't chase this reference
      _ | isRegisterTy x -> pure x
      _ -> throwError "unexpected type of value to 'load'"

eq :: Ty -> Ty -> Err Ty
eq a b = if
  | a == b -> pure $ TyBool $ positionOf a
  | otherwise -> throwError "expected the input values to have the same type"

exit :: Ty -> Err Ty
exit t = case t of
  TyUnit pos -> pure $ TyUnit pos
  TyInt pos 32 -> pure $ TyUnit pos
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

primCall2 :: Text -> Val -> Val -> M Val
primCall2 nm a b = lookup_ (AString pos nm) primCalls $ VTuple pos $ fromList2 [a, b]
  where pos = positionOf a

gte :: Val -> Val -> M Val
gte = primCall2 "Prim.gte"

lt :: Val -> Val -> M Val
lt = primCall2 "Prim.lt"

andVal :: Val -> Val -> M Val
andVal = primCall2 "Prim.and"

orVal :: Val -> Val -> M Val
orVal = primCall2 "Prim.or"

primCalls :: Map AString (Val -> M Val)
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
    f (n, g) = (AString noPosition n, g n)

exitPrim :: Val -> M Val
exitPrim v = fun1 (const $ TyUnit pos) "Prim.exit" v
  where
  pos = positionOf v

sub :: Val -> Val -> M Val
sub = primCall2 "Prim.sub"

negVal :: Val -> M Val
negVal x = case typeOf x of
  TyFloat{} -> fun1 id "Prim.neg" x
  _ -> sub (VScalar pos (VInt pos 0)) x
  where
  pos = positionOf x

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
  (Nothing, Nothing) -> pure $ VScalar pos $ VBool pos False
  _ -> pure $ VScalar pos $ VBool pos True
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
      blkt <- evalBlockM (evalSumAlts b m $ neSumDataVals n)
      blkf <- evalBlockM (pure $ VScalar pos $ VBool pos True)
      evalIf eqv blkt blkf
  _ | isRegisterVal x && isRegisterVal y -> boolFun2 "Prim.ne" $ VTuple posx $ fromList2 [x, y]
  _ -> err111 "unexpected values to Prim.ne" x y noTCHint
  where
  posx = positionOf x

eqSumDataVals :: Map UIdent (Maybe Val) -> (UIdent, Maybe Val) -> M Val
eqSumDataVals m (c, mv) = case (mv, Map.lookup c m) of
  (Just v, Just (Just v')) -> eqVal v v'
  (Nothing, Just Nothing) -> pure $ VScalar pos $ VBool pos True
  _ -> pure $ VScalar pos $ VBool pos False
  where
  pos = positionOf c

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
    blkt <- evalBlockM (evalSumAlts b m $ eqSumDataVals n)
    blkf <- evalBlockM (pure $ VScalar pos $ VBool pos False)
    evalIf eqv blkt blkf
  _ | isRegisterVal x && isRegisterVal y -> boolFun2 "Prim.eq" $ VTuple posx $ fromList2 [x, y]
  _ -> err111 "unexpected values to Prim.eq" x y noTCHint
  where
  posx = positionOf x

printPrim :: Val -> M ()
printPrim v = case typeOf v of
  _ | TyEnum{} <- typeOf v, VScalar _ (VUndef _ _) <- v ->
    unreachable001 "unable to print undef value" (v, typeOf v)
  TyPointer _ (TyChar _ 8) -> f "Pointer"
  TyPointer{} -> do
    a <- cast v $ VType pos $ TyPointer pos (TyChar pos 8)
    printPrim a
  _ -> f $ Text.pack (filter (' ' /=) $ show $ pretty (typeOf v))
  where
    f nm = pushDecl $ VLet (VUnit pos) $ VCall (AString pos ("FORT_print_" <> nm)) v
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
allocaTC x = pure $ TyPointer (positionOf x) x

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

allocaRegisterTy :: Ty -> M Val
allocaRegisterTy ty = do
  v <- freshRegisterVal (TyPointer pos ty) 
  pushDecl $ VLet v $ VCall (AString pos "Prim.alloca") $ VType pos ty
  pure v
  where
    pos = positionOf ty
 
evalSumAlts :: Val -> Map UIdent (Maybe Val) -> ((UIdent, Maybe Val) -> M Val) -> M Val
evalSumAlts c0 m f | isValEnum c0 = do
  let xs = sortByFst $ Map.toList m
  blks <- mapM (evalBlockM . f) xs
  cons <- mapM (evalCon . fst) xs
  evalSwitch c0 [ AltScalar c blk | (c, blk) <- zip cons blks ]
evalSumAlts c0 _ _ = unreachable001 "expected enum val" (typeOf c0)

countofTC :: Ty -> Err Ty
countofTC x = case x of
  TyType _ t -> countofTC t
  TyPointer pos TyArray{} -> pure $ TyInt pos 32
  TyArray pos _ _ -> pure $ TyInt pos 32
  TyString pos -> pure $ TyInt pos 32
  _ -> throwError "unexpected type to 'countof'"

countof :: Val -> M Val
countof x = do
  sz <- case x of
    VScalar _ (VString _ s) -> pure $ fromIntegral $ Text.length s
    VType _ t -> countofType t
    _ -> countofType $ typeOf x
  pure $ VScalar pos $ VInt pos sz
  where
  pos = positionOf x

countofType :: Ty -> M Sz
countofType x = case x of
  TyPointer _ (TyArray _ sz _) -> pure sz
  TyArray _ sz _ -> pure sz
  _ -> err101 "unexpected type to 'countof'" x noTCHint

load :: Val -> M Val
load x0 = case x0 of
  VPtr _ _ p -> go p
  VScalar _ a -> loadScalar a
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
      VScalar _ a -> loadScalar a
      VIndexed{} -> pure $ VPtr xpos (TyPointer xpos $ typeOf x) x -- don't chase this reference
      _ -> unreachable100 "unexpected value to 'load'" x
      where
      xpos = positionOf x

loadScalar :: VScalar -> M Val
loadScalar x = case typeOf x of
  TyPointer pos t | isRegisterTy t -> fun1 (const t) "Prim.load" $ VScalar pos x
  t -> err111 "unexpected type to 'load'" x t noTCHint

store :: Val -> Val -> M Val
store p0 x0 = case p0 of
  VPtr _ _ p -> go p x0
  VScalar _ a -> storeScalar a x0
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
      (VScalar _ a, _) -> storeScalar a x
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
      p <- transformIndexVal r (VScalar pos (VInt pos i))
      go p v

storeScalar :: VScalar -> Val -> M Val
storeScalar p x = case typeOf p of
  TyPointer _ ta | isRegisterTy ta && typeOf x `isSmallerOrEq` ta ->
    fun2 (\_ _ -> pure $ TyUnit pos) "Prim.store" $ VTuple pos $ fromList2 [ VScalar pos p, x ]
  t -> err111 "unexpected type to 'store'" t p noTCHint
  where
  pos = positionOf p

bitsize :: Ty -> Sz
bitsize x = case x of
  TyChar _ sz -> sz
  TyFloat _ sz -> sz
  TyInt _ sz -> sz
  TyUInt _ sz -> sz
  TyBool{} -> 1
  TyPointer _ _ | isRegisterTy x -> bitsizePointer
  TyString _ -> bitsizePointer
  _ -> unreachable "unexpected type as input to bitsize" x

transformIndexVal :: Val -> Val -> M Val
transformIndexVal x i = transformM f x
  where
    f val = case val of
      VScalar _ a -> indexScalar a i
      _ -> pure val

index :: Val -> Val -> M Val
index x0 i = case x0 of
  VPtr pos _ (VIndexed _ _ sz a) -> do
    indexAsserts i sz
    v <- transformIndexVal a i
    pure $ VPtr pos (TyPointer pos $ typeOf a) v
  VScalar _ a -> indexScalar a i
  _ -> err111 "unexpected value to 'index'" x0 (typeOf x0) noTCHint

indexScalar :: VScalar -> Val -> M Val
indexScalar x i = case typeOf x of
  TyPointer _ (TyArray _ sz t) -> do
    indexAsserts i sz
    fun2 (\_ _ -> pure $ TyPointer pos t) "Prim.index" $ VTuple pos $ fromList2 [VScalar pos x, i]
  t -> err111 "unexpected type of value to 'index'" t x noTCHint
  where
  pos = positionOf x

indexAsserts :: Val -> Sz -> M ()
indexAsserts i sz = case typeOf i of
  t | isIntTy t -> do
    void $ gte i (VScalar pos $ VInt pos 0) >>= assertWithMessage "index underflow"
    void $ lt i (VScalar pos $ VInt pos sz) >>= assertWithMessage "index overflow"
    | otherwise -> err111 "unexpected type for 'index' input value" t i noTCHint
  where
  pos = positionOf i

assertWithMessage :: Text -> Val -> M Val
assertWithMessage msg val = assert (VScalar pos $ VString pos msg) val
  where pos = positionOf val

assert :: Val -> Val -> M Val
assert msg x = do
  ssb <- gets isSlowSafeBuild
  if
    | ssb -> do
        blkt <- evalBlockM $ pure $ VUnit pos
        blkf <- evalBlockM $ do
          printVal $ VScalar pos $ VString pos "assertion failed:"
          printVal msg
          exitPrim $ VScalar pos $ VInt pos 1
        evalIf x blkt blkf
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

  _-> unreachable001 "unable to 'print' internal value" x

printChLit :: Char -> M ()
printChLit = printPrim . VScalar noPosition . VChar noPosition

printStrLit :: Text -> M ()
printStrLit = printPrim . VScalar noPosition . VString noPosition

cast :: Val -> Val -> M Val
cast x y = do
  t <- vTypeToTy y
  let pos = positionOf x
  if
    | isRegisterVal x && isRegisterTy t -> fun2 (\_ b -> vTypeToTy b) "Prim.cast" $ VTuple pos $ fromList2 [x, y]
    | typeOf x `isSmallerOrEq` t -> do
        v <- freshUndefVal t
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

idFun2 :: Text -> Val -> M Val
idFun2 = fun2 (\t _ -> pure t)

idFun1 :: Text -> Val -> M Val
idFun1 = fun1 id

memFun :: Text -> Val -> M Val
memFun nm x = case x of
  VTuple pos (Cons2 a (b :| [c])) -> do
    pushDecl $ VLet (VUnit pos) $ VCall (AString pos nm) $ VTuple pos $ fromList2 [a, b, c, VScalar pos $ VBool pos False]
    pure $ VUnit pos
  _ -> err101 "expected 3-tuple argument to memFun" x noTCHint

pairFun :: (Val -> Val -> M Val) -> Val -> M Val
pairFun f x = case x of
  VTuple _ (Cons2 a (b :| [])) -> f a b
  _ -> err101 "expected pair argument to pairFun" x noTCHint

fun1 :: (Ty -> Ty) -> Text -> Val -> M Val
fun1 resTy nm v = fun (resTy $ typeOf v) (AString (positionOf v) nm) v

fun :: Ty -> AString -> Val -> M Val
fun rt nm v = case rt of
  TyUnit pos -> do
    pushDecl $ VLet (VUnit pos) $ VCall nm v
    pure $ VUnit pos
  _ -> do
    r <- freshRegisterVal rt
    pushDecl $ VLet r $ VCall nm v
    pure r

boolFun2 :: Text -> Val -> M Val
boolFun2 = fun2 (\t _ -> pure $ TyBool $ positionOf t)

fun2 :: (Ty -> Val -> M Ty) -> Text -> Val -> M Val
fun2 resTy nm = pairFun $ \a b -> do
  rt <- resTy (typeOf a) b
  let pos = positionOf a
  fun rt (AString pos nm) $ VTuple pos $ fromList2 [a, b]

switchValOf :: Val -> M Val
switchValOf x = case x of
  VSum _ c _ | isSwitchVal c -> pure c
  VScalar{} | isSwitchVal x -> pure x
  _ -> err101 "unexpected switch value in 'case' expression" x noTCHint

evalSwitch :: Val -> [Alt] -> M Val
evalSwitch val xs = do
  tg <- switchValOf val
  if
    | null xs -> err101 "empty alternatives" val noTCHint
    | (alts, AltDefault dflt : _) <- break isAltDefault xs -> switch tg alts dflt
    | AltScalar sclr blk <- last xs -> do
        blk' <- evalBlockM (eqVal tg (VScalar pos sclr) >>= assertWithMessage "unmatched 'case' alternative")
        switch tg (init xs) blk{ blockDecls = blockDecls blk' ++ blockDecls blk }
    | otherwise -> unreachable001 "unexpected alternatives" val
  where
    pos = positionOf val
    switch :: Val -> [Alt] -> Block -> M Val
    switch tg alts dflt = do
      (r, rdflt : ralts) <- joinVals $ blockResult dflt : [ blockResult b | AltScalar _ b <- alts ]
      pushDecl $ VLet r $ VSwitch tg (dflt{ blockResult = rdflt }) [ AltScalar a b{ blockResult = rb } | (rb, AltScalar a b) <- zip ralts alts ]
      pure r

    isAltDefault :: Alt -> Bool
    isAltDefault x = case x of
      AltDefault{} -> True
      _ -> False

