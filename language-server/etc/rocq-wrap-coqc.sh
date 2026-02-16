#!/bin/bash

set -ex

rocq=$(command -v rocq)

rm -rf .wrappers
mkdir .wrappers

cat > .wrappers/coqc <<EOF
#!/bin/sh
exec rocq c "\$@"
EOF

chmod +x .wrappers/coqc

case "$OSTYPE" in
cygwin) 
    dune=$(command -v dune)
    dunep=${dune%%dune}
    export PATH="`cygpath -ma $PWD/.wrappers`;`cygpath -ma $dunep`;$PATH" 
    shift
    $dune "$@"
    ;;
*)  
    export PATH="$PWD/.wrappers:$PATH" 
    "$@"
    ;;
esac
