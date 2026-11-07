#!/bin/bash
set -euo pipefail
SESSION=omachan-dev
PIERS="$HOME/temp-ur/fakeships"
case "${1:-status}" in
  start|start-onboarding)
    mkdir -p "$PIERS"
    specs="fex:8101 wes:8102 sev:8103"
    [ ! -d "$PIERS/fake-let/.urb" ] || specs="$specs let:8104"
    [ "$1" != start-onboarding ] || specs="let:8104"
    for spec in $specs; do
      ship=${spec%:*}; port=${spec#*:}; pier="$PIERS/fake-$ship"
      if tmux list-panes -t "$SESSION:$ship" >/dev/null 2>&1; then continue; fi
      if [ -d "$pier/.urb" ]; then
        command="urbit '$pier' -b 127.0.0.1 --http-port $port --snap-time 60 --no-dock"
      else
        [ ! -e "$pier" ] || { echo "Refusing to overwrite $pier" >&2; exit 1; }
        command="urbit -F $ship -c '$pier' -b 127.0.0.1 --http-port $port --snap-time 60 --no-dock"
      fi
      if tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux new-window -d -t "$SESSION" -n "$ship" -c "$PIERS" "$command"
      else
        tmux new-session -d -s "$SESSION" -n "$ship" -c "$PIERS" "$command"
      fi
    done
    ;;
  status) tmux list-panes -s -t "$SESSION" -F '#{window_name}: #{pane_current_command} (#{pane_current_path})' ;;
  dojo)
    case "${2:-}" in fex|wes|sev|let) ;; *) exit 1 ;; esac
    [ "$#" -eq 3 ]
    tmux send-keys -t "$SESSION:$2" -l "$3"
    tmux send-keys -t "$SESSION:$2" Enter
    ;;
  *) echo 'Usage: fakenet.sh start|start-onboarding|status|dojo SHIP COMMAND' >&2; exit 1 ;;
esac
