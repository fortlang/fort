The Language Fort
==The lexical structure of Fort==


### Literals 

The regular expressions associated with literal values are as follows:

**String literals**
*'"' (char - [\"] | {"\} | {"\\"} | {"\n"} | '\' digit+ | {"\x"} (["abcdef"] | digit)+)* '"'*

e.g. `"hello, world!"`

**Character literals**
*' (char - ["'\"] | {"\'"} | {"\\"} | {"\n"} | '\' digit+) '*

e.g. `'A'`

**Floating point literals**
*'-'? digit+ '.' digit+ ('e' '-'? digit+)?*

e.g. `3.14`

**Decimal literals**
*'-'? digit+*

e.g. `42`

**Hexidecimal literals**
*{"0x"} (["abcdef"] | digit)+*

e.g. `0xf0`

**Octal literals**
*{"0o"} ["01234567"]+*

e.g. `0o70`

**Binary literals**
*{"0b"} ["01"]+*

e.g. `0b10`

### Identifiers 

The regular expressions associated with identifiers are as follows:

**Lowercase identifiers**
*('_' | lower) (["'-_"] | digit | letter)**

e.g. `foo`

**Uppercase identifiers**
*upper (["'-_"] | digit | letter)**

e.g. `Foo`

**Prefix operators**
*'@' ["!#$%&*+-./:<=>?@^|~"]**

e.g. `@`

**Infix operators**
*["!#$%&*+-./:<=>?^|~"]+*

e.g. `+`

### Reserved words and symbols 

The set of reserved words is the set of terminals appearing in the grammar. Those reserved words that consist of non-letter characters are called symbols, and they are treated in a different way from those that are similar to identifiers. The lexer follows rules familiar from languages like Haskell, C, and Java, including longest match and spacing conventions.

The reserved words used in Fort are the following:

|`Array` |`Bool` |`C` |`F`|
|`False` |`I` |`Opaque` |`Pointer`|
|`Record` |`String` |`Sum` |`True`|
|`U` |`array` |`case` |`do`|
|`export` |`extern` |`if` |`infix`|
|`infixl` |`infixr` |`of` |`operator`|
|`qualifier` |`record` |`tailrec` |`type`|
|`where` |`with` ||

The symbols used in Fort are the following:

|, |; |~ |->|
|= |` |\ |{|
|} |: |[ |]|
|( |) |() |.|
|=> | ||

### Comments 

Single-line comments begin with two semicolons, e.g. `;; this is a comment`.  There are no multiple-line comments in the grammar.

### Layout 

Layout/whitespace is used to denote structure within the code instead of the more traditional braces and semicolons, e.g.

    main = do
      print "hello,"
      println "world!"

If you prefer (or sometimes for concisesness), braces/semicolons syntax is also provided, e.g.

`main = do { print "hello,"; println "world"; }`

## The syntactic structure of Fort 

    StringLit ::= string literal
    CharLit ::= character literal
    FloatLit ::= floating point literal
    
    UIdent ::= uppercase identifier
    LIdent ::= lowercase identifier
    QualLIdent ::= (UIdent ".")? LIdent
    QualUIdent ::= (UIdent ".")? UIdent
    
    PrefixOp ::= prefix operator
    InfixOp ::= infix operator
    
    Module ::= [Decl]
    
    Decl ::=
      | "type" UIdent "=" Type
      | "operator" PrefixOp "=" QualLIdent
      | "operator" InfixOp "=" QualLIdent Fixity FloatingLit
      | "qualifier" UIdent "=" StringLit
      | "export" StringLit "=" QualLIdent "`" Type "`"
      | "tailrec" [LIdent "=" Exp]
      | Binding "=" Exp
    
    Binding ::=
      | Pat
      | "~" LIdent
    
    Pat ::= 
      | Pat ":" "`" Type "`"
      | "(" commasep [Pat] ")"
      | LIdent
    
    Exp ::=
      | "\" [Binding] "->" Exp
      | Exp "where" [Binding "=" Exp]
      | Exp ":" "`" Type "`"
      | Exp "with" [LIdent "=" Exp]
      | Exp InfixOp Exp
      | PrefixOp Exp
      | "extern" StringLit "`" Type "`" 
      | "do" [Stmt]
      | "if" [Exp "->" Exp]
      | "case" Exp "of" [AltPat "->" Exp]
      | "record" [FieldDecl]
      | "{" commasep [LIdent "=" Exp] "}"
      | "(" commasep [Exp] ")"
      | "array" [Exp]
      | "[" commasep [Exp] "]"
      | "`" Type "`"
      | QualLIdent
      | QualUIdent
      | Exp "." LIdent
      | Scalar
    
    Stmt ::=
      | Exp
      | Pat "=" Exp
      | "tailrec" [LIdent "=" Exp]
    
    AltPat ::=
      | Scalar
      | LIdent
      | UIdent Pat?
    
    Fixity ::=
      | "infix"
      | "infixl"
      | "infixr"
    
    Type ::=
      | "\" [LIdent] "=>" Type
      | Type "->" Type
      | Type Type
      | "(" commasep [Type] ")"
      | "Record" [LIdent ":" Type]
      | "Sum" [UIdent (":" Type)?]
      | "Pointer" Type
      | "Array" ArraySize Type
      | "Opaque" StringLit
      | "String"
      | "U" Size
      | "I" Size
      | "F" Size
      | "C" Size
      | "Bool"
      | LIdent
      | QualUIdent
    
    ArraySize ::=
      | "[" commasep [Size] "]"
      | Size
    
    Size ::=
      | UIntLit
      | LIdent
    
    Scalar ::=
      | "True"
      | "False"
      | FloatLit
      | UIntLit
      | StringLit
      | character literal
      | decimal literal
    
    UIntLit ::=
      | digit+
      | hexidecimal literal
      | octal literal
      | binary literal

Note:  This grammar has been simplified somewhat for clarity.  The actually grammar used to generate the lexing/parsing code for fort can be found in fort.grm.

