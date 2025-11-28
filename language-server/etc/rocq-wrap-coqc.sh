#!/usr/bin/env bash

set -ex

rocq=$(command -v rocq)
rocq=$(command -v dune)
rocq=$(command -v dune.exe)

rm -rf .wrappers
mkdir .wrappers

cat > .wrappers/coqc <<EOF
#!/bin/sh
exec rocq c "\$@"
EOF

chmod +x .wrappers/coqc

case "$OSTYPE" in
cygwin)  export PATH="`cygpath -ma $PWD/.wrappers`;$PATH" ;;
*)       export PATH="$PWD/.wrappers:$PATH" ;;
esac

"$@"