#!/bin/bash
# Exercise a local fake in a separate Quickshell instance.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
preview="$root/.dev/plugin-check"
shell_source="${OMACHAN_SHELL_SOURCE:-/usr/share/omarchy/shell}"
mkdir -p "$preview"
ln -sfn "$shell_source/Commons" "$preview/Commons"
ln -sfn "$shell_source/Ui" "$preview/Ui"
ln -sfn "$root/plugin" "$preview/Omachan"
case "${1:-feed}" in
  feed) harness=plugin-smoke.qml ;;
  onboarding) harness=plugin-onboarding.qml ;;
  *) echo "Usage: check-plugin.sh [feed|onboarding] [wes|fex]" >&2; exit 1 ;;
esac
ship="${2:-wes}"
case "$ship" in wes|fex) ;; *) echo "Choose the local wes or fex fake." >&2; exit 1 ;; esac
cp "$root/tests/$harness" "$preview/shell.qml"
OMACHAN_SOURCE="$root" OMACHAN_TEST_SHIP="$ship" quickshell -p "$preview"
