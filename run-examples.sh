rm -f fort.tix
cabal run fort -- examples/helloworld.fort --run

cabal run fort -- lib/stack.fort --main-is=test --run
cabal run fort -- lib/append-buffer.fort --main-is=test --run
cabal run fort -- lib/piece-buffer.fort --main-is=test --run
cabal run fort -- lib/rope.fort --main-is=test --run

cabal run fort -- examples/mandelbrot.fort
examples/mandelbrot.fort.ll.exe > mandelbrot.pbm
cabal run fort -- examples/spectral-norm.fort
examples/spectral-norm.fort.ll.exe 5500
cabal run fort -- examples/intro.fort --run
cabal run fort -- examples/sieve.fort --run
cabal run fort -- examples/fannkuch-redux.fort --run
cabal run fort -- examples/n-body.fort --run
cabal run fort -- examples/fasta.fort --run
cabal run fort -- examples/lfsr.fort
examples/lfsr.fort.ll.exe | wc
cabal run fort -- lib/ansi.fort --main-is=test --run
cabal run fort -- examples/lexer.fort --run --main-is=test
cabal run fort -- examples/colorize.fort
examples/colorize.fort.ll.exe examples/mandelbrot.fort
cabal run fort -- examples/sieve-simple.fort --run

