# classify.sh: sourced by review-plan.sh. The change type of the diff and its scale tier.
#
# Reads: MODE, PR, TYPE_FLAG, BRANCH, BASE, HEAD, CHANGED, TEST_RE
# Sets: GH_ARGS, PR_TITLE, TYPE, TYPE_SIGNAL, TYPE_CONFLICT, TITLE_TYPE, COMMIT_TYPE,
#       BRANCH_TYPE, LINES, TOTAL_LINES, FILES, SCALE, SCALE_REASON, OVERRIDES

# Map a conventional-commit subject to a type. Only the prefix is read; the rest of
# the subject is never interpreted.
prefix_type() {
  case "$1" in
    fix:*|fix\(*) echo fix ;;
    feat:*|feat\(*) echo feature ;;
    refactor:*|refactor\(*|perf:*|perf\(*) echo refactor ;;
    test:*|test\(*|docs:*|docs\(*|chore:*|chore\(*|build:*|build\(*|deps:*|deps\(*|ci:*|ci\(*) echo chore ;;
    *) echo "" ;;
  esac
}

# A lower signal that is *more demanding* than the winner is handed to the change
# pass as a question; it never silently upgrades the type.
demand() { case "$1" in feature) echo 3 ;; fix) echo 2 ;; refactor) echo 1 ;; chore) echo 0 ;; *) echo -1 ;; esac; }

add_override() { OVERRIDES="${OVERRIDES:+$OVERRIDES, }$1"; }

