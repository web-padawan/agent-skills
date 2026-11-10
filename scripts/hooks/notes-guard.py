#!/usr/bin/env python3
"""notes-guard.py: PreToolUse hook that holds a reviewer pass until its notes file exists.

Registered in hooks/hooks.json for the Agent tool. Claude Code sends the hook payload on
stdin. The guard reads the prompt of the Agent call. It acts only on a prompt that holds the
context line of scripts/lib/prompts.sh:

  Context file: `<context path>` — read it first. Then read `<notes path>` whole if it exists.

It denies the launch when the context file or the notes file does not exist. A pass that
starts without the notes file reviews without the Settled facts of the orchestrator. The
notes file must exist before the fan-out message, so the Write goes in a message of its own.
Every other Agent call gets no decision.

Usage (manual check):
  printf '%s' '<payload json>' | python3 -I notes-guard.py

Exit code 0 always. A denial is JSON on stdout.
"""
import json
import os
import re
import sys

CONTEXT_LINE = re.compile(
    r"Context file: `([^`]+)` — read it first\. Then read `([^`]+)` whole if it exists\.")


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "notes-guard: " + reason,
    }}))
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(payload, dict) or payload.get("tool_name") not in ("Agent", "Task"):
        return
    prompt = (payload.get("tool_input") or {}).get("prompt") or ""
    if not isinstance(prompt, str):
        return
    match = CONTEXT_LINE.search(prompt)
    if not match:
        return
    context, notes = match.group(1), match.group(2)
    if not os.path.isfile(context):
        deny("the context file %s does not exist. Run the plan again, then launch the passes." % context)
    if not os.path.isfile(notes):
        deny("the notes file %s does not exist. Write it in a message of its own, then launch "
             "every pass again in one message (references/pipeline.md §2)." % notes)


if __name__ == "__main__":
    main()
