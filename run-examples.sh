cabal run fort -- examples/helloworld.fort --run
cabal run fort -- examples/append-buffer.fort --main-is=test --run
cabal run fort -- examples/mandelbrot.fort
examples/mandelbrot.fort.ll.exe > mandelbrot.pbm
cabal run fort -- examples/spectral-norm.fort
examples/spectral-norm.fort.ll.exe 5500
cabal run fort -- examples/stack.fort --main-is=test --run
cabal run fort -- examples/intro.fort --run
cabal run fort -- examples/sieve.fort --run
cabal run fort -- examples/piece-buffer.fort --main-is=test --run
cabal run fort -- examples/fannkuch-redux.fort --run
cabal run fort -- examples/n-body.fort --run
cabal run fort -- examples/fasta.fort --run
cabal run fort -- examples/rope.fort --main-is=test --run
cabal run fort -- examples/lexer.fort --run