plan_classify() {
  # ── Change type
  PR_TITLE=""
  if command -v gh >/dev/null 2>&1; then
    GH_ARGS=()
    [ -n "$PR" ] && GH_ARGS+=("$PR")
    PR_TITLE=$(gh pr view ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json title --jq .title 2>/dev/null || echo "")
  fi

  TYPE=""
  TYPE_SIGNAL=""
  if [ -n "$TYPE_FLAG" ]; then
    TYPE="$TYPE_FLAG"; TYPE_SIGNAL="--$TYPE_FLAG flag"
  fi

  TITLE_TYPE=$(prefix_type "$PR_TITLE")
  if [ -z "$TYPE" ] && [ -n "$TITLE_TYPE" ]; then
    TYPE="$TITLE_TYPE"; TYPE_SIGNAL="PR title prefix"
  fi

  # Majority conventional prefix across the branch's commits.
  COMMIT_TYPE=""
  COMMIT_TALLY=""
  if [ -n "$BASE" ]; then
    COMMIT_SUBJECTS=$(git log --format=%s "$BASE..$HEAD" 2>/dev/null || echo "")
    if [ -n "$COMMIT_SUBJECTS" ]; then
      fixes=0; feats=0; refs=0; chores=0; total=0
      while IFS= read -r subject; do
        [ -z "$subject" ] && continue
        total=$((total + 1))
        case "$(prefix_type "$subject")" in
          fix) fixes=$((fixes + 1)) ;;
          feature) feats=$((feats + 1)) ;;
          refactor) refs=$((refs + 1)) ;;
          chore) chores=$((chores + 1)) ;;
        esac
      done <<< "$COMMIT_SUBJECTS"
      best=0
      for pair in "fix:$fixes" "feature:$feats" "refactor:$refs" "chore:$chores"; do
        n="${pair#*:}"
        if [ "$n" -gt "$best" ]; then best="$n"; COMMIT_TYPE="${pair%%:*}"; fi
      done
      [ -n "$COMMIT_TYPE" ] && COMMIT_TALLY="$best/$total"
    fi
  fi
  if [ -z "$TYPE" ] && [ -n "$COMMIT_TYPE" ]; then
    TYPE="$COMMIT_TYPE"; TYPE_SIGNAL="commit majority ($COMMIT_TALLY)"
  fi

  BRANCH_TYPE=""
  case "$BRANCH" in
    fix/*|bugfix/*|hotfix/*) BRANCH_TYPE=fix ;;
    feat/*|feature/*) BRANCH_TYPE=feature ;;
    refactor/*|perf/*) BRANCH_TYPE=refactor ;;
    chore/*|docs/*|test/*|ci/*|build/*|deps/*) BRANCH_TYPE=chore ;;
  esac
  if [ -z "$TYPE" ] && [ -n "$BRANCH_TYPE" ]; then
    TYPE="$BRANCH_TYPE"; TYPE_SIGNAL="branch name prefix"
  fi

  if [ -z "$TYPE" ]; then
    TYPE="undetermined"
    TYPE_SIGNAL="none resolved — decide from the diff shape (see references/pipeline.md)"
  fi

  TYPE_CONFLICT="none"
  if [ "$TYPE" != "undetermined" ]; then
    win=$(demand "$TYPE")
    for cand in "PR title:$TITLE_TYPE" "commits:$COMMIT_TYPE" "branch name:$BRANCH_TYPE"; do
      other="${cand#*:}"
      [ -z "$other" ] && continue
      [ "$other" = "$TYPE" ] && continue
      if [ "$(demand "$other")" -gt "$win" ]; then
        TYPE_CONFLICT="${cand%%:*} → $other (more demanding than the declared type — hand it to the change pass)"
        win=$(demand "$other")
      fi
    done
  fi

  # ── Scale
  # The tiers: trivial is 10 production lines or less in 2 files or less. lite is 150 lines
  # or less in 8 files or less. full is above. A risk override forces full at any size.
  # Sized by PRODUCTION lines: tests never enter the mutant or deep budgets, and a
  # 30-line fix with 80 lines of tests is a lite review, not a full one.
  LINES=0
  TOTAL_LINES=0
  FILES=0
  if [ -n "$BASE" ]; then
    read -r LINES TOTAL_LINES FILES <<< "$(git diff --numstat -M "$BASE..$HEAD" 2>/dev/null | awk -F'\t' -v test_re="$TEST_RE" '
      {
        p = $3
        if (p ~ /\.lock$/ || p ~ /(^|\/)package-lock\.json$/) next
        if (p ~ /(^|\/)(dist|node_modules|__snapshots__)\//) next
        if (p ~ /\.(png|jpg|jpeg|gif|webp|ico)$/) next
        files++
        if ($1 == "-" || $2 == "-") next
        total += $1 + $2
        if (p ~ test_re) next
        prod += $1 + $2
      }
      END { printf "%d %d %d\n", prod + 0, total + 0, files + 0 }')"
  fi

  SCALE=""
  if [ "$LINES" -le 10 ] && [ "$FILES" -le 2 ]; then SCALE="trivial"
  elif [ "$LINES" -le 150 ] && [ "$FILES" -le 8 ]; then SCALE="lite"
  else SCALE="full"; fi
  SCALE_REASON="size"

  # Risk overrides — size is a proxy for risk, not risk itself.
  OVERRIDES=""
  if [ -n "$CHANGED" ]; then
    printf '%s\n' "$CHANGED" | grep -q '\.d\.ts$' && add_override "a .d.ts file changed"
    printf '%s\n' "$CHANGED" | grep -qE '^(\.github/|\.circleci/|Jenkinsfile|azure-pipelines|\.gitlab-ci)' && add_override "CI or build infra touched"
    printf '%s\n' "$CHANGED" | grep -qiE '(^|/)(release|publish)[^/]*\.(sh|js|mjs|yml|yaml)$' && add_override "release tooling touched"
  fi
  if [ -n "$BASE" ] && git diff --unified=0 "$BASE..$HEAD" 2>/dev/null | grep -qE '^\+[[:space:]]*export '; then
    add_override "a new export added"
  fi

  if [ -n "$OVERRIDES" ] && [ "$SCALE" != "full" ]; then
    SCALE="full"; SCALE_REASON="risk override: $OVERRIDES"
  elif [ -n "$OVERRIDES" ]; then
    SCALE_REASON="size (risk override also applies: $OVERRIDES)"
  fi
  return 0
}
