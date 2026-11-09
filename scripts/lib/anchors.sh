# anchors.sh: sourced by review-plan.sh. The context script call, the base and the head,
# the fork facts, the guards and the fork marker.
#
# Reads: MODE, PR, WANT_CONTEXT, NO_WRITE, SCRIPT_DIR, PLUGIN_NAME, REPO_ROOT
# Sets: CTX, CTX_NOTE, BRANCH, HEAD0, BASE_BRANCH, ANCHOR_BASE, ANCHOR_HEAD, FORK, HEAD_REPO,
#       BASE, HEAD, BASE_SOURCE, GUARD, FORK_MARKER

# Read a key from the ANCHORS section only. Everything before it can contain a PR
# body, which is user-controlled text that must never be mistaken for a SHA.
anchor() {
  printf '%s\n' "$CTX" | awk -v key="$1" '
    /^=== ANCHORS ===$/ { in_section = 1; next }
    /^=== / { in_section = 0 }
    in_section && $1 == key ":" { print $2; exit }
    in_section && index($0, key ": ") == 1 { print substr($0, length(key) + 3); exit }
  '
}

# One-line digest of what CI already proved, read from the context script's own
# CI_STATUS section. Display only: check names come from the head's workflow files,
# so they are never parsed for anything that reaches git.
ci_summary() {
  printf '%s\n' "$CTX" | awk '
    /^=== CI_STATUS ===$/ { in_section = 1; next }
    /^=== / { in_section = 0 }
    in_section && index($0, "summary: ") == 1 { print substr($0, 10); exit }
    in_section && index($0, "unavailable: ") == 1 { print "unavailable — " substr($0, 14); exit }
  '
}

