if [ -z $1 ]
then
cmd="rm -f fort.tix; cabal test";
else
cmd="rm -f fort.tix; cabal run fort -- --run $1 --show-llvm";
fi

eval $cmd

watchcmd="fswatch -or --exclude=\".*\" --include=\"\\.c$\" --include=\"\\.h$\" --include=\"\\.hs$\" --include=\"\\.fort$\" . | (while read; do $cmd; done)"

eval $watchcmd

