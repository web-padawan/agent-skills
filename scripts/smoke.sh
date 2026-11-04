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
# pipe, restore on SIGTERM, and leave no shell behind. Checks the review-plan.sh report dir
# and earlier-findings list, the post-review.sh --head refusal, the pr-intake.sh facts on a
# fixture, and the bash-guard.py decisions. Also checks that every
# script in this directory answers --help with exit 0.
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
# Two side branches: d/b.txt exists only in ab-ref, d/c.txt exists only in ab-files.
git checkout -q -b ab-ref
mkdir d && printf 'a\n' > d/a.txt && printf 'b\n' > d/b.txt && git add d && git commit -q -m "add d"
git checkout -q -b ab-files
git rm -q d/b.txt && printf 'c\n' > d/c.txt && git add d/c.txt && git commit -q -m "replace d/b with d/c"
check "ab.sh swaps the files that only one side has" 1 \
  "$SCRIPTS/ab.sh" --ref ab-ref --path d --out-dir "$WORK/ab-files" -- ls d
expect "ab.sh side A has only the ref files" "a.txt b.txt" "$(tr '\n' ' ' < "$WORK/ab-files/A.log" | sed 's/ $//')"
expect "ab.sh side B has only the HEAD files" "a.txt c.txt" "$(tr '\n' ' ' < "$WORK/ab-files/B.log" | sed 's/ $//')"
expect "ab.sh restored the added and deleted files" "" "$(git status --porcelain)"
printf 'mine\n' > d/b.txt
check "ab.sh refuses an untracked file that only the ref has" 2 \
  "$SCRIPTS/ab.sh" --ref ab-ref --path d -- ls d
grep -q "untracked d/b.txt" "$WORK/last.log"
expect "ab.sh names the untracked file" 0 "$?"
expect "ab.sh kept the untracked file" "mine" "$(cat d/b.txt)"
rm d/b.txt
git checkout -q feature && git branch -q -D ab-files ab-ref

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

echo "== review-plan.sh"
printf '.omc/\n' >> .git/info/exclude
git remote add origin "$REPO" && git fetch -q origin main
expect "review-plan.sh keeps an ignored report dir that does not exist yet" \
  "report_dir: .omc/self-review" \
  "$("$SCRIPTS/review-plan.sh" --mode self --no-context --no-write 2>/dev/null | grep '^report_dir:')"
mkdir -p .omc/self-review
jq -n --arg head "$(git rev-parse HEAD)" '{branch: "feature", head: $head, round: 1, findings: [
  {id: "F1", round: 1, category: "logic", tier: "B", status: "open", file: "a.txt", line: 2,
   claim: "kept claim", merged: [{file: "a.txt", line: 3, claim: "merged claim"}]}]}' \
  > .omc/self-review/feature-findings.json
"$SCRIPTS/review-plan.sh" --mode self --no-context > "$WORK/plan.log" 2>&1
expect "review-plan.sh lists a merged finding with the finding that kept it" \
  "- F1 | open | logic | a.txt:2 | B | kept claim Merged: a.txt:3 merged claim" \
  "$(grep '^- F1 ' .omc/self-review/context.md 2>/dev/null)"

echo "== post-review.sh"
printf '{"findings": []}\n' > "$WORK/post.json"
check "post-review.sh refuses a run without --head" 2 \
  "$SCRIPTS/post-review.sh" --findings "$WORK/post.json" --dry-run

echo "== pr-intake.sh"
# Three packages import the changed module, and a unit test asserts CSS. The fixture
# issue got `Impact: Low` before the review and `behavior altering change` after it.
INTAKE_REPO="$WORK/intake"
git init -q -b main "$INTAKE_REPO"
(
  cd "$INTAKE_REPO" || exit 1
  git config user.email smoke@example.com; git config user.name smoke; git config commit.gpgsign false
  mkdir -p packages/core/src packages/a/src packages/b/src packages/c/src packages/core/test
  printf 'export const M = 1;\n' > packages/core/src/vaadin-core-mixin.js
  printf ':host { color: red; }\n' > packages/core/src/vaadin-core-styles.css
  for p in a b c; do
    printf "import { M } from '@vaadin/core/src/vaadin-core-mixin.js';\n" > "packages/$p/src/vaadin-$p.js"
  done
  git add . && git commit -q -m base
  printf 'export const M = 2;\n' > packages/core/src/vaadin-core-mixin.js
  printf ':host { color: blue; }\n' > packages/core/src/vaadin-core-styles.css
  printf "it('x', () => {\n  expect(getComputedStyle(el).color).to.equal('blue');\n});\n" > packages/core/test/core.test.js
  git add . && git commit -q -m change
)
cat > "$WORK/intake-meta.json" <<'EOF'
{"slug": "owner/name", "data": {"repository": {"pullRequest": {
  "title": "fix: change the core mixin", "isCrossRepository": true, "author": {"login": "someone"},
  "closingIssuesReferences": {"nodes": [{
    "number": 7, "state": "OPEN", "createdAt": "2026-01-01T00:00:00Z", "author": {"login": "platosha"},
    "body": "The core mixin is wrong.",
    "labels": {"nodes": [{"name": "bug"}, {"name": "Impact: Low"}, {"name": "behavior altering change"}]},
    "comments": {"nodes": []},
    "timelineItems": {"nodes": [
      {"__typename": "LabeledEvent", "createdAt": "2026-01-01T00:00:01Z", "label": {"name": "bug"}},
      {"__typename": "LabeledEvent", "createdAt": "2026-01-02T00:00:00Z", "label": {"name": "Impact: Low"}},
      {"__typename": "LabeledEvent", "createdAt": "2026-03-01T00:00:00Z", "label": {"name": "behavior altering change"}}
    ]}}]}}}}}
