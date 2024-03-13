-- File generated by the BNF Converter (bnfc 2.9.4.1).

-- Templates for pattern matching on abstract syntax

{-# OPTIONS_GHC -fno-warn-unused-matches #-}

module Fort.Skel where

import Prelude (($), Either(..), String, (++), Show, show)
import qualified Fort.Abs

type Err = Either String
type Result = Err String

failure :: Show a => a -> Result
failure x = Left $ "Undefined case: " ++ show x

transADoubleTok :: Fort.Abs.ADoubleTok -> Result
transADoubleTok x = case x of
  Fort.Abs.ADoubleTok string -> failure x

transAStringTok :: Fort.Abs.AStringTok -> Result
transAStringTok x = case x of
  Fort.Abs.AStringTok string -> failure x

transBinTok :: Fort.Abs.BinTok -> Result
transBinTok x = case x of
  Fort.Abs.BinTok string -> failure x

transCharTok :: Fort.Abs.CharTok -> Result
transCharTok x = case x of
  Fort.Abs.CharTok string -> failure x

transDecTok :: Fort.Abs.DecTok -> Result
transDecTok x = case x of
  Fort.Abs.DecTok string -> failure x

transHexTok :: Fort.Abs.HexTok -> Result
transHexTok x = case x of
  Fort.Abs.HexTok string -> failure x

transInfixOpTok :: Fort.Abs.InfixOpTok -> Result
transInfixOpTok x = case x of
  Fort.Abs.InfixOpTok string -> failure x

transIntTok :: Fort.Abs.IntTok -> Result
transIntTok x = case x of
  Fort.Abs.IntTok string -> failure x

transLIdentTok :: Fort.Abs.LIdentTok -> Result
transLIdentTok x = case x of
  Fort.Abs.LIdentTok string -> failure x

transOctTok :: Fort.Abs.OctTok -> Result
transOctTok x = case x of
  Fort.Abs.OctTok string -> failure x

transPrefixOpTok :: Fort.Abs.PrefixOpTok -> Result
transPrefixOpTok x = case x of
  Fort.Abs.PrefixOpTok string -> failure x

transUIdentTok :: Fort.Abs.UIdentTok -> Result
transUIdentTok x = case x of
  Fort.Abs.UIdentTok string -> failure x

transModule :: Show a => Fort.Abs.Module' a -> Result
transModule x = case x of
  Fort.Abs.Module _ decls -> failure x

transTupleElemExp :: Show a => Fort.Abs.TupleElemExp' a -> Result
transTupleElemExp x = case x of
  Fort.Abs.TupleElemExp _ exp -> failure x

transTupleElemPat :: Show a => Fort.Abs.TupleElemPat' a -> Result
transTupleElemPat x = case x of
  Fort.Abs.TupleElemPat _ pat -> failure x

transTupleElemType :: Show a => Fort.Abs.TupleElemType' a -> Result
transTupleElemType x = case x of
  Fort.Abs.TupleElemType _ type_ -> failure x

transLayoutElemTField :: Show a => Fort.Abs.LayoutElemTField' a -> Result
transLayoutElemTField x = case x of
  Fort.Abs.LayoutElemTField _ tfield -> failure x

transLayoutElemTSum :: Show a => Fort.Abs.LayoutElemTSum' a -> Result
transLayoutElemTSum x = case x of
  Fort.Abs.LayoutElemTSum _ tsum -> failure x

transLayoutElemExp :: Show a => Fort.Abs.LayoutElemExp' a -> Result
transLayoutElemExp x = case x of
  Fort.Abs.LayoutElemExp _ exp -> failure x

transLayoutElemStmt :: Show a => Fort.Abs.LayoutElemStmt' a -> Result
transLayoutElemStmt x = case x of
  Fort.Abs.LayoutElemStmt _ stmt -> failure x

transLayoutElemIfBranch :: Show a => Fort.Abs.LayoutElemIfBranch' a -> Result
transLayoutElemIfBranch x = case x of
  Fort.Abs.LayoutElemIfBranch _ ifbranch -> failure x

transLayoutElemCaseAlt :: Show a => Fort.Abs.LayoutElemCaseAlt' a -> Result
transLayoutElemCaseAlt x = case x of
  Fort.Abs.LayoutElemCaseAlt _ casealt -> failure x

transLayoutElemFieldDecl :: Show a => Fort.Abs.LayoutElemFieldDecl' a -> Result
transLayoutElemFieldDecl x = case x of
  Fort.Abs.LayoutElemFieldDecl _ fielddecl -> failure x

transLayoutElemTailRecDecl :: Show a => Fort.Abs.LayoutElemTailRecDecl' a -> Result
transLayoutElemTailRecDecl x = case x of
  Fort.Abs.LayoutElemTailRecDecl _ tailrecdecl -> failure x

transLayoutElemExpDecl :: Show a => Fort.Abs.LayoutElemExpDecl' a -> Result
transLayoutElemExpDecl x = case x of
  Fort.Abs.LayoutElemExpDecl _ expdecl -> failure x

transADouble :: Show a => Fort.Abs.ADouble' a -> Result
transADouble x = case x of
  Fort.Abs.ADouble _ adoubletok -> failure x

transAString :: Show a => Fort.Abs.AString' a -> Result
transAString x = case x of
  Fort.Abs.AString _ astringtok -> failure x

transAltPat :: Show a => Fort.Abs.AltPat' a -> Result
transAltPat x = case x of
  Fort.Abs.PCon _ uident pat -> failure x
  Fort.Abs.PDefault _ lident -> failure x
  Fort.Abs.PEnum _ uident -> failure x
  Fort.Abs.PScalar _ scalar -> failure x

transBinding :: Show a => Fort.Abs.Binding' a -> Result
transBinding x = case x of
  Fort.Abs.Delayed _ lident -> failure x
  Fort.Abs.Immediate _ pat -> failure x

transCaseAlt :: Show a => Fort.Abs.CaseAlt' a -> Result
transCaseAlt x = case x of
  Fort.Abs.CaseAlt _ altpat exp -> failure x

transDecl :: Show a => Fort.Abs.Decl' a -> Result
transDecl x = case x of
  Fort.Abs.ExpDecl _ expdecl -> failure x
  Fort.Abs.ExportDecl _ astring quallident type_ -> failure x
  Fort.Abs.InfixDecl _ infixop infixinfo -> failure x
  Fort.Abs.PrefixDecl _ prefixop quallident -> failure x
  Fort.Abs.QualDecl _ uident astring -> failure x
  Fort.Abs.TypeDecl _ uident type_ -> failure x

transExp :: Show a => Fort.Abs.Exp' a -> Result
transExp x = case x of
  Fort.Abs.Where _ exp layoutelemexpdecls -> failure x
  Fort.Abs.Lam _ bindings exp -> failure x
  Fort.Abs.Typed _ exp type_ -> failure x
  Fort.Abs.With _ exp layoutelemfielddecls -> failure x
  Fort.Abs.InfixOper _ exp1 infixop exp2 -> failure x
  Fort.Abs.App _ exp1 exp2 -> failure x
  Fort.Abs.PrefixOper _ prefixop exp -> failure x
  Fort.Abs.Array _ exps -> failure x
  Fort.Abs.Case _ exp layoutelemcasealts -> failure x
  Fort.Abs.Con _ uident -> failure x
  Fort.Abs.Do _ layoutelemstmts -> failure x
  Fort.Abs.EType _ type_ -> failure x
  Fort.Abs.Extern _ astring type_ -> failure x
  Fort.Abs.If _ layoutelemifbranchs -> failure x
  Fort.Abs.Parens _ exp -> failure x
  Fort.Abs.Record _ fielddecls -> failure x
  Fort.Abs.Scalar _ scalar -> failure x
  Fort.Abs.Tuple _ tupleelemexp tupleelemexps -> failure x
  Fort.Abs.Unit _ -> failure x
  Fort.Abs.Var _ lident -> failure x
  Fort.Abs.XArray _ layoutelemexps -> failure x
  Fort.Abs.XDot _ exp lident -> failure x
  Fort.Abs.XRecord _ layoutelemfielddecls -> failure x

transExpDecl :: Show a => Fort.Abs.ExpDecl' a -> Result
transExpDecl x = case x of
  Fort.Abs.Binding _ binding exp -> failure x
  Fort.Abs.TailRec _ tailrecdecls -> failure x

transFieldDecl :: Show a => Fort.Abs.FieldDecl' a -> Result
transFieldDecl x = case x of
  Fort.Abs.FieldDecl _ lident exp -> failure x

transFixity :: Show a => Fort.Abs.Fixity' a -> Result
transFixity x = case x of
  Fort.Abs.InfixL _ -> failure x
  Fort.Abs.InfixN _ -> failure x
  Fort.Abs.InfixR _ -> failure x

transIfBranch :: Show a => Fort.Abs.IfBranch' a -> Result
transIfBranch x = case x of
  Fort.Abs.IfBranch _ exp1 exp2 -> failure x

transInfixInfo :: Show a => Fort.Abs.InfixInfo' a -> Result
transInfixInfo x = case x of
  Fort.Abs.InfixInfo _ quallident fixity adouble -> failure x

transInfixOp :: Show a => Fort.Abs.InfixOp' a -> Result
transInfixOp x = case x of
  Fort.Abs.InfixOp _ infixoptok -> failure x

transLIdent :: Show a => Fort.Abs.LIdent' a -> Result
transLIdent x = case x of
  Fort.Abs.LIdent _ lidenttok -> failure x

transPat :: Show a => Fort.Abs.Pat' a -> Result
transPat x = case x of
  Fort.Abs.PParens _ pat -> failure x
  Fort.Abs.PTuple _ tupleelempat tupleelempats -> failure x
  Fort.Abs.PTyped _ pat type_ -> failure x
  Fort.Abs.PUnit _ -> failure x
  Fort.Abs.PVar _ lident -> failure x

transPrefixOp :: Show a => Fort.Abs.PrefixOp' a -> Result
transPrefixOp x = case x of
  Fort.Abs.PrefixOp _ prefixoptok -> failure x

transQualLIdent :: Show a => Fort.Abs.QualLIdent' a -> Result
transQualLIdent x = case x of
  Fort.Abs.Qual _ uident lident -> failure x
  Fort.Abs.UnQual _ lident -> failure x

transScalar :: Show a => Fort.Abs.Scalar' a -> Result
transScalar x = case x of
  Fort.Abs.AFalse _ -> failure x
  Fort.Abs.ATrue _ -> failure x
  Fort.Abs.Char _ chartok -> failure x
  Fort.Abs.Double _ adouble -> failure x
  Fort.Abs.Int _ inttok -> failure x
  Fort.Abs.String _ astring -> failure x
  Fort.Abs.UInt _ uint -> failure x

transSize :: Show a => Fort.Abs.Size' a -> Result
transSize x = case x of
  Fort.Abs.SzNat _ uint -> failure x
  Fort.Abs.SzVar _ lident -> failure x

transStmt :: Show a => Fort.Abs.Stmt' a -> Result
transStmt x = case x of
  Fort.Abs.Stmt _ exp -> failure x
  Fort.Abs.TailRecLet _ tailrecdecls -> failure x
  Fort.Abs.XLet _ exp1 exp2 -> failure x

transTField :: Show a => Fort.Abs.TField' a -> Result
transTField x = case x of
  Fort.Abs.TField _ lident type_ -> failure x

transTSum :: Show a => Fort.Abs.TSum' a -> Result
transTSum x = case x of
  Fort.Abs.TCon _ uident type_ -> failure x
  Fort.Abs.TEnum _ uident -> failure x

transTailRecDecl :: Show a => Fort.Abs.TailRecDecl' a -> Result
transTailRecDecl x = case x of
  Fort.Abs.TailRecDecl _ lident1 lident2 exp -> failure x

transTailRecDecls :: Show a => Fort.Abs.TailRecDecls' a -> Result
transTailRecDecls x = case x of
  Fort.Abs.TailRecDecls _ layoutelemtailrecdecls -> failure x

transType :: Show a => Fort.Abs.Type' a -> Result
transType x = case x of
  Fort.Abs.TLam _ lidents type_ -> failure x
  Fort.Abs.TFun _ type_1 type_2 -> failure x
  Fort.Abs.TApp _ type_1 type_2 -> failure x
  Fort.Abs.TArray _ -> failure x
  Fort.Abs.TBool _ -> failure x
  Fort.Abs.TChar _ -> failure x
  Fort.Abs.TFloat _ -> failure x
  Fort.Abs.TInt _ -> failure x
  Fort.Abs.TName _ uident -> failure x
  Fort.Abs.TOpaque _ astring -> failure x
  Fort.Abs.TParens _ type_ -> failure x
  Fort.Abs.TPointer _ -> failure x
  Fort.Abs.TQualName _ uident1 uident2 -> failure x
  Fort.Abs.TRecord _ layoutelemtfields -> failure x
  Fort.Abs.TSize _ uint -> failure x
  Fort.Abs.TSizes _ sizes -> failure x
  Fort.Abs.TString _ -> failure x
  Fort.Abs.TSum _ layoutelemtsums -> failure x
  Fort.Abs.TTuple _ tupleelemtype tupleelemtypes -> failure x
  Fort.Abs.TUInt _ -> failure x
  Fort.Abs.TUnit _ -> failure x
  Fort.Abs.TVar _ lident -> failure x
  Fort.Abs.TVector _ -> failure x

transUIdent :: Show a => Fort.Abs.UIdent' a -> Result
transUIdent x = case x of
  Fort.Abs.UIdent _ uidenttok -> failure x

transUInt :: Show a => Fort.Abs.UInt' a -> Result
transUInt x = case x of
  Fort.Abs.Bin _ bintok -> failure x
  Fort.Abs.Dec _ dectok -> failure x
  Fort.Abs.Hex _ hextok -> failure x
  Fort.Abs.Oct _ octtok -> failure x
