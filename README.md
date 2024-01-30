# The Fort Programming Language

Fort is a data-oriented general-purpose programming language with a functional style.  The goal is to conveniently build small and fast programs while eliminating the possibility of out-of-memory and stack-overflow errors.

Semantics:
  Fort code compiles into a finite state machine (FSM).  This FSM consists of registers and arrays where the size of the arrays are known at compile time.  This differs from other run-times in that there is no run-time stack and no garbage collection.  This allows fort code to have a fixed, known at compile time memory footprint and how stack overflow and out of memory errors are avoided.

Performance:
  On par with C for size and speed.

Type checking/inference:
  Fort is strongly typed at compile time with full type inference.  Type annotations are provided as machine checked documentation for the user but are never required and have no effect on program semantics.  No run-time typing information is retained after compilation.  Values must be explicitly converted by the user (i.e. no implicit casts).

Syntax:
  Fort syntax resembles a simplified Haskell 'do' syntax.  Instead of functions, fort provides lambdas which are fully evaluated at compile time.  This step essentially 'inlines' all of the code in a fort application.  This inlining can lead to better optimization and it enables the parametric and ad-hoc polymorphism provided by fort.  Unfortunately this inlining has the potential to bloat the generated code so facilities are provided to mitigate this.  The full fort syntax can be seen here: [fort-syntax.md](https://github.com/fortlang/fort/blob/main/doc/fort-syntax.md)

Data structures:
  Fort supports the following primitive data types:  Signed/unsigned integer, floating point, bool, character, immutable string, pointer, opaque types, unit (similar to void in C/LLVM).  The number of bits used by a given numeric type can be specified by the user.

  Fort supports the following container data types: Array, Record, Tuple, Sum.  Arrays are for sequential storage of the contained data type.  Records are for grouping together several data types and giving each one a 'field' name.  Tuples are for grouping together several data types like records but values are referenced by position instead of name.  Sums are for pairing together a 'tag' and a value.  Sums are essentially a C 'union' type that also has a tag indicating which particular type the union value contains at run-time.  Records, tuples, and sums are completely compiled away to ensure no run-time cost.

  Function types are provided to enable linking with C libraries.

Control flow:
  Multiway 'if' expressions provide branching on boolean predicates.  'case' expressions provide branching for numeric data types (similar to a C 'switch') and for deconstructing sum types.

  Iteration is provided via tail recursion (since there is no run-time stack).  The lambda calculus syntax enables the definition of user-defined constructs that are sometimes built in to other languages (e.g. 'for', 'while', etc.).

Integration with C:
  Fort code can be called from and call out to C code/libraries.  The current backend generates LLVM code with plans for future versions to generate C (as well as other backends).

Building:
  The fort compiler is implemented in [haskell](https://www.haskell.org).  I use [ghcup](https://www.haskell.org/ghcup) to track/install the recommended versions of ghc (haskell compiler) and cabal (haskell package manager).

  The fort backend currently produces LLVM code and uses the LLVM code/compiler to build the resultant binary.

  My build uses the following dependencies on osx:

    * cabal 3.10.2.1
    * ghc 9.4.8
    * llvm 17.0.6
    * clang 17.0.6

  Once you have cabal, ghc, and clang in your path you should be able to run:

  ```
  cabal run fort -- --run examples/helloworld.fort
  ```

  You can try out various examples using cabal run or alternatively build the fort executable with:

  ```
  cabal install --installdir=bin
  ```

  Let me know (brett at fortlang.org) If you have success building fort on other platforms or with other versions.

Warning:

   Fort is still in the early stages of development.  The core functionality is there, including:

    * LLVM code generation for all fort syntax
    * interfacing to/from C
    * separate modules
    * test coverage on the entire fort compiler
    * command line arguments to show the results of each compilation step
    * various flags for code generation
    * several working examples from the [programming languages benchmarks game](https://benchmarksgame-team.pages.debian.net/benchmarksgame/index.html)
    * working examples of some data structures, including a [rope](https://en.wikipedia.org/wiki/Rope_(data_structure))

  but many things are not, including:

    * documentation/tutorials
    * pre-built binaries
    * user libraries
    * z3 integration
    * concurrency/parallelism
    * REPL/Debugger/IDE support

  Contributions/feedback are welcome!

cheers,

Brett
