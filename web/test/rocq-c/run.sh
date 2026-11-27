#!/bin/sh
# Compile the .v files of this directory with rocq c compiled to wasm
# (rocq-web), under node, and check their output (the "expect:" comments).
# A file is skipped when the library of its "requires:" comment is not
# installed in the switch. Usage: run.sh [file.v ...]
set -u
here=$(cd "$(dirname "$0")" && pwd)
rocq_c="${ROCQ_C:-$OPAM_SWITCH_PREFIX/lib/rocq-web/rocq_c.bc.wasm.js}"
coqlib=$(rocq c -where)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
[ $# -gt 0 ] || set -- "$here"/*.v
fail=0
for f in "$@"; do
  name=$(basename "$f")
  req=$(sed -n 's/^(\* requires: \(.*\) \*)$/\1/p' "$f")
  if [ -n "$req" ] && [ ! -d "$coqlib/user-contrib/$req" ]; then
    echo "SKIP $name ($req is not installed)"; continue
  fi
  cp "$f" "$tmp/$name"
  start=$(date +%s)
  if ! (cd "$tmp" && node "$rocq_c" -bytecode-compiler no -coqlib "$coqlib" "$name") \
       > "$tmp/$name.out" 2>&1; then
    echo "FAIL $name: rocq c failed"; sed 's/^/  /' "$tmp/$name.out"; fail=1; continue
  fi
  ok=1
  sed -n 's/^(\* expect: \(.*\) \*)$/\1/p' "$f" > "$tmp/$name.expect"
  while IFS= read -r e; do
    grep -qF -- "$e" "$tmp/$name.out" || { echo "FAIL $name: no \"$e\" in the output"; ok=0; }
  done < "$tmp/$name.expect"
  if [ $ok = 1 ]; then echo "OK   $name ($(( $(date +%s) - start ))s)"
  else sed 's/^/  /' "$tmp/$name.out"; fail=1; fi
done
exit $fail
