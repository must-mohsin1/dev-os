#!/usr/bin/env bash
# sync-doctrine — converge every off-repo copy of the kanban doctrine skills
# onto the repo seeds. Covers what the installers don't:
#   1. the global skill template tree (~/.hermes/skills/devops/)
#   2. stray profiles outside both fleets that already carry kanban-worker
#   3. the devos profile's CATEGORIZED duplicates under skills/devops/
#      (hermes profile install only writes the flat skills/<name>/ layout)
# Idempotent. Invoked by scripts/upgrade.sh; safe to run by hand.
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HHOME="${HERMES_HOME:-$HOME/.hermes}"

sync_dir() {  # $1 = seed dir, $2 = destination dir
  seed="$1"; dest="$2"
  [ -d "$seed" ] || return 0
  if [ -f "$dest/SKILL.md" ] && ! diff -q "$dest/SKILL.md" "$seed/SKILL.md" >/dev/null 2>&1; then
    echo "  ! overwriting drifted copy: $dest/SKILL.md" >&2
  fi
  mkdir -p "$dest" && cp -R "$seed/." "$dest/"
  echo "synced: $dest"
}

# 1) Global template tree
sync_dir "$SRC_DIR/skills/devops/kanban-worker"                  "$HHOME/skills/devops/kanban-worker"
sync_dir "$SRC_DIR/agents/devos/skills/kanban-orchestrator"      "$HHOME/skills/devops/kanban-orchestrator"

# 2) Stray profiles outside both fleets that already carry kanban-worker
for pdir in "$HHOME"/profiles/*/; do
  name="$(basename "$pdir")"
  case "$name" in devos|devos-researcher|devos-planner|devcrew-*) continue ;; esac
  [ -f "$pdir/skills/devops/kanban-worker/SKILL.md" ] || continue
  sync_dir "$SRC_DIR/skills/devops/kanban-worker" "$pdir/skills/devops/kanban-worker"
done

# 3) devos profile categorized duplicates (flat copies are installer-managed)
if [ -d "$HHOME/profiles/devos" ]; then
  sync_dir "$SRC_DIR/agents/devos/skills/kanban-orchestrator" "$HHOME/profiles/devos/skills/devops/kanban-orchestrator"
  sync_dir "$SRC_DIR/agents/devos/skills/kanban-doctor"       "$HHOME/profiles/devos/skills/kanban-doctor"
fi

echo "sync-doctrine: done"
