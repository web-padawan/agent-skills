#!/usr/bin/env bash
# dev-server.sh — manage the web-dev-server that browser probes and dev pages use.
#
# Usage:
#   dev-server.sh ensure  [--port N] [--path /dev/x.html] [--theme lumo|aura] [--check <repo-file>] [--timeout S]
#   dev-server.sh restart [same flags]
#   dev-server.sh status  [--port N] [--path /dev/x.html] [--check <repo-file>]
#   dev-server.sh stop    [--port N]
#
# ensure   starts the server when nothing answers on the port, else keeps it. With --check
#          it restarts a server that serves a stale copy of that file.
# restart  stops the listener on the port, then starts a fresh server.
# status   prints the pid, the HTTP code of --path, and the served state of --check.
# stop     kills the web-dev-server that listens on the port. Refuses to kill anything else.
#
# --check compares the served module with the file on disk, after both lose their import
# lines, because --node-resolve rewrites bare imports. `served: stale` means that a
# `git checkout <ref> -- <path>` replaced the file and the server did not notice.
#
# Defaults: port 8765 (so `yarn start` on 8000 is untouched), path /dev/, timeout 30.
# The log is ${TMPDIR:-/tmp}/dev-server-<port>.log. The server binary comes from
# <repo>/node_modules/.bin/web-dev-server, so run this inside the repository.
#
# Exit codes: 0 ok · 1 usage or environment error · 2 the server did not come up.
set -euo pipefail

CMD="${1:-}"
[ -n "$CMD" ] || { sed -n '2,24p' "$0"; exit 1; }
shift
PORT=8765
PAGE=/dev/
THEME=""
CHECK=""
TIMEOUT=30

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:?--port requires a value}"; shift ;;
    --path) PAGE="${2:?--path requires a value}"; shift ;;
    --theme) THEME="${2:?--theme requires a value}"; shift ;;
    --check) CHECK="${2:?--check requires a value}"; shift ;;
    --timeout) TIMEOUT="${2:?--timeout requires a value}"; shift ;;
    --help|-h) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not inside a git repository" >&2; exit 1; }
BIN="$ROOT/node_modules/.bin/web-dev-server"
LOG="${TMPDIR:-/tmp}/dev-server-$PORT.log"
LOG="${LOG//\/\//\/}"
BASE_URL="http://localhost:$PORT"

listener_pids() {
  lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null || true
}

is_wds() {
  ps -o command= -p "$1" 2>/dev/null | grep -q "web-dev-server"
}

http_code() {
  local code
  code=$(curl -s -o /dev/null --max-time 3 -w '%{http_code}' "$BASE_URL$1" 2>/dev/null || true)
  echo "${code:-000}"
}

strip_imports() {
  grep -vE "^\s*(import\b|export\b.*\bfrom\b)|import\(" || true
}

served_state() {
  # same | stale | missing | unreadable
  local file="$1" url served disk
  [ -f "$ROOT/$file" ] || { echo unreadable; return; }
  url="$BASE_URL/${file#/}"
  served=$(curl -s --max-time 5 "$url" 2>/dev/null | strip_imports | shasum | cut -c1-40)
  [ -n "$served" ] || { echo missing; return; }
  disk=$(strip_imports < "$ROOT/$file" | shasum | cut -c1-40)
  if [ "$served" = "$disk" ]; then echo same; else echo stale; fi
}

do_stop() {
  local pids pid killed=0
  pids=$(listener_pids)
  for pid in $pids; do
    if is_wds "$pid"; then
      kill "$pid" 2>/dev/null || true
      killed=1
    else
      echo "refuse: pid $pid on port $PORT is not web-dev-server: $(ps -o command= -p "$pid")" >&2
      exit 1
    fi
  done
  if [ "$killed" = 1 ]; then
    for _ in $(seq 1 20); do
      [ -z "$(listener_pids)" ] && break
      sleep 0.25
    done
    echo "stopped: port $PORT"
  else
    echo "stopped: nothing listened on port $PORT"
  fi
}

do_start() {
  [ -x "$BIN" ] || { echo "error: $BIN not found, run yarn install" >&2; exit 1; }
  local args=(--node-resolve --port "$PORT")
  [ -n "$THEME" ] && args+=("--theme=$THEME")
  (cd "$ROOT" && nohup "$BIN" "${args[@]}" < /dev/null > "$LOG" 2>&1 & disown) 2>/dev/null
  local waited=0 code
  while :; do
    code=$(http_code "$PAGE")
    [ "$code" = 200 ] && break
    if [ "$waited" -ge "$TIMEOUT" ]; then
      echo "error: no 200 from $BASE_URL$PAGE after ${TIMEOUT}s (last code $code)" >&2
      echo "log: $LOG" >&2
      tail -5 "$LOG" >&2 || true
      exit 2
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  echo "started: pid $(listener_pids | head -1) url $BASE_URL$PAGE theme ${THEME:-default} log $LOG"
}

do_status() {
  local pids code
  pids=$(listener_pids | tr '\n' ' ')
  code=$(http_code "$PAGE")
  echo "port: $PORT"
  echo "pid: ${pids:-none}"
  echo "http: $code $BASE_URL$PAGE"
  if [ -n "$CHECK" ]; then
    echo "served: $(served_state "$CHECK") $CHECK"
  fi
  [ "$code" = 200 ]
}

case "$CMD" in
  stop) do_stop ;;
  status) do_status ;;
  restart) do_stop; do_start; [ -n "$CHECK" ] && echo "served: $(served_state "$CHECK") $CHECK"; true ;;
  ensure)
    if [ "$(http_code "$PAGE")" = 200 ]; then
      if [ -n "$CHECK" ] && [ "$(served_state "$CHECK")" = stale ]; then
        echo "stale: $CHECK differs from disk, restarting"
        do_stop
        do_start
      else
        echo "running: pid $(listener_pids | head -1) url $BASE_URL$PAGE"
      fi
    else
      do_start
    fi
    [ -n "$CHECK" ] && echo "served: $(served_state "$CHECK") $CHECK"
    true
    ;;
  *) echo "unknown command: $CMD" >&2; sed -n '2,24p' "$0"; exit 1 ;;
esac
