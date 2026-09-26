#!/usr/bin/env bash
# test-summary.sh — run Web Test Runner suites and print one line per suite.
#
# Usage:
#   test-summary.sh --group <pkg> [--group <pkg>]... [--glob <pattern>]
#                   [--suites unit,firefox,webkit,snapshots,it,lumo,aura,base | --browsers | --all]
#                   [--cmd '<command>']... [--log-dir <dir>] [--quiet]
#
# Suites map to the yarn scripts of vaadin/web-components:
#   unit → yarn test · firefox → yarn test:firefox · webkit → yarn test:webkit
#   snapshots → yarn test:snapshots · it → yarn test:it --glob='*<group>*'
#   lumo | aura | base → yarn test:<theme> (docker visual tests)
# --browsers is unit,firefox,webkit. --all is unit,firefox,webkit,snapshots,it. Default is unit.
# --glob narrows the unit, browser and snapshot suites to test files that match.
# --cmd runs any other command through the same parser, for example a flow-components run.
#
# Each run writes its full log to <log-dir>/<label>.log. The default log dir is
# ${TMPDIR:-/tmp}/test-summary-<time>. The summary line per suite is
#   <label>  <N passed, M failed[, K skipped]>  <ok|FAIL|error>  <log path>
# followed by one indented line per failing test. `none` means that the package has no test
# files for that suite. `error` means that the run ended without a summary line, for example
# a config or import error. The last 8 log lines follow it.
#
# Exit codes: 0 all suites passed · 1 a suite failed or errored · 2 usage error.
set -uo pipefail

GROUPS_=()
GLOB=""
SUITES="unit"
CMDS=()
LOG_DIR=""
QUIET=false

while [ $# -gt 0 ]; do
  case "$1" in
    --group) GROUPS_+=("${2:?--group requires a value}"); shift ;;
    --glob) GLOB="${2:?--glob requires a value}"; shift ;;
    --suites) SUITES="${2:?--suites requires a value}"; shift ;;
    --browsers) SUITES="unit,firefox,webkit" ;;
    --all) SUITES="unit,firefox,webkit,snapshots,it" ;;
    --cmd) CMDS+=("${2:?--cmd requires a value}"); shift ;;
    --log-dir) LOG_DIR="${2:?--log-dir requires a value}"; shift ;;
    --quiet) QUIET=true ;;
    --help|-h) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ${#GROUPS_[@]} -eq 0 ] && [ ${#CMDS[@]} -eq 0 ]; then
  echo "error: pass --group <pkg> or --cmd '<command>'" >&2
  exit 2
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$PWD
cd "$ROOT"
[ -n "$LOG_DIR" ] || LOG_DIR="${TMPDIR:-/tmp}/test-summary-$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${LOG_DIR//\/\//\/}"
mkdir -p "$LOG_DIR"

suite_cmd() {
  # $1 suite, $2 group → command string
  local g="$2" glob=""
  [ -n "$GLOB" ] && glob=" --glob='$GLOB'"
  case "$1" in
    unit) echo "yarn test --group $g$glob" ;;
    firefox) echo "yarn test:firefox --group $g$glob" ;;
    webkit) echo "yarn test:webkit --group $g$glob" ;;
    snapshots) echo "yarn test:snapshots --group $g$glob" ;;
    it) echo "yarn test:it --glob='*$g*'" ;;
    lumo|aura|base) echo "yarn test:$1 --group $g$glob" ;;
    *) echo "error: unknown suite $1" >&2; exit 2 ;;
  esac
}

FAILED=0
RUNS=()

run_one() {
  # $1 label, $2 command
  local label="$1" cmd="$2" log="$LOG_DIR/$1.log" code summary status fails
  [ "$QUIET" = true ] || echo "running: $cmd" >&2
  bash -c "$cmd" 2>&1 | tr '\r' '\n' > "$log"
  code=${PIPESTATUS[0]}
  # The last progress line holds the final counts.
  summary=$(grep -aE 'test files \|' "$log" | tail -1 | sed -E 's/.*test files \| *//')
  fails=$(grep -aE '^\s*❌ ' "$log" | sed -E 's/^[[:space:]]*❌ //' | sort -u)
  if grep -qa 'Could not find any group named' "$log"; then
    status=none
    summary="no test files for this suite"
  elif [ -z "$summary" ]; then
    status=error
    summary="no summary line (exit $code)"
  elif [ "$code" = 0 ] && [ -z "$fails" ] && ! echo "$summary" | grep -qE '[1-9][0-9]* failed'; then
    status=ok
  else
    status=FAIL
  fi
  case "$status" in ok|none) ;; *) FAILED=$((FAILED + 1)) ;; esac
  printf '%-22s %-36s %-5s %s\n' "$label" "$summary" "$status" "$log"
  if [ -n "$fails" ]; then
    printf '%s\n' "$fails" | sed 's/^/    ❌ /'
  fi
  if [ "$status" = error ]; then
    tail -8 "$log" | sed 's/^/    | /'
  fi
}

IFS=',' read -ra SUITE_LIST <<< "$SUITES"
for g in ${GROUPS_[@]+"${GROUPS_[@]}"}; do
  for s in "${SUITE_LIST[@]}"; do
    run_one "$s-$g" "$(suite_cmd "$s" "$g")"
  done
done
i=0
for c in ${CMDS[@]+"${CMDS[@]}"}; do
  i=$((i + 1))
  run_one "cmd$i" "$c"
done

if [ "$FAILED" = 0 ]; then
  echo "RESULT: ok"
  exit 0
fi
echo "RESULT: FAIL ($FAILED suite(s) failed)"
exit 1
