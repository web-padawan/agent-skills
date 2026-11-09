#!/usr/bin/env bash
# smoke.sh — exercise the scripts that rewrite a working tree, inside a throwaway repository.
#
# Usage:
#   smoke.sh
#
# Builds a git repository under ${TMPDIR:-/tmp}/smoke-<time> with a main branch and a feature
# branch of three commits. Then runs ab.sh, mutant.sh, fixup-into.sh and float-to-tip.sh
# against it and checks their exit codes and their effect on the tree. Runs dev-server.sh and
# `ab.sh --port` against a fake web-dev-server (a python3 http.server) and checks that they
# return through a pipe, restore on SIGTERM, and leave no shell behind. Checks the
# review-plan.sh report dir and earlier-findings list, the post-review.sh refusals, the
# pr-refresh.sh usage refusals, the diff-facts.sh and pr-screen.sh facts on a fixture, the web
# component property facts of diff-facts.sh in a Flow fixture, the workflow-facts.sh facts and
# the dropped tests pass on a workflow-only change, the plan fixtures (a PNG, two conventions
# docs, findings files on the same head, a dirty tree), and the bash-guard.py decisions. Also
# checks that every script in this directory answers --help with exit 0.
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
for f in "$SCRIPTS"/*.sh "$SCRIPTS"/facts/*.sh; do
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

echo "== mutant.sh"
MH=$(git rev-parse HEAD)
check "mutant.sh baseline is green on the clean tree" 0 \
  "$SCRIPTS/mutant.sh" --head "$MH" --baseline --log "$WORK/mut-base.log" -- grep -q three a.txt
printf 'one\ntwo\n' > a.txt
check "mutant.sh reports a killed mutant" 0 \
  "$SCRIPTS/mutant.sh" --head "$MH" --file a.txt --log "$WORK/mut-k.log" -- grep -q three a.txt
expect "mutant.sh prints KILLED" "RESULT: KILLED (exit 1)" "$(grep '^RESULT:' "$WORK/last.log")"
expect "mutant.sh restored a killed mutant" "" "$(git status --porcelain)"
printf 'uno\ntwo\nthree\n' > a.txt
check "mutant.sh reports a surviving mutant" 1 \
  "$SCRIPTS/mutant.sh" --head "$MH" --file a.txt --log "$WORK/mut-s.log" -- grep -q three a.txt
expect "mutant.sh restored a surviving mutant" "" "$(git status --porcelain)"
check "mutant.sh refuses a file without a mutant" 2 \
  "$SCRIPTS/mutant.sh" --head "$MH" --file a.txt -- true
printf 'uno\n' > a.txt && printf 'y\n' > b.txt
check "mutant.sh refuses a second dirty file" 2 \
  "$SCRIPTS/mutant.sh" --head "$MH" --file a.txt -- true
check "mutant.sh refuses a baseline on a dirty tree" 2 \
  "$SCRIPTS/mutant.sh" --head "$MH" --baseline -- true
git checkout -q -- a.txt b.txt
printf 'uno\n' > a.txt
check "mutant.sh refuses a HEAD other than head0" 2 \
  "$SCRIPTS/mutant.sh" --head "$(git rev-parse HEAD~1)" --file a.txt -- true
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

echo "== review-plan.sh"
git remote add origin "$REPO" && git fetch -q origin main
SELF_DIR=$(git rev-parse --path-format=absolute --git-path self-review)
expect "review-plan.sh puts the self-review report dir in the git directory" \
  "report_dir: $SELF_DIR" \
  "$("$SCRIPTS/review-plan.sh" --mode self --no-context --no-write 2>/dev/null | grep '^report_dir:')"
mkdir -p "$SELF_DIR"
jq -n --arg head "$(git rev-parse HEAD)" '{branch: "feature", head: $head, round: 1, findings: [
  {id: "F1", round: 1, category: "logic", tier: "B", status: "open", file: "a.txt", line: 2,
   claim: "kept claim", merged: [{file: "a.txt", line: 3, claim: "merged claim"}]}]}' \
  > "$SELF_DIR/feature-findings.json"
"$SCRIPTS/review-plan.sh" --mode self --no-context > "$WORK/plan.log" 2>&1
expect "review-plan.sh lists a merged finding with the finding that kept it" \
  "- F1 | open | logic | a.txt:2 | B | kept claim Merged: a.txt:3 merged claim" \
  "$(grep '^- F1 ' "$SELF_DIR/context.md" 2>/dev/null)"

echo "== post-review.sh"
# shellcheck source=lib/conventional-label.sh
. "$SCRIPTS/lib/conventional-label.sh"
check "the label check refuses praise, which the review never posts" 1 \
  check_conventional_label "**praise:** clean tests"
check "the label check accepts a decorated issue" 0 \
  check_conventional_label "**issue (logic, blocking):** wrong branch"
printf '{"findings": []}\n' > "$WORK/post.json"
check "post-review.sh refuses a run without --head" 2 \
  "$SCRIPTS/post-review.sh" --findings "$WORK/post.json" --dry-run
POST_HEAD=$(printf 'a%.0s' {1..40})
post_json() {  # post_json <name> <findings JSON array>
  printf '{"findings": %s}\n' "$2" > "$WORK/post-$1.json"
}
post_json status '[{"file": "a", "line": 1, "message": "**issue (logic, blocking):** x", "status": "maybe"}]'
check "post-review.sh refuses a status outside the vocabulary" 2 \
  "$SCRIPTS/post-review.sh" --head "$POST_HEAD" --findings "$WORK/post-status.json" --dry-run
post_json nodup '[{"file": "a", "line": 1, "message": "**issue (logic, blocking):** x", "status": "already raised (bot, 5)"}]'
check "post-review.sh refuses an already raised finding without a dup thread" 2 \
  "$SCRIPTS/post-review.sh" --head "$POST_HEAD" --findings "$WORK/post-nodup.json" --dry-run
post_json verdict '[{"file": "a", "line": 1, "message": "**issue (logic, blocking):** x", "dup": {"id": 5, "verdict": "agrees"}}]'
check "post-review.sh refuses a dup verdict outside the vocabulary" 2 \
  "$SCRIPTS/post-review.sh" --head "$POST_HEAD" --findings "$WORK/post-verdict.json" --dry-run
post_json confirms '[{"file": "a", "line": 1, "message": "**issue (logic, blocking):** x", "dup": {"id": 5, "verdict": "confirms"}}]'
check "post-review.sh refuses a run where every finding confirms a thread" 2 \
  "$SCRIPTS/post-review.sh" --head "$POST_HEAD" --findings "$WORK/post-confirms.json" --dry-run
post_json nonblocking '[{"file": "a", "line": 1, "message": "**suggestion (logic, non-blocking):** x"}]'
check "post-review.sh refuses --blocking-only when no finding is blocking" 2 \
  "$SCRIPTS/post-review.sh" --head "$POST_HEAD" --findings "$WORK/post-nonblocking.json" --dry-run --blocking-only
# A fake gh: PR 1 at $POST_HEAD, no threads, src/a.js with the hunks 1-4 and 21-25 and a
# binary file without a patch.
mkdir -p "$WORK/fakegh"
cat > "$WORK/fakegh/gh" <<'GH'
#!/usr/bin/env bash
jqx=""; prev=""
for a in "$@"; do [ "$prev" = --jq ] && jqx=$a; prev=$a; done
case "$*" in
  "pr view"*) out="{\"id\": \"PR_1\", \"number\": 1, \"headRefOid\": \"$FAKE_HEAD\", \"url\": \"https://github.com/o/r/pull/1\"}" ;;
  *pulls/1/files*) out='[{"filename": "src/a.js", "patch": "@@ -1,3 +1,4 @@\n a\n+b\n c\n d\n@@ -20,2 +21,5 @@ x\n e\n+f\n+g\n+h\n i"}, {"filename": "shot.png"}]' ;;
  *pulls/1/comments*) out='[]' ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
if [ -n "$jqx" ]; then printf '%s' "$out" | jq -r "$jqx"; else printf '%s\n' "$out"; fi
GH
chmod +x "$WORK/fakegh/gh"
post_fake() {  # post_fake <name> — a dry run of post-review.sh against the fake gh
  PATH="$WORK/fakegh:$PATH" FAKE_HEAD="$POST_HEAD" "$SCRIPTS/post-review.sh" --head "$POST_HEAD" \
    --findings "$WORK/post-$1.json" --dry-run
}
post_json inhunk '[{"file": "src/a.js", "line": 22, "message": "**issue (logic):** x"}, {"file": "shot.png", "line": 1, "message": "**nitpick:** y"}]'
check "post-review.sh takes a line anchor in a hunk, and a file without a patch" 0 post_fake inhunk
post_json outside '[{"file": "src/a.js", "line": 10, "message": "**issue (logic):** x"}, {"file": "src/b.js", "line": 3, "message": "**issue (logic):** y"}]'
check "post-review.sh refuses a line anchor outside the hunks of the diff" 2 post_fake outside
expect "post-review.sh names the hunks of a refused line anchor" \
  "  finding 0: src/a.js:10 is outside the hunks (1-4, 21-25)|  finding 1: src/b.js:3 is in no file of the diff" \
  "$(grep '^  finding' "$WORK/last.log" | paste -sd'|' -)"
post_json summaryonly '[{"file": "src/a.js", "line": 10, "message": "**issue (logic):** x", "summary_only": true}]'
check "post-review.sh takes a line outside the hunks for a summary-only finding" 0 post_fake summaryonly
printf '# Review context\n\n- mode: self\n- head: `%s`\n' "$(printf 'a%.0s' {1..40})" > "$WORK/self-context.md"
check "pr-refresh.sh refuses a run without --at" 2 "$SCRIPTS/pr-refresh.sh" --context "$WORK/self-context.md"
check "pr-refresh.sh refuses a run without --context" 2 "$SCRIPTS/pr-refresh.sh" --at gate
check "pr-refresh.sh refuses a context file without a PR" 2 \
  "$SCRIPTS/pr-refresh.sh" --at gate --context "$WORK/self-context.md"

echo "== pr-screen.sh"
SCREENING_CONFIG="$SCRIPTS/../config/screening/vaadin.json"
# Three packages import the changed module, and a unit test asserts CSS. The fixture
# issue is 31 days old and has the label `Impact: Low`.
SCREENING_REPO="$WORK/screening"
git init -q -b main "$SCREENING_REPO"
(
  cd "$SCREENING_REPO" || exit 1
  git config user.email smoke@example.com; git config user.name smoke; git config commit.gpgsign false
  mkdir -p packages/core/src packages/a/src packages/b/src packages/c/src packages/core/test
  printf 'export const M = 1;\n' > packages/core/src/vaadin-core-mixin.js
  printf ':host { color: red; }\n' > packages/core/src/vaadin-core-styles.css
  mkdir -p guidelines && printf '# Testing\n\n- Prefer visual tests over unit tests for CSS.\n' > guidelines/testing.md
  for p in a b c; do
    printf "import { M } from '@vaadin/core/src/vaadin-core-mixin.js';\n" > "packages/$p/src/vaadin-$p.js"
  done
  git add . && git commit -q -m base
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b feature
  printf 'export const M = 2;\nconst b = child.$.button;\n' > packages/core/src/vaadin-core-mixin.js
  printf ':host { color: blue; }\n' > packages/core/src/vaadin-core-styles.css
  printf "it('x', () => {\n  expect(getComputedStyle(el).color).to.equal('blue');\n});\n" > packages/core/test/core.test.js
  git add . && git commit -q -m change
)
ISSUE_CREATED=$(jq -nr 'now - 31 * 86400 | todate')
cat > "$WORK/screening-meta.json" <<EOF
{"slug": "owner/name", "data": {"repository": {"pullRequest": {
  "title": "fix: change the core mixin", "isCrossRepository": true, "author": {"login": "someone"},
  "closingIssuesReferences": {"nodes": [{
    "number": 7, "state": "OPEN", "createdAt": "$ISSUE_CREATED", "author": {"login": "platosha"},
    "body": "The core mixin is wrong.",
    "labels": {"nodes": [{"name": "bug"}, {"name": "Impact: Low"}]},
    "comments": {"nodes": []}}]}}}}}
EOF
SCREENING_BASE=$(git -C "$SCREENING_REPO" rev-parse HEAD~1)
SCREENING_HEAD=$(git -C "$SCREENING_REPO" rev-parse HEAD)
(cd "$SCREENING_REPO" && REVIEW_FLOW_DIR="$WORK/none" "$SCRIPTS/diff-facts.sh" --base "$SCREENING_BASE" \
  --head "$SCREENING_HEAD") > "$WORK/diff-facts.log" 2>&1
expect "diff-facts.sh counts three importing packages" \
  "reach: packages/core/src/vaadin-core-mixin.js -> 3 other packages [a b c]" \
  "$(grep '^reach: packages/core/src/vaadin-core-mixin.js' "$WORK/diff-facts.log")"
expect "diff-facts.sh flags CSS that a unit test asserts" \
  "css_unit_assertions: packages/core/test/core.test.js:2" "$(grep '^css_unit_assertions:' "$WORK/diff-facts.log")"
expect "diff-facts.sh names the rule behind the CSS hits" \
  "css_rule: guidelines/testing.md:3" "$(grep '^css_rule:' "$WORK/diff-facts.log")"
expect "diff-facts.sh lists a new test file with its size" \
  "new_test_files: packages/core/test/core.test.js (3 lines) for 5 changed production lines" "$(grep '^new_test_files:' "$WORK/diff-facts.log")"
expect "diff-facts.sh lists a read of the shadow DOM of another element" \
  "shadow_reach: packages/core/src/vaadin-core-mixin.js:2 child.$.button" "$(grep '^shadow_reach:' "$WORK/diff-facts.log")"
expect "diff-facts.sh prints the rule of the shadow DOM read" 1 \
  "$(grep -c '^rule: Each `shadow_reach` entry' "$WORK/diff-facts.log")"

# A Flow repository: the diff syncs a property, and the web component checkout declares it
# with notify and a default at the pinned tag. It also syncs `fileName`, which only another
# package declares, and uses `downloadButtonHidden` and `download()`, which only a commit after
# the tag declares.
FLOWFX="$WORK/flowfx"; WCFX="$WORK/wcfx"
git init -q -b main "$WCFX"
(
  cd "$WCFX" || exit 1
  git config user.email smoke@example.com; git config user.name smoke; git config commit.gpgsign false
  mkdir -p packages/x/src
  printf 'static get properties() {\n  return {\n    zoom: {\n      type: String,\n      value: %s,\n      notify: true,\n    },\n  };\n}\n  open() {\n  }\n' "'a'" > packages/x/src/vaadin-x.js
  mkdir -p packages/y/src
  printf 'static get properties() {\n  return {\n    fileName: {\n      type: String,\n    },\n  };\n}\n' > packages/y/src/vaadin-y.js
  git add . && git commit -q -m wc && git tag v1.0.0
  printf 'static get properties() {\n  return {\n    downloadButtonHidden: {\n      type: Boolean,\n    },\n  };\n}\n  download() {\n  }\n' > packages/x/src/vaadin-x-download-mixin.js
  git add . && git commit -q -m download
)
WCFX_LATER=$(git -C "$WCFX" rev-parse --short main)
git init -q -b main "$FLOWFX"
(
  cd "$FLOWFX" || exit 1
  git config user.email smoke@example.com; git config user.name smoke; git config commit.gpgsign false
  mkdir -p x-flow/src/main/java
  printf '<project/>\n' > pom.xml
  printf '@NpmPackage(value = "@vaadin/x", version = "1.0.0")\nclass X {}\n' > x-flow/src/main/java/X.java
  git add . && git commit -q -m base
  printf '@NpmPackage(value = "@vaadin/x", version = "1.0.0")\nclass X {\n  @Synchronize(property = "zoom", value = "zoom-changed")\n  String getZoom() { return null; }\n  void setFileName(String f) { getElement().setProperty("fileName", f); }\n  void hideDownload() { getElement().setProperty("downloadButtonHidden", true); }\n  void download() { getElement().callJsFunction("download"); }\n  void open() { getElement().callJsFunction("open"); }\n}\n' > x-flow/src/main/java/X.java
  git add . && git commit -q -m change
)
(cd "$FLOWFX" && REVIEW_WC_DIR="$WCFX" "$SCRIPTS/diff-facts.sh" --base "$(git rev-parse HEAD~1)" \
  --head "$(git rev-parse HEAD)") > "$WORK/diff-facts-flow.log" 2>&1
expect "diff-facts.sh prints the web component declaration of a synced property" \
  "wc_property: zoom -> @vaadin/x@1.0.0 packages/x/src/vaadin-x.js:3 type=String value='a' notify=true" \
  "$(grep '^wc_property: zoom ' "$WORK/diff-facts-flow.log")"
expect "diff-facts.sh does not take the declaration of a property from another package" \
  "wc_property: fileName -> not declared in @vaadin/x@1.0.0 (a native, inherited or connector property)" \
  "$(grep '^wc_property: fileName ' "$WORK/diff-facts-flow.log")"
expect "diff-facts.sh names a property that only a commit after the pinned tag declares" \
  "wc_property: downloadButtonHidden -> not in @vaadin/x@1.0.0, declared after it at main ($WCFX_LATER) packages/x/src/vaadin-x-download-mixin.js:3" \
  "$(grep '^wc_property: downloadButtonHidden ' "$WORK/diff-facts-flow.log")"
expect "diff-facts.sh names a called method that only a commit after the pinned tag declares" \
  "wc_method: download -> not in @vaadin/x@1.0.0, declared after it at main ($WCFX_LATER) packages/x/src/vaadin-x-download-mixin.js:8" \
  "$(grep '^wc_method: download ' "$WORK/diff-facts-flow.log")"
expect "diff-facts.sh prints the declaration of a called method at the pinned tag" \
  "wc_method: open -> @vaadin/x@1.0.0 packages/x/src/vaadin-x.js:10" \
  "$(grep '^wc_method: open ' "$WORK/diff-facts-flow.log")"
expect "diff-facts.sh prints the rule of an API newer than the pinned version" 1 \
  "$(grep -c '^rule: A `declared after it` entry' "$WORK/diff-facts-flow.log")"
expect "diff-facts.sh prints no reach line in a Flow repository" \
  "" "$(grep -E '^(reach|flow_counterpart):' "$WORK/diff-facts-flow.log")"
expect "diff-facts.sh prints the first-sync rule of a notify property" 1 \
  "$(grep -c '^rule: A `wc_property` with `notify=true`' "$WORK/diff-facts-flow.log")"
(cd "$SCREENING_REPO" && "$SCRIPTS/review-plan.sh" --mode self --no-context --type fix) > "$WORK/diff-facts-plan.log" 2>&1
expect "review-plan.sh quotes the diff facts in the skeleton" \
  "    shadow_reach: packages/core/src/vaadin-core-mixin.js:2 child.$.button" \
  "$(grep '^    shadow_reach:' "$SCREENING_REPO/.git/self-review/context.md" 2>/dev/null)"
(cd "$SCREENING_REPO" && "$SCRIPTS/pr-screen.sh" --pr 1 --reach-max 3 --config "$SCREENING_CONFIG" \
  --meta "$WORK/screening-meta.json") > "$WORK/screening.log" 2>&1
expect "pr-screen.sh sets the flag of an issue label" \
  "issue_flags: low-impact" "$(grep '^issue_flags:' "$WORK/screening.log")"
expect "pr-screen.sh counts a former employee as team" \
  "issue: #7 open labels=[bug, Impact: Low] author=team age=31d comments=0" "$(grep '^issue:' "$WORK/screening.log")"
expect "pr-screen.sh proposes a decision for a low-impact change with a wide reach" \
  "verdict_reason: low-impact and reach 3 -> question (design)" "$(grep '^verdict_reason:' "$WORK/screening.log")"
expect "pr-screen.sh proposes a reply at the gate for a decide verdict" \
  "gate_default: Draft a reply" "$(grep '^gate_default:' "$WORK/screening.log")"
jq '.data.repository.pullRequest.closingIssuesReferences.nodes[0].labels.nodes = []' "$WORK/screening-meta.json" > "$WORK/screening-nolabels.json"
(cd "$SCREENING_REPO" && "$SCRIPTS/pr-screen.sh" --pr 1 --meta "$WORK/screening-nolabels.json") > "$WORK/screening-nolabels.log" 2>&1
expect "pr-screen.sh keeps the fields of an issue without labels" \
  "issue: #7 open labels=[] author=contributor age=31d comments=0" "$(grep '^issue:' "$WORK/screening-nolabels.log")"
expect "pr-screen.sh gives no behavior-altering reason without a breaking label or marker" \
  "0" "$(grep -c 'behavior-altering' "$WORK/screening.log")"
jq '.data.repository.pullRequest.title = "fix!: change the core mixin"
  | .data.repository.pullRequest.body = "Text\r\nBREAKING CHANGE: M is 2"' "$WORK/screening-meta.json" > "$WORK/screening-breaking.json"
(cd "$SCREENING_REPO" && "$SCRIPTS/pr-screen.sh" --pr 1 --reach-max 3 --config "$SCREENING_CONFIG" \
  --meta "$WORK/screening-breaking.json") > "$WORK/screening-breaking.log" 2>&1
expect "pr-screen.sh reads a breaking change that the title and the body mark" \
  "breaking_marker: title and body" "$(grep '^breaking_marker:' "$WORK/screening-breaking.log")"
expect "pr-screen.sh sets behavior-altering for a marked breaking change" \
  "issue_flags: behavior-altering low-impact" "$(grep '^issue_flags:' "$WORK/screening-breaking.log")"
# A feature without acceptance criteria: a contributor gets the flag, a team author skips it.
jq '.data.repository.pullRequest.title = "feat: add a core option"' "$WORK/screening-meta.json" > "$WORK/screening-feat.json"
(cd "$SCREENING_REPO" && "$SCRIPTS/pr-screen.sh" --pr 1 --reach-max 3 --config "$SCREENING_CONFIG" \
  --meta "$WORK/screening-feat.json") > "$WORK/screening-feat.log" 2>&1
expect "pr-screen.sh flags a feature of a contributor without acceptance criteria" \
  "issue_flags: low-impact feature-no-ac" "$(grep '^issue_flags:' "$WORK/screening-feat.log")"
jq '.data.repository.pullRequest.author.login = "platosha"' "$WORK/screening-feat.json" > "$WORK/screening-feat-team.json"
(cd "$SCREENING_REPO" && "$SCRIPTS/pr-screen.sh" --pr 1 --reach-max 3 --config "$SCREENING_CONFIG" \
  --meta "$WORK/screening-feat-team.json") > "$WORK/screening-feat-team.log" 2>&1
expect "pr-screen.sh keeps only the team flags for a team author" \
  "issue_flags: low-impact" "$(grep '^issue_flags:' "$WORK/screening-feat-team.log")"
expect "pr-screen.sh lists the contributor flags it skipped for a team author" \
  "skipped_flags: self-filed feature-no-ac (team author)" "$(grep '^skipped_flags:' "$WORK/screening-feat-team.log")"
(cd "$SCREENING_REPO" && "$SCRIPTS/pr-screen.sh" --pr 1 --reach-max 3 \
  --meta "$WORK/screening-feat.json") > "$WORK/screening-generic.log" 2>&1
(cd "$SCREENING_REPO" && "$SCRIPTS/pr-screen.sh" --pr 1 --scale trivial \
  --meta "$WORK/screening-feat.json") > "$WORK/screening-trivial.log" 2>&1
expect "pr-screen.sh proposes a quick review for a trivial take verdict" \
  "gate_default: Quick review" "$(grep '^gate_default:' "$WORK/screening-trivial.log")"
expect "pr-screen.sh applies only the generic rules without a config" \
  "issue_flags: none|verdict_hint: take" \
  "$(grep '^issue_flags:' "$WORK/screening-generic.log")|$(grep '^verdict_hint:' "$WORK/screening-generic.log")"

echo "== pr-refresh.sh"
# A PR commit, then a merge of main into the PR, then a real change. A stub
# get-pr-context.sh next to a copy of the script prints the current state from a fixture.
RF="$WORK/refresh"
mkdir -p "$RF/bin"
cp "$SCRIPTS/pr-refresh.sh" "$RF/bin/"
printf '#!/usr/bin/env bash\ncat "$REFRESH_FIXTURE"\n' > "$RF/bin/get-pr-context.sh"
chmod +x "$RF/bin/get-pr-context.sh"
git init -q -b main "$RF/repo"
(
  cd "$RF/repo" || exit 1
  git config user.email smoke@example.com; git config user.name smoke; git config commit.gpgsign false
  printf 'a\n' > a.txt && git add . && git commit -q -m base
  git checkout -q -b pr && printf 'p\n' > p.txt && git add . && git commit -q -m pr
  git checkout -q main && printf 'm\n' > m.txt && git add . && git commit -q -m main
  git checkout -q pr && git merge -q --no-edit main
  printf 'p2\n' > p.txt && git commit -q -am change
)
RF_OLD_BASE=$(git -C "$RF/repo" rev-parse main~1)
RF_OLD=$(git -C "$RF/repo" rev-parse pr~1^1)
RF_MERGE=$(git -C "$RF/repo" rev-parse pr~1)
RF_CHANGE=$(git -C "$RF/repo" rev-parse pr)
RF_NEW_BASE=$(git -C "$RF/repo" rev-parse main)
cat > "$RF/context.md" <<EOF
# Review context

- pr: https://github.com/owner/name/pull/1
- base: \`$RF_OLD_BASE\`
- head: \`$RF_OLD\`

## Already on the PR

    threads:  # id | author | kind | state | path:line | first line
      11 | bot | bot | open | p.txt:1 | old claim
          reply 12 | a | human | old reply

## Diff
EOF
refresh_fixture() {  # refresh_fixture <head>
  cat <<EOF
=== PR_METADATA ===
{"headRefOid":"$1"}
=== ANCHORS ===
merge_base: $RF_NEW_BASE
=== CI_STATUS ===
summary: 1 checks — 1 pass, 0 fail, 0 pending, 0 skipped
=== EXISTING_COMMENTS ===
threads:  # id | author | kind | state | path:line | first line
  11 | bot | bot | open | p.txt:1 | old claim
      reply 12 | a | human | old reply
      reply 13 | b | human | new reply
  14 | c | human | open | p.txt:3 | new thread
general:  # id | author | first line
  21 | sonar[bot] | new general
EOF
}
refresh_fixture "$RF_MERGE" > "$RF/merge.txt"
(cd "$RF/repo" && REFRESH_FIXTURE="$RF/merge.txt" "$RF/bin/pr-refresh.sh" --at gate --context "$RF/context.md") > "$RF/merge.log" 2>&1
expect "pr-refresh.sh does not count a merge of the base branch as a change" \
  "tree_changed: no" "$(grep '^tree_changed:' "$RF/merge.log")"
expect "pr-refresh.sh lists a new reply under its known thread, and a new thread" \
  "  11 | bot | bot | open | p.txt:1 | old claim (thread known)|      reply 13 | b | human | new reply|  14 | c | human | open | p.txt:3 | new thread" \
  "$(sed -n '/^new_threads:$/,/^new_general/p' "$RF/merge.log" | sed '1d;$d' | paste -sd'|' -)"
expect "pr-refresh.sh asks to read a new general comment" \
  "action: read each new general comment: a bot can post its review summary there" \
  "$(grep '^action: read each new general' "$RF/merge.log")"
refresh_fixture "$RF_CHANGE" > "$RF/change.txt"
(cd "$RF/repo" && REFRESH_FIXTURE="$RF/change.txt" "$RF/bin/pr-refresh.sh" --at gate --context "$RF/context.md") > "$RF/change.log" 2>&1
expect "pr-refresh.sh lists a file whose own PR diff changed" \
  "tree_changed: 1 files: p.txt" "$(grep '^tree_changed:' "$RF/change.log")"
expect "pr-refresh.sh asks to re-run the plan at the gate" \
  "action: the plan read another diff: re-run review-plan.sh before the gate question" \
  "$(grep '^action: the plan' "$RF/change.log")"
(cd "$RF/repo" && REFRESH_FIXTURE="$RF/change.txt" "$RF/bin/pr-refresh.sh" --at triage --context "$RF/context.md") > "$RF/triage.log" 2>&1
expect "pr-refresh.sh asks to verify each finding at triage" \
  "action: the plan read another diff: verify each finding at ${RF_CHANGE:0:7}; a finding that this head fixes gets status \`fixed at ${RF_CHANGE:0:7}\` and never posts" \
  "$(grep '^action: the plan' "$RF/triage.log")"
printf '=== PR_METADATA ===\nerror: failed to resolve the PR\n' > "$RF/gh-error.txt"
check "pr-refresh.sh exits 1 when gh cannot read the PR" 1 \
  env REFRESH_FIXTURE="$RF/gh-error.txt" "$RF/bin/pr-refresh.sh" --at gate --context "$RF/context.md"

echo "== workflow-facts.sh"
# A workflow change only: a new job without permissions that calls an action on a branch.
WF_REPO="$WORK/workflow"
git init -q -b main "$WF_REPO"
(
  cd "$WF_REPO" || exit 1
  git config user.email smoke@example.com; git config user.name smoke; git config commit.gpgsign false
  mkdir -p .github/workflows
  printf 'on: push\njobs:\n  build:\n    permissions:\n      contents: read\n    runs-on: x\n    steps:\n      - uses: actions/checkout@v7\n' \
    > .github/workflows/ci.yml
  git add . && git commit -q -m base
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b feature
  printf '  dismiss:\n    runs-on: x\n    steps:\n      - name: Dismiss\n        uses: owner/actions/review@feat/x\n' \
    >> .github/workflows/ci.yml
  git add . && git commit -q -m change
)
(cd "$WF_REPO" && "$SCRIPTS/workflow-facts.sh" --base HEAD~1 --head HEAD --no-gh) > "$WORK/workflow.log" 2>&1
expect "workflow-facts.sh names a branch ref and where to read the action" \
  "uses: owner/actions/review@feat/x (branch) read: repos/owner/actions/contents/review/action.yml?ref=feat/x" \
  "$(grep '^uses:' "$WORK/workflow.log")"
expect "workflow-facts.sh lists a new job without permissions" \
  "jobs_without_permissions: .github/workflows/ci.yml: dismiss (new)" \
  "$(grep '^jobs_without_permissions:' "$WORK/workflow.log")"
(cd "$WF_REPO" && "$SCRIPTS/review-plan.sh" --mode self --no-context --no-write --type chore) > "$WORK/workflow-plan.log" 2>&1
expect "review-plan.sh drops the tests pass for a workflow-only change" \
  "passes_dropped: tests (no test, code or binary file changed)" \
  "$(grep '^passes_dropped:' "$WORK/workflow-plan.log")"
expect "review-plan.sh prints the workflow facts" \
  "  jobs_without_permissions: .github/workflows/ci.yml: dismiss (new)" \
  "$(grep '^  jobs_without_permissions:' "$WORK/workflow-plan.log")"

echo "== bash-guard.py"
GUARD="$SCRIPTS/hooks/bash-guard.py"
guard() {  # guard <agent> <mode> <command> — prints deny or allow
  jq -cn --arg a "$1" --arg c "$3" '{tool_name: "Bash", agent_type: $a, tool_input: {command: $c}}' \
    | python3 -I "$GUARD" --mode "$2" | grep -q '"permissionDecision": "deny"' && echo deny || echo allow
}
PLUGIN_NAME=$(jq -r .name "$SCRIPTS/../.claude-plugin/plugin.json")
R="$PLUGIN_NAME:change-reviewer"
expect "bash-guard.py allows git show in a fork review" allow "$(guard $R fork 'git show abc123:a.js | head -5')"
expect "bash-guard.py denies a redirect to a file" deny "$(guard $R same 'grep -rn x src > out.txt')"
expect "bash-guard.py denies git checkout" deny "$(guard $R same 'git checkout -- a.js')"
expect "bash-guard.py denies sed -i" deny "$(guard $R same "sed -i '' s/a/b/ a.js")"
expect "bash-guard.py allows a test run on an own branch" allow "$(guard $R same 'yarn test --group core')"
expect "bash-guard.py denies a test run in a fork review" deny "$(guard $R fork 'yarn test --group core')"
expect "bash-guard.py denies command substitution in a fork review" deny "$(guard $R fork 'echo $(id)')"
expect "bash-guard.py leaves other agents alone" allow "$(guard general-purpose fork 'rm -rf x')"
expect "bash-guard.py leaves a reviewer of another plugin alone" allow "$(guard other-plugin:code-reviewer same 'rm -rf x')"
(cd "$SCREENING_REPO" && "$SCRIPTS/review-plan.sh" --mode self --no-context --no-write --type fix) > "$WORK/prefix-plan.log" 2>&1
expect "review-plan.sh prefixes each agent with the plugin name" \
  "$R" \
  "$(awk '$1 == "change" && /reads:/ { print $2 }' "$WORK/prefix-plan.log")"

echo "== review-plan.sh fixtures"
# Fixtures that pin the plan output of edge paths: a changed PNG, conventions docs of 300
# and 500 lines, findings files on the same head, and a dirty tracked file.
FX="$WORK/fixture"
git init -q -b main "$FX"
git -C "$FX" config user.email smoke@example.com
git -C "$FX" config user.name smoke
git -C "$FX" config commit.gpgsign false
mkdir -p "$FX/src"
printf 'export function a() {\n  return 1;\n}\n' > "$FX/src/a.js"
git -C "$FX" add -A && git -C "$FX" commit -q -m "base"
git -C "$FX" remote add origin "$FX" && git -C "$FX" fetch -q origin main
git -C "$FX" checkout -q -b topic
printf 'export function a() {\n  return 2;\n}\n' > "$FX/src/a.js"
printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\020\000\000\000\010\010\006\000\000\000' > "$FX/shot.png"
git -C "$FX" add -A && git -C "$FX" commit -q -m "fix: return two"
FX_HEAD=$(git -C "$FX" rev-parse HEAD)
FX_DIR=$(git -C "$FX" rev-parse --path-format=absolute --git-path self-review)
fx_plan() {  # fx_plan <log> [flags] — a self-mode plan of the fixture
  local log="$1"; shift
  (cd "$FX" && "$SCRIPTS/review-plan.sh" --mode self --no-context "$@") > "$WORK/$log" 2>&1
}
mkdir -p "$FX_DIR"
echo "## Settled facts" > "$FX_DIR/context-notes.md"
echo "stale" > "$FX_DIR/context-prod.patch"
fx_plan fx-png.log --fresh --type fix
expect "review-plan.sh deletes the notes file and patches of an earlier context" \
  "" "$(ls "$FX_DIR/context-notes.md" "$FX_DIR/context-prod.patch" 2>/dev/null)"
PASS_N=$(grep -c '^Context file:' "$WORK/fx-png.log")
expect "review-plan.sh asks each pass to count the notes file" \
  "yes" "$([ "$PASS_N" -gt 0 ] && [ "$PASS_N" = "$(grep -c '^End your reply with one line that counts that file: `notes:' "$WORK/fx-png.log")" ] && echo yes)"
expect "review-plan.sh lists a changed PNG under binary_files" \
  "binary_files: shot.png " "$(grep '^binary_files:' "$WORK/fx-png.log")"
expect "review-plan.sh lists a changed PNG under the binary lane of the skeleton" \
  "- shot.png" "$(sed -n '/^binary (never diffed):$/{n;p;}' "$FX_DIR/context.md")"
awk 'BEGIN { print "# Conventions"; for (c = 1; c <= 3; c++) { print "## Chapter " c; for (i = 1; i <= 98; i++) print "Rule " c "." i } }' > "$FX/CONVENTIONS.md"
fx_plan fx-conv300.log --fresh --type fix
expect "review-plan.sh quotes a conventions doc of 300 lines whole" \
  "Source: \`CONVENTIONS.md\`, quoted whole (298 lines)." \
  "$(grep '^Source: `CONVENTIONS' "$FX_DIR/context.md")"
awk 'BEGIN { print "# Conventions"; print "## Testing"; for (i = 1; i <= 160; i++) print "Test rule " i; print "## Components"; for (i = 1; i <= 160; i++) print "Code rule " i; print "## Release"; for (i = 1; i <= 170; i++) print "Release rule " i }' > "$FX/CONVENTIONS.md"
fx_plan fx-conv500.log --fresh --type fix
expect "review-plan.sh names a conventions doc of 500 lines and does not quote it" \
  "Source: \`CONVENTIONS.md\`, not quoted (494 lines, over 400)." \
  "$(grep '^Source: `CONVENTIONS' "$FX_DIR/context.md")"
rm -f "$FX/CONVENTIONS.md"
mkdir -p "$FX_DIR"
fx_findings() {  # fx_findings <extra jq fields> — a findings file of the fixture head
  jq -n --arg head "$FX_HEAD" "{branch: \"topic\", head: \$head, round: 1, findings: [] $1}" > "$FX_DIR/topic-findings.json"
}
fx_findings ', verdict: "clean"'
fx_plan fx-verdict.log --type fix
expect "review-plan.sh counts a further round on a head with a verdict" \
  "round: 2 of 1 (rounds budget: matrix, capped by scale)" "$(grep '^round:' "$WORK/fx-verdict.log")"
fx_findings ''
fx_plan fx-noverdict.log --type fix
expect "review-plan.sh counts a further round on a head without a verdict" \
  "round: 2 of 1 (rounds budget: matrix, capped by scale)" "$(grep '^round:' "$WORK/fx-noverdict.log")"
fx_findings ', schema: 2'
fx_plan fx-schema.log --type fix
expect "review-plan.sh reads a findings file of schema 2" \
  "earlier_findings: same head — the earlier review of this head had no finding" \
  "$(grep '^earlier_findings:' "$WORK/fx-schema.log")"
rm -f "$FX_DIR/topic-findings.json"
printf 'export function a() {\n  return 3;\n}\n' > "$FX/src/a.js"
check "review-plan.sh refuses a dirty tracked file in self mode" 2 \
  bash -c "cd '$FX' && '$SCRIPTS/review-plan.sh' --mode self --no-context --no-write --type fix"
expect "review-plan.sh names the dirty tracked files" \
  "guard: refuse: tracked files are dirty — commit or stash first (the coverage stage restores mutants against the index)" \
  "$(grep '^guard:' "$WORK/last.log")"
git -C "$FX" checkout -q -- src/a.js

echo "== contracts"
# Every key that the plan prints is in the plan key list of docs/contracts.md.
CONTRACT_KEYS=$(awk '/^## Plan keys/ { s = 1; next } /^## / { s = 0 } s && /^```/ { c = !c; next } s && c && NF { print $1 }' \
  "$SCRIPTS/../docs/contracts.md" | sort -u)
for log in fx-png.log fx-verdict.log diff-facts-plan.log workflow-plan.log; do
  unknown=$(awk '/^=== PLAN ===$/ { f = 1; next } /^=== PROMPTS ===$/ { f = 0 } f && /^[a-z_0-9]+:/ { sub(/:.*/, ""); print }' "$WORK/$log" \
    | sort -u | comm -23 - <(printf '%s\n' "$CONTRACT_KEYS"))
  expect "docs/contracts.md lists every plan key of $log" "" "$unknown"
