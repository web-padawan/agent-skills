#!/usr/bin/env bash
# smoke.sh — exercise the scripts that rewrite a working tree, inside a throwaway repository.
#
# Usage:
#   smoke.sh
#
# Builds a git repository under ${TMPDIR:-/tmp}/smoke-<time> with a main branch and a feature
# branch of three commits. Then runs ab.sh, fixup-into.sh and float-to-tip.sh against it and
# checks their exit codes and their effect on the tree. Runs dev-server.sh and `ab.sh --port`
# against a fake web-dev-server (a python3 http.server) and checks that they return through a
# pipe, restore on SIGTERM, and leave no shell behind. Also checks that every script in this
# directory answers --help with exit 0.
#
# Exit codes: 0 all checks passed · 1 a check failed.
set -uo pipefail

SCRIPTS=$(cd "$(dirname "$0")" && pwd)
WORK="${TMPDIR:-/tmp}/smoke-$(date +%Y%m%d-%H%M%S)"
WORK="${WORK//\/\//\/}"
FAILED=0

check() {
  # $1 description, $2 expected exit code, then the command
  local desc="$1" want="$2" got
  shift 2
  "$@" > "$WORK/last.log" 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "ok    $desc"
  else
    echo "FAIL  $desc (exit $got, want $want)"
    sed 's/^/      | /' "$WORK/last.log" | tail -12
    FAILED=$((FAILED + 1))
  fi
}

