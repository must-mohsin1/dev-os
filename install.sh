#!/usr/bin/env bash
# dev-os installer — stands up the autonomous agent org (coordinator + research/planning specialists)
# on Hermes, above the hermes-devcrew implementation team.
#   ./install.sh                 install agents, link runners, set descriptions (idempotent, safe)
#   ./install.sh --with-cron     also register the nightly improvement loop (needs DEVOS_IMPROVE_REPO)
#
# Requires: hermes; OAuth for Codex (`openai-codex`) + Grok (`xai-oauth`); hermes-devcrew (dependency).
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
WITH_CRON=0; [ "${1:-}" = "--with-cron" ] && WITH_CRON=1
say(){ printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
die(){ printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
command -v hermes >/dev/null 2>&1 || die "Hermes not found — https://hermes-agent.nousresearch.com/docs/"
authed(){ hermes auth list 2>/dev/null | grep -qi "$1"; }

# 1) dependency: hermes-devcrew (implementation team) -------------------------------------------
if command -v devcrew-run >/dev/null 2>&1; then say "dependency hermes-devcrew: present"
else warn "hermes-devcrew not found — install it so devos can dispatch builds:
    git clone https://github.com/must-mohsin1/hermes-devcrew && cd hermes-devcrew && ./install.sh"; fi

# 2) credentials (OAuth) — skip if already authed ----------------------------------------------
authed "openai-codex" && say "Codex: authed" || warn "Codex not authed → run: hermes auth add openai-codex --type oauth"
authed "xai"          && say "Grok:  authed" || warn "Grok not authed  → run: hermes auth add xai-oauth --type oauth"

# 3) install the 3 agent profiles ---------------------------------------------------------------
for d in "$SRC"/agents/*/; do
  [ -f "$d/distribution.yaml" ] || continue
  name=$(grep -E '^name:' "$d/distribution.yaml" | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '"'"'"' ')
  hermes profile install "$d" --force --yes >/dev/null 2>&1 && say "installed $name" || warn "install failed: $name"
done

# 4) orchestrator descriptions + Grok + fallback key -------------------------------------------
hermes profile describe devos --text "Dev OS coordinator: routes goals to researcher/planner/devcrew, gates at the plan, tracks the board." >/dev/null 2>&1 || true
hermes profile describe devos-researcher --text "Research specialist: Grok web research with parallel sub-searchers; cited briefs." >/dev/null 2>&1 || true
hermes profile describe devos-planner --text "Planning specialist: goal+brief -> approval-ready specs with checkable acceptance criteria." >/dev/null 2>&1 || true
hermes --profile devos-researcher tools enable x_search >/dev/null 2>&1 && say "Grok x_search enabled on researcher" || true
if [ -f "$HOME_DIR/.env" ]; then
  while IFS= read -r line; do case "$line" in OPENROUTER*) v="${line%%=*}"; for p in devos devos-researcher devos-planner; do pe="$HOME_DIR/profiles/$p/.env"; [ -d "${pe%/*}" ] && { touch "$pe"; grep -q "^$v=" "$pe" 2>/dev/null || printf '%s\n' "$line" >> "$pe"; }; done;; esac; done < "$HOME_DIR/.env"
fi

# 5) link the runners ---------------------------------------------------------------------------
chmod +x "$SRC/devos-run" "$SRC/devos-improve" 2>/dev/null || true
if [ -d "$HOME/.local/bin" ]; then
  ln -sf "$SRC/devos-run" "$HOME/.local/bin/devos-run"
  ln -sf "$SRC/devos-improve" "$HOME/.local/bin/devos-improve"
  say "linked devos-run + devos-improve -> ~/.local/bin"
fi

# 6) optional improvement cron ------------------------------------------------------------------
if [ "$WITH_CRON" = 1 ]; then
  if [ -n "${DEVOS_IMPROVE_REPO:-}" ]; then
    hermes --profile devos cron add "0 3 * * *" "devos-improve $DEVOS_IMPROVE_REPO" >/dev/null 2>&1 \
      && say "nightly improvement loop set for $DEVOS_IMPROVE_REPO" || warn "could not register cron"
  else warn "set DEVOS_IMPROVE_REPO=/path/to/repo and re-run with --with-cron"; fi
fi

cat <<DONE

✅ dev-os installed.  Agents: devos · devos-researcher · devos-planner   (devcrew = build dependency)

Run the pipeline:
  devos-run "Add OAuth login with tests" /path/to/repo      # research -> plan -> [approve] -> build -> report
  devos-run --no-gate "..." /repo                           # fully autonomous
  devos-improve /path/to/repo                               # propose the top improvement (no build)
  hermes gateway start                                      # drive devos from Discord
DONE