EOF
INTAKE_BASE=$(git -C "$INTAKE_REPO" rev-parse HEAD~1)
INTAKE_HEAD=$(git -C "$INTAKE_REPO" rev-parse HEAD)
(cd "$INTAKE_REPO" && "$SCRIPTS/pr-intake.sh" --pr 1 --base "$INTAKE_BASE" --head "$INTAKE_HEAD" \
  --meta "$WORK/intake-meta.json" --as-of 2026-02-01T00:00:00Z --flow-dir "$WORK/none") > "$WORK/intake.log" 2>&1
expect "pr-intake.sh counts three importing packages" \
  "reach: packages/core/src/vaadin-core-mixin.js -> 3 other packages [a b c]" \
  "$(grep '^reach: packages/core/src/vaadin-core-mixin.js' "$WORK/intake.log")"
expect "pr-intake.sh replays the labels to --as-of" \
  "issue_flags: low-impact" "$(grep '^issue_flags:' "$WORK/intake.log")"
expect "pr-intake.sh counts a former employee as team" \
  "issue: #7 open labels=[Impact: Low, bug] author=team age=31d comments=0" "$(grep '^issue:' "$WORK/intake.log")"
expect "pr-intake.sh flags CSS that a unit test asserts" \
  "css_unit_assertions: packages/core/test/core.test.js:2" "$(grep '^css_unit_assertions:' "$WORK/intake.log")"
expect "pr-intake.sh proposes a decision for a low-impact change with a wide reach" \
  "verdict_reason: low-impact and reach 3 -> question (design)" "$(grep '^verdict_reason:' "$WORK/intake.log")"
(cd "$INTAKE_REPO" && "$SCRIPTS/pr-intake.sh" --pr 1 --base "$INTAKE_BASE" --head "$INTAKE_HEAD" \
  --meta "$WORK/intake-meta.json" --flow-dir "$WORK/none") > "$WORK/intake-now.log" 2>&1
expect "pr-intake.sh reads the current labels without --as-of" \
  "verdict_reason: behavior-altering -> question (semver)" "$(grep -m1 '^verdict_reason:' "$WORK/intake-now.log")"

echo "== bash-guard.py"
GUARD="$SCRIPTS/hooks/bash-guard.py"
guard() {  # guard <agent> <mode> <command> — prints deny or allow
  jq -cn --arg a "$1" --arg c "$3" '{tool_name: "Bash", agent_type: $a, tool_input: {command: $c}}' \
    | python3 -I "$GUARD" --mode "$2" | grep -q '"permissionDecision": "deny"' && echo deny || echo allow
}
R=agent-skills:change-reviewer
expect "bash-guard.py allows git show in a fork review" allow "$(guard $R fork 'git show abc123:a.js | head -5')"
expect "bash-guard.py denies a redirect to a file" deny "$(guard $R same 'grep -rn x src > out.txt')"
expect "bash-guard.py denies git checkout" deny "$(guard $R same 'git checkout -- a.js')"
expect "bash-guard.py denies sed -i" deny "$(guard $R same "sed -i '' s/a/b/ a.js")"
expect "bash-guard.py allows a test run on an own branch" allow "$(guard $R same 'yarn test --group core')"
expect "bash-guard.py denies a test run in a fork review" deny "$(guard $R fork 'yarn test --group core')"
expect "bash-guard.py denies command substitution in a fork review" deny "$(guard $R fork 'echo $(id)')"
expect "bash-guard.py leaves other agents alone" allow "$(guard general-purpose fork 'rm -rf x')"

if [ "$FAILED" = 0 ]; then
  echo "RESULT: ok"
  rm -rf "$WORK"
  exit 0
fi
echo "RESULT: FAIL ($FAILED check(s) failed), files kept in $WORK"
exit 1
