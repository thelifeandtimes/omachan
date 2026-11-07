#!/bin/bash
# Install only the validated local Omachan package; preserve the user's bar.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
bash "$root/scripts/package-plugin.sh"
python3 - "$root" <<'PY'
import datetime
import json
from pathlib import Path
import shutil
import sys
root = Path(sys.argv[1])
config = Path.home() / '.config/omarchy'
target = config / 'plugins/urbit.omachan'
backup = config / 'plugin-backups' / ('omachan-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
if target.is_symlink() or (target / '.git').exists():
    raise SystemExit('Refusing to overwrite a symlink or Git-managed Omachan installation.')
if target.exists():
    manifest = json.loads((target / 'manifest.json').read_text())
    if manifest.get('id') != 'urbit.omachan':
        raise SystemExit('The destination contains another plugin; left unchanged.')
backup.mkdir(parents=True)
if (config / 'shell.json').exists(): shutil.copy2(config / 'shell.json', backup / 'shell.json')
if target.exists(): shutil.copytree(target, backup / 'urbit.omachan')
shutil.copytree(root / '.dev/plugin-package', target, dirs_exist_ok=True)
print('Backup: ' + str(backup))
PY
omarchy-shell shell rescanPlugins
# Registry discovery runs asynchronously after the rescan IPC returns.
python3 - <<'PYWAIT'
import json
import subprocess
import time
for _ in range(40):
    result = subprocess.run(['omarchy-shell','shell','listPlugins'], capture_output=True, text=True, check=True)
    if any(p.get('id') == 'urbit.omachan' for p in json.loads(result.stdout)): break
    time.sleep(.25)
else: raise SystemExit('Omachan was copied but the shell did not discover it; inspect shell logs.')
PYWAIT
omarchy plugin enable urbit.omachan --section right
