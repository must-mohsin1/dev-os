#!/usr/bin/env bash
# verify_code_landed.sh — Pre-complete verification that a worker actually
# shipped code, not just claimed they did.
#
# Pattern observed in items 6 and 7 (2026-06-11): workers reported
# "shipped, N tests pass, 0 regressions" but the workspace was empty
# and the files weren't in the repo. Orchestrator was force-completing
# based on self-claims.
#
# This script is meant to be called BEFORE any `hermes kanban complete`
# on a worker card. It refuses to proceed if:
#   1. The card's workspace is empty
#   2. None of the card's Files: paths have any diff vs the parent commit
#   3. The card body contains a "no code changes" / "skipped" / "deferred"
#      marker that the worker used to skip the work
#
# Usage: verify_code_landed.sh <card-id> [repo-path]
#   card-id:  the kanban card ID (e.g. t_35c90447)
#   repo-path: path to the working repo (default: current dir)
#
# Exit codes:
#   0 — code landed; safe to complete
#   1 — workspace empty OR no file diffs OR no-code-change marker
#   2 — card-id not found OR malformed card body
#   3 — usage error
#
# Companion to safe-complete. safe-complete guards against rubber-stamping
# review findings; this guards against rubber-stamping worker self-claims.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <card-id> [repo-path]" >&2
  exit 3
fi

CARD_ID="$1"
REPO_PATH="${2:-$(pwd)}"

# Find the workspace dir
WS_DIR="$HOME/.hermes/kanban/boards/*/workspaces/$CARD_ID"
if [[ ! -d $WS_DIR ]]; then
  echo "ERROR: workspace $WS_DIR not found" >&2
  exit 2
fi

# 1. Workspace must not be empty
WS_FILES=$(find "$WS_DIR" -type f -not -name "*.pyc" -not -path "*__pycache__*" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$WS_FILES" -eq 0 ]]; then
  echo "REFUSING: workspace $WS_DIR is empty (0 non-pyc files)." >&2
  echo "  Worker claimed 'shipped' but did not write any code to the workspace." >&2
  echo "  This is the worker-claim-lies pattern from item6+item7." >&2
  exit 1
fi

# 2. Get the card body and look for Files: scope
CARD_BODY=$(hermes kanban show "$CARD_ID" 2>/dev/null || echo "")
if [[ -z "$CARD_BODY" ]]; then
  echo "ERROR: could not read card body for $CARD_ID" >&2
  exit 2
fi

# Extract the Files: block from the card body
FILES_SCOPE=$(echo "$CARD_BODY" | awk '/^Files:/,/^$/' | grep -E '^\s+-?\s*`?[^ ]' | sed -E 's/^\s*-?\s*`?([^`]+)`?\s*$/\1/' | grep -v '^$' | head -20)

if [[ -z "$FILES_SCOPE" ]]; then
  echo "WARN: no Files: scope found in card body — falling back to diff-against-base check" >&2
  FILES_SCOPE=""
fi

# 3. Check for no-code-change markers in the card body
NO_CODE_MARKERS="no code changes|no-changes|skipped|deferred to follow-up|placeholder|stub only|nothing to ship|claim-only"
if echo "$CARD_BODY" | grep -qiE "$NO_CODE_MARKERS"; then
  echo "REFUSING: card body contains a no-code-change marker." >&2
  echo "  Markers checked: $NO_CODE_MARKERS" >&2
  exit 1
fi

# 4. Check that the card's Files: scope has diffs vs the parent commit
cd "$REPO_PATH"
PARENT_COMMIT=$(git rev-parse HEAD)
DIFFS_FOUND=0
TOTAL_CHECKED=0
for f in $FILES_SCOPE; do
  TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
  # Strip wildcards / leading ./ — git diff can handle exact paths
  if git diff --name-only "$PARENT_COMMIT" -- "$f" 2>/dev/null | grep -q .; then
    DIFFS_FOUND=$((DIFFS_FOUND + 1))
  elif [[ -f "$f" ]] && ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    # Untracked file with content
    if [[ -s "$f" ]]; then
      DIFFS_FOUND=$((DIFFS_FOUND + 1))
    fi
  fi
done

if [[ "$TOTAL_CHECKED" -gt 0 && "$DIFFS_FOUND" -eq 0 ]]; then
  echo "REFUSING: card has Files: scope with $TOTAL_CHECKED files, but NONE have diffs vs HEAD." >&2
  echo "  Worker claimed 'shipped' but the code did not land in the repo." >&2
  echo "  This is the worker-claim-lies pattern from item6+item7." >&2
  echo "" >&2
  echo "  Files checked:" >&2
  for f in $FILES_SCOPE; do
    echo "    - $f" >&2
  done
  exit 1
fi

# 5. All checks passed
echo "OK: code landed."
echo "  Workspace files: $WS_FILES"
echo "  Files in scope:  $TOTAL_CHECKED"
echo "  Files with diff: $DIFFS_FOUND"
exit 0
