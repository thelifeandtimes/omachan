#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
bash scripts/install-desk.sh "${1:-fex}"
bash scripts/fakenet.sh dojo "${1:-fex}" '|commit %omachan'
