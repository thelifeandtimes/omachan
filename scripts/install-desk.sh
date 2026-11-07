#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in fex|wes|sev) ;; *) echo 'Choose fex, wes, or sev' >&2; exit 1;; esac
pier="$HOME/temp-ur/fakeships/fake-$1"
[ -d "$pier/omachan" ] && [ -d "$pier/base" ]
cp -R "$root/desk/." "$pier/omachan/"
# Development piers use a fake-only release configuration. Never point them at
# the live distribution/hub identities from the production desk source.
cat > "$pier/omachan/lib/omachan-config.hoon" <<'HOON'
|%
++  distributor  ~fex
++  hub          ~fex
--
HOON
