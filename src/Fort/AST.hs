{-# LANGUAGE PatternSynonyms #-}

module Fort.AST
  ( module Fort.AST
  , module Fort.FunctorAST
  )

where

import qualified Fort.FunctorAST as F
import Fort.Errors

import Fort.FunctorAST hiding (Exp, InfixOp, PrefixOp, LIdent, UIdent, Module, Binding, Decl, ExpDecl, Pat, Fixity, Stmt, AltPat, QualLIdent, InfixInfo, FieldDecl, CaseAlt, Type, Scalar, TField, TSum)

import Fort.FunctorAST (pattern Binding, pattern Module, pattern LIdent, pattern ExpDecl, pattern InfixOp, pattern UIdent, pattern PrefixOp, pattern Stmt, pattern InfixInfo, pattern FieldDecl, pattern CaseAlt, pattern Scalar, pattern TField, pattern TSum)

type Type = F.Type Position
type Scalar = F.Scalar Position
type Exp = F.Exp Position
type TSum = F.TSum Position
type TField = F.TField Position
type CaseAlt = F.CaseAlt Position
type FieldDecl = F.FieldDecl Position
type QualLIdent = F.QualLIdent Position
type InfixInfo = F.InfixInfo Position
type Stmt = F.Stmt Position
type InfixOp = F.InfixOp Position
type PrefixOp = F.PrefixOp Position
type LIdent = F.LIdent Position
type UIdent = F.UIdent Position
type Binding = F.Binding Position
type Module = F.Module Position
type Decl = F.Decl Position
type ExpDecl = F.ExpDecl Position
type Pat = F.Pat Position
type AltPat = F.AltPat Position
type Fixity = F.Fixity Position
