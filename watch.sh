cmd="cabal run fort -- --run $1"

eval $cmd

watchcmd="fswatch -or --exclude=\".*\" --include=\"\\.c$\" --include=\"\\.h$\" --include=\"\\.hs$\" --include=\"\\.fort$\" . | (while read; do $cmd; done)"

eval $watchcmd

