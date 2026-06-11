#!/usr/bin/env bash
# Sentinel probe: re-running install.sh must NOT wipe non-distribution skills.
# `hermes profile install --force` replaces a profile's whole skills tree, so
# install.sh §4a snapshots each profile's skills before the install and merges
# back any top-level skill dir the install removed. This probe guards that.
#
# The underlying wipe is fixed upstream: https://github.com/NousResearch/hermes-agent/pull/44386
# (fixes https://github.com/NousResearch/hermes-agent/issues/25120). Once the deployed
# hermes-agent includes that fix, §4a can be removed — this probe verifies removal-readiness:
# with §4a reverted it should still report extras preserved.
#
#   scripts/probe-install-preserves-extras.sh
#
# PASS = planted extra skills survive a reinstall, distribution skills still
# refresh (no stale resurrection), and the §4b doctrine seed still lands.
# Runs entirely inside a throwaway HERMES_HOME; never touches ~/.hermes.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export HERMES_HOME="$(mktemp -d /tmp/devos-probe.XXXXXX)"
trap 'rc=$?; if [ "$rc" -eq 0 ]; then rm -rf "$HERMES_HOME"; else echo "probe artifacts kept at $HERMES_HOME" >&2; fi' EXIT
LOG="$HERMES_HOME/install.log"
fail(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }

echo "probe: HERMES_HOME=$HERMES_HOME"
bash "$REPO/install.sh" --yes --skip-oauth >"$LOG" 2>&1 || fail "first install.sh run exited $? (see $LOG)"
DEVOS_SKILLS="$HERMES_HOME/profiles/devos/skills"
[ -d "$DEVOS_SKILLS/coordinate-and-route" ] || fail "first install did not lay down devos distribution skills"

# Plant non-distribution extras — what a live profile accretes over time.
mkdir -p "$DEVOS_SKILLS/zz-sentinel-extra"
echo "sentinel marker" > "$DEVOS_SKILLS/zz-sentinel-extra/SKILL.md"
mkdir -p "$HERMES_HOME/profiles/devos-planner/skills/zz-sentinel-extra"
echo "sentinel marker" > "$HERMES_HOME/profiles/devos-planner/skills/zz-sentinel-extra/SKILL.md"
# Plant drift in a distribution-owned skill — the reinstall must still refresh it.
echo "PROBE-DRIFT" >> "$DEVOS_SKILLS/coordinate-and-route/SKILL.md"

bash "$REPO/install.sh" --yes --skip-oauth >"$LOG" 2>&1 || fail "second install.sh run exited $? (see $LOG)"

[ -f "$DEVOS_SKILLS/zz-sentinel-extra/SKILL.md" ] || fail "reinstall wiped devos extra skill (zz-sentinel-extra)"
[ -f "$HERMES_HOME/profiles/devos-planner/skills/zz-sentinel-extra/SKILL.md" ] || fail "reinstall wiped devos-planner extra skill"
if grep -q "PROBE-DRIFT" "$DEVOS_SKILLS/coordinate-and-route/SKILL.md"; then
  fail "distribution skill not refreshed on reinstall (stale copy survived)"
fi
[ -f "$DEVOS_SKILLS/devops/kanban-worker/SKILL.md" ] || fail "doctrine seed (§4b) missing after reinstall"
echo "PASS: extras preserved, distribution skills refreshed, doctrine seed intact"
