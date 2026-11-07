#!/bin/bash
# A separate bar and popup for development; never edits shell configuration.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
preview="$root/.dev/plugin-preview"
shell_source="${OMACHAN_SHELL_SOURCE:-/usr/share/omarchy/shell}"
[ -f "$shell_source/Commons/qmldir" ] || { echo 'Omarchy shell modules not found' >&2; exit 1; }
mkdir -p "$preview"
ln -sfn "$shell_source/Commons" "$preview/Commons"
ln -sfn "$shell_source/Ui" "$preview/Ui"
ln -sfn "$root/plugin" "$preview/Omachan"
cp "$root/tests/preview.qml" "$preview/shell.qml"
exec quickshell -p "$preview"
