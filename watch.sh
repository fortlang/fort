cmd="cabal run fort -- --run $1"
# cmd="cabal test"
cmd="cabal build"
eval $cmd

watchcmd="fswatch -or --exclude=\".*\" --include=\"\\.hs$\" --include=\"\\.fort$\" . | (while read; do $cmd; done)"

eval $watchcmd

