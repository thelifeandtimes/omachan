#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
package="$root/.dev/plugin-package"
mkdir -p "$package/plugin"
cp "$root/application-connection.json" "$root/manifest.json" "$root/LICENSE" "$package/"
mkdir -p "$package/licenses"
cp "$root/licenses/omart-MIT.txt" "$package/licenses/"
mkdir -p "$package/plugin/app_connection"
cp "$root/plugin/app_connection/"*.py "$package/plugin/app_connection/"
cp "$root/plugin/receive_connection.py" "$root/plugin/Omachan.qml" "$root/plugin/bridge.py" "$package/plugin/"
omarchy plugin validate "$package"
qmllint "$package/plugin/Omachan.qml"
echo "$package"