expect() {
  # $1 description, $2 expected text, $3 actual text
  if [ "$2" = "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1 (got '$3', want '$2')"
    FAILED=$((FAILED + 1))
  fi
}

bounded() {
  # $1 seconds, then the command. Exit 124 when the command still runs after that time.
  local secs="$1" pid i
  shift
  "$@" & pid=$!
  for ((i = 0; i < secs * 4; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid"
}

mkdir -p "$WORK"
echo "work: $WORK"

echo "== help"
for f in "$SCRIPTS"/*.sh; do
  case "$(basename "$f")" in smoke.sh) continue ;; esac
  check "$(basename "$f") --help" 0 "$f" --help
done
for f in "$SCRIPTS"/probe.cjs "$SCRIPTS"/probe-compare.cjs "$SCRIPTS"/visual-diffstat.cjs; do
  check "$(basename "$f") --help" 0 node "$f" --help
done

echo "== repository"
REPO="$WORK/repo"
git init -q -b main "$REPO"
cd "$REPO" || exit 1
git config user.email smoke@example.com
git config user.name smoke
git config commit.gpgsign false
git config rebase.autosquash true
printf 'one\n' > a.txt
git add a.txt && git commit -q -m "base"
git checkout -q -b feature
printf 'one\ntwo\n' > a.txt && git commit -qam "add two"
printf 'x\n' > b.txt && git add b.txt && git commit -q -m "add b"
printf 'one\ntwo\nthree\n' > a.txt && git commit -qam "add three"
TREE=$(git rev-parse 'HEAD^{tree}')

echo "== ab.sh"
check "ab.sh differs when the ref changes the output" 1 \
  "$SCRIPTS/ab.sh" --ref main --path a.txt -- cat a.txt
expect "ab.sh restored the path" "" "$(git status --porcelain)"
check "ab.sh identical when the command ignores the path" 0 \
  "$SCRIPTS/ab.sh" --ref main --path a.txt -- cat b.txt
check "ab.sh refuses an unknown ref" 2 \
  "$SCRIPTS/ab.sh" --ref nope --path a.txt -- cat a.txt
printf 'dirty\n' >> a.txt
check "ab.sh refuses a dirty path" 2 \
  "$SCRIPTS/ab.sh" --ref main --path a.txt -- cat a.txt
git checkout -q -- a.txt

echo "== dev-server.sh"
if command -v python3 >/dev/null; then
  # A fake web-dev-server: ps must show that name, so it is a python script, not a wrapper.
  mkdir -p node_modules/.bin dev
  cat > node_modules/.bin/web-dev-server <<'FAKE'
#!/usr/bin/env python3
import http.server, sys
port = int(sys.argv[sys.argv.index('--port') + 1])
http.server.ThreadingHTTPServer.allow_reuse_address = True
http.server.ThreadingHTTPServer(('', port), http.server.SimpleHTTPRequestHandler).serve_forever()
FAKE
  chmod +x node_modules/.bin/web-dev-server
  printf 'smoke\n' > dev/index.html
  printf 'node_modules/\ndev/\n' > .git/info/exclude
  PORT=8791
  while [ -n "$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null)" ]; do PORT=$((PORT + 1)); done
  check "dev-server.sh ensure returns through a pipe" 0 \
    bounded 30 bash -c "\"$SCRIPTS/dev-server.sh\" ensure --port $PORT --check a.txt | cat"
  expect "dev-server.sh left no shell behind" "" "$(pgrep -f "dev-server.sh ensure --port $PORT")"
  check "dev-server.sh restart returns through a pipe" 0 \
    bounded 30 bash -c "\"$SCRIPTS/dev-server.sh\" restart --port $PORT --check a.txt | cat"
  check "ab.sh --port restarts the server and differs" 1 \
    bounded 60 "$SCRIPTS/ab.sh" --ref main --path a.txt --port "$PORT" -- curl -s "localhost:$PORT/a.txt"
  expect "ab.sh --port restored the path" "" "$(git status --porcelain)"
  "$SCRIPTS/ab.sh" --ref main --path a.txt --port "$PORT" -- sleep 60 > "$WORK/interrupt.log" 2>&1 & AB=$!
  for _ in $(seq 1 120); do grep -q '^== A:' "$WORK/interrupt.log" 2>/dev/null && break; sleep 0.25; done
  kill "$AB" 2>/dev/null
  wait "$AB"
  expect "ab.sh --port exits 130 on SIGTERM during A" 130 "$?"
  expect "ab.sh --port restored the path on SIGTERM" "" "$(git status --porcelain)"
  check "dev-server.sh stop" 0 "$SCRIPTS/dev-server.sh" stop --port "$PORT"
  expect "dev-server.sh stop freed the port" "" "$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null)"
else
  echo "skip  dev-server.sh checks, python3 not found"
fi

echo "== fixup-into.sh"
printf 'x\ny\n' > b.txt
check "fixup-into.sh folds a path into an earlier commit" 0 \
  "$SCRIPTS/fixup-into.sh" --grep "add b" b.txt
expect "fixup-into.sh kept three commits" "3" "$(git rev-list --count main..HEAD)"
expect "fixup-into.sh put y into the add b commit" "x
y" "$(git show "$(git log --format=%H --grep='add b' main..HEAD)":b.txt)"
expect "fixup-into.sh left no fixup commit" "0" "$(git log --format=%s main..HEAD | grep -c '^fixup!')"
check "fixup-into.sh refuses a commit on main" 2 \
  "$SCRIPTS/fixup-into.sh" main --staged
check "fixup-into.sh refuses when nothing is staged" 2 \
  "$SCRIPTS/fixup-into.sh" --grep "add b" --staged
printf 'one\nTWO\n' > a.txt
check "fixup-into.sh aborts on a conflict" 1 \
  "$SCRIPTS/fixup-into.sh" --grep "add two" a.txt
expect "fixup-into.sh kept the fixup on the tip" "fixup! add two" "$(git log -1 --format=%s)"
git reset -q --hard HEAD~1

echo "== float-to-tip.sh"
TREE=$(git rev-parse 'HEAD^{tree}')
check "float-to-tip.sh moves a commit to the tip" 0 \
  "$SCRIPTS/float-to-tip.sh" --grep "add b"
expect "float-to-tip.sh tip is add b" "add b" "$(git log -1 --format=%s)"
expect "float-to-tip.sh tree unchanged" "$TREE" "$(git rev-parse 'HEAD^{tree}')"
check "float-to-tip.sh reports nothing to do on the tip" 0 \
  "$SCRIPTS/float-to-tip.sh" --grep "add b"
check "float-to-tip.sh aborts on a conflict" 1 \
  "$SCRIPTS/float-to-tip.sh" --grep "add two"
expect "float-to-tip.sh branch unchanged after abort" "add b" "$(git log -1 --format=%s)"
printf 'dirty\n' >> a.txt
check "float-to-tip.sh refuses a dirty tree" 2 \
  "$SCRIPTS/float-to-tip.sh" --grep "add three"
git checkout -q -- a.txt

if [ "$FAILED" = 0 ]; then
  echo "RESULT: ok"
  rm -rf "$WORK"
  exit 0
fi
echo "RESULT: FAIL ($FAILED check(s) failed), files kept in $WORK"
exit 1
