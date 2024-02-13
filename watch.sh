# cmd="cabal run fort -- --run $1"
#cmd="cabal run fort -- examples/less.fort; ./examples/less.fort.ll.exe $1"
cmd="rm -f examples/colorize.fort.ll.exe; cabal run fort -- examples/colorize.fort; ./examples/colorize.fort.ll.exe examples/colorize.fort"
# cmd="cabal run fort -- --main-is=test --run $1"
# cmd="cabal test"
# cmd="cabal build"
eval $cmd

watchcmd="fswatch -or --exclude=\".*\" --include=\"\\.hs$\" --include=\"\\.fort$\" . | (while read; do $cmd; done)"

eval $watchcmd