plan_anchors() {
  # The fork marker: scripts/hooks/bash-guard.py reads it and holds the reviewer passes to
  # read-only commands while a fork review runs. It expires on its own (bash-guard.py).
  FORK_MARKER="${XDG_CACHE_HOME:-$HOME/.cache}/$PLUGIN_NAME/fork-review"

  # ── Context script
  # One wrapped call, printed verbatim: the caller gets PR metadata, branch state
  # and ANCHORS without a second round trip. A failure here is not fatal — the plan
  # falls back to git-only facts.
  CTX=""
  CTX_NOTE=""
  if [ "$WANT_CONTEXT" = true ]; then
    CTX_ARGS=(--no-diff)
    [ -n "$PR" ] && CTX_ARGS+=(--pr "$PR")
    if ! CTX=$("$SCRIPT_DIR/get-pr-context.sh" "${CTX_ARGS[@]}" 2>&1); then
      CTX_NOTE="context script failed — plan uses git-only facts"
    fi
    # Print only what the orchestrator acts on: PR metadata, CI and the existing
    # comments, plus any error line from the rest. BRANCH_STATE, ANCHORS and
    # REVIEW_INSTRUCTIONS are restated by the plan (branch, guard, base/head,
    # conventions_doc), and the ANCHORS file lists repeat the plan's lanes — on a
    # 33-file PR they were a third of a plan output too large to show inline.
    [ -n "$CTX" ] && printf '%s\n' "$CTX" | awk '
      /^=== / { keep = ($0 ~ /^=== (PR_METADATA|CI_STATUS|EXISTING_COMMENTS) ===$/); if (keep) print; else held = $0; next }
      keep { print; next }
      /^error: / { if (held != "") { print ""; print held; held = "" } print }
    ' | awk 'NF || !blank { print } { blank = !NF }'
  fi

  BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  HEAD0=$(git rev-parse HEAD 2>/dev/null || echo "")

  BASE_BRANCH=$(anchor base_branch)
  if [ -z "$BASE_BRANCH" ]; then
    if git rev-parse --verify origin/main >/dev/null 2>&1; then BASE_BRANCH="main"
    elif git rev-parse --verify origin/master >/dev/null 2>&1; then BASE_BRANCH="master"
    else BASE_BRANCH=""; fi
  fi

  ANCHOR_BASE=$(anchor merge_base)
  ANCHOR_HEAD=$(anchor head)
  case "$ANCHOR_BASE" in *[!0-9a-f]*) ANCHOR_BASE="" ;; esac
  case "$ANCHOR_HEAD" in *[!0-9a-f]*) ANCHOR_HEAD="" ;; esac
  FORK=$(anchor fork)
  case "$FORK" in true|false) ;; *) FORK="" ;; esac
  [ "$MODE" = "pr" ] || FORK=""
  HEAD_REPO=$(anchor head_repo)
  [[ "$HEAD_REPO" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || HEAD_REPO=""

  # self mode always reviews the local branch, so its head is local HEAD; the anchors'
  # base is only trusted when it was computed against that same head (an unpushed or
  # rebased branch otherwise drags base-branch commits into the diff).
  BASE=""
  HEAD=""
  BASE_SOURCE="anchors"
  if [ "$MODE" = "self" ]; then
    HEAD="$HEAD0"
    if [ -n "$ANCHOR_BASE" ] && [ "$ANCHOR_HEAD" = "$HEAD0" ]; then
      BASE="$ANCHOR_BASE"
    elif [ -n "$BASE_BRANCH" ]; then
      BASE=$(git merge-base "origin/$BASE_BRANCH" HEAD 2>/dev/null || echo "")
      BASE_SOURCE="recomputed"
    fi
  else
    HEAD="${ANCHOR_HEAD:-$HEAD0}"
    BASE="$ANCHOR_BASE"
    if [ -z "$BASE" ] && [ -n "$BASE_BRANCH" ]; then
      BASE=$(git merge-base "origin/$BASE_BRANCH" "$HEAD" 2>/dev/null || echo "")
      BASE_SOURCE="recomputed"
    fi
  fi

  # ── Guards
  GUARD="ok"
  if [ "$MODE" = "self" ]; then
    case "$BRANCH" in
      main|master) GUARD="refuse: on $BRANCH — self-review runs on a topic branch" ;;
      maintenance/*) GUARD="refuse: on a maintenance branch — self-review runs on a topic branch" ;;
      "") GUARD="refuse: detached HEAD — check out the branch first" ;;
    esac
    if [ "$GUARD" = "ok" ] && [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      GUARD="refuse: tracked files are dirty — commit or stash first (the coverage stage restores mutants against the index)"
    fi
  fi
  if [ "$GUARD" = "ok" ] && [ -z "$BASE" ]; then
    GUARD="refuse: cannot resolve the merge base — fetch the base branch, or pass --pr"
  fi
  # A fork head in the working tree means that its .claude/settings.json, hooks, skills,
  # rules and CLAUDE.md loaded when this session started. Nothing in this run can undo that.
  if [ "$GUARD" = "ok" ] && [ "$FORK" = "true" ] && [ -n "$HEAD" ] && [ "$HEAD0" = "$HEAD" ]; then
    GUARD="refuse: the fork head is the working tree, and its project settings loaded at session start — check out the base branch, start a new session, and run the review again"
  fi

  # ── Fork marker
  if [ "$NO_WRITE" != true ]; then
    # Only a pr-mode run replaces the marker. A self-review elsewhere must not lift the
    # read-only hold of a fork review that still runs; the marker expires on its own.
    if [ "$FORK" = "true" ] && [ "$GUARD" = "ok" ]; then
      mkdir -p "$(dirname "$FORK_MARKER")"
      printf 'repo=%s\npr=%s\nhead=%s\nsince=%s\n' "$REPO_ROOT" "${PR:-}" "$HEAD" "$(date +%s)" > "$FORK_MARKER"
    elif [ "$MODE" = "pr" ]; then
      rm -f "$FORK_MARKER"
    fi
  fi
  return 0
}
