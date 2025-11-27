#!/usr/bin/env bash

set -ex

rocq=$(command -v rocq)

rm -rf .wrappers
mkdir .wrappers

cat > .wrappers/coqc <<EOF
#!/bin/sh
exec rocq c "\$@"
EOF

chmod +x .wrappers/coqc

export PATH="$PWD/.wrappers;:$PWD/.wrappers:$PATH"

"$@"