#!/usr/bin/env python3
"""question-guard.py: PreToolUse hook that keeps the pr-review questions readable on their own.

Registered in hooks/hooks.json for the AskUserQuestion tool. Claude Code sends the hook
payload on stdin. The open question dialog can cover the text above it, and a message can
lose its text. So the two questions of pr-review carry their own content:

  Review  the Gate question starts with the Problem and Change lines of the explanation
          (skills/pr-review/SKILL.md, Gate).
  Post    the post question names the census and each finding after its first sentence
          (skills/pr-review/references/present.md).

The guard denies a question with one of these headers that lacks that content. Every other
question gets no decision.

Usage (manual check):
  printf '%s' '<payload json>' | python3 -I question-guard.py

Exit code 0 always. A denial is JSON on stdout.
"""
import json
import re
import sys

POST_MIN = 20  # characters after the first question mark: at least one label and anchor


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "question-guard: " + reason,
    }}))
    sys.exit(0)


def problem(header, text):
    """Why the question text of a pr-review header is not ready, or None."""
    if header == "Review":
        if not (re.search(r"\bProblem\b", text) and re.search(r"\bChange\b", text)):
            return ("the `Review` question must start with the Problem and Change lines of the "
                    "explanation (skills/pr-review/SKILL.md, Gate)")
    elif header == "Post":
        rest = text.split("?", 1)[1] if "?" in text else ""
        if len(rest.strip()) < POST_MIN:
            return ("the `Post` question must name the census and the label and anchor of each "
                    "finding that can post (skills/pr-review/references/present.md)")
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(payload, dict) or payload.get("tool_name") != "AskUserQuestion":
        return
    questions = (payload.get("tool_input") or {}).get("questions") or []
    if not isinstance(questions, list):
        return
    for q in questions:
        if not isinstance(q, dict):
            continue
        reason = problem(q.get("header"), q.get("question") or "")
        if reason:
            deny(reason + ". Give the full text in a message of its own first, then ask.")


if __name__ == "__main__":
    main()