done
check "review-plan.sh refuses --off with an unknown stage" 1 \
  bash -c "cd '$FX' && '$SCRIPTS/review-plan.sh' --mode self --no-context --no-write --off nosuch"
check "review-plan.sh refuses --budget without a number" 1 \
  bash -c "cd '$FX' && '$SCRIPTS/review-plan.sh' --mode self --no-context --no-write --budget rounds=x"

echo "== past PRs"
# Only docs/retrospective.md cites a past PR or issue. The fixture PRs of plan-baseline.sh
# and the shorthand link example of comment-slop.md are data, not citations.
PR_HITS=$(cd "$SCRIPTS/.." && grep -rnE '#[0-9]{3,}' agents references skills owners docs scripts \
  README.md CLAUDE.md 2>/dev/null \
  | grep -v -E '^(docs/retrospective\.md|scripts/smoke\.sh|scripts/dev/plan-baseline\.sh|skills/comment-cleanup/references/comment-slop\.md):' \
  || true)
expect "only docs/retrospective.md cites a past PR" "" "$PR_HITS"

if [ "$FAILED" = 0 ]; then
  echo "RESULT: ok"
  rm -rf "$WORK"
  exit 0
fi
echo "RESULT: FAIL ($FAILED check(s) failed), files kept in $WORK"
exit 1
