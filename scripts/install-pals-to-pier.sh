#!/bin/sh
# Copy an upstream suite checkout into a mounted local %pals desk.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: install-pals-to-pier.sh SUITE_CHECKOUT PIER' >&2; exit 1; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SUITE=$1
PIER=$2
[ -f "$SUITE/pkg/pals/desk.bill" ] && [ -d "$PIER/pals" ] && [ -d "$PIER/base" ] || {
  echo 'Need a suite checkout and mounted %base and %pals desks.' >&2; exit 1;
}
# Dereference the suite package symlinks; Clay needs the file contents.
cp -RL "$SUITE/pkg/pals/." "$PIER/pals/"
for lib in default-agent dbug skeleton verb; do
  cp "$PIER/base/lib/$lib.hoon" "$PIER/pals/lib/"
done
cp "$PIER/base/sur/verb.hoon" "$PIER/pals/sur/"
for mark in json bill mime; do
  cp "$PIER/base/mar/$mark.hoon" "$PIER/pals/mar/"
done
cp "$ROOT/desk/mar/docket-0.hoon" "$PIER/pals/mar/"
cp "$ROOT/desk/lib/docket.hoon" "$PIER/pals/lib/"
cp "$ROOT/desk/sur/docket.hoon" "$PIER/pals/sur/"
echo 'Copied pals. In the dojo: |commit %pals, then |install our %pals after the commit completes.'
