#!/usr/bin/env bash
# Dev OS setup — configures the `devos` coordinator profile per DEVOS.md.
#   ./setup-devos.sh            full setup (runs the two OAuth logins)
#   ./setup-devos.sh --config   config only (skip OAuth; safe to re-run)
#   SETUP_DEVOS_MANUAL_PASTE=1  pass OAuth callback manually (browser-only remotes)
# Policy: Codex main · OpenRouter fallback (gpt-5.5, deepseek-v4-flash) · Grok web search ·
#         Discord gateway · NO Claude/Gemini.
# NOTE: `hermes login` was removed in 0.14.x — credentials are managed via `hermes auth`.
set -euo pipefail
PROFILE=devos
HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
DO_OAUTH=1; [ "${1:-}" = "--config" ] && DO_OAUTH=0
AUTH_ARGS=()
remote_session(){ [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; }
if [ "${SETUP_DEVOS_MANUAL_PASTE:-0}" = "1" ] || remote_session; then AUTH_ARGS+=(--manual-paste); fi
say(){ printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
command -v hermes >/dev/null 2>&1 || { echo "hermes not found"; exit 1; }
authed(){ hermes auth list 2>/dev/null | grep -qi "$1"; }
auth_add_oauth() {
  local provider=$1; shift
  local log first_rc second_rc
  log="$(mktemp)"
  if hermes auth add "$provider" --type oauth "$@" 2>&1 | tee "$log"; then
    rm -f "$log"
    return 0
  fi
  first_rc="${PIPESTATUS[0]:-1}"
  if grep -q "Remote session detected" "$log"; then
    rm -f "$log"
    printf '%s\n' ">> Retrying $provider with --manual-paste..."
    if hermes auth add "$provider" --type oauth --manual-paste; then return 0; fi
    second_rc=$?
    return "$second_rc"
  fi
  rm -f "$log"
  return "$first_rc"
}

# 1) Account OAuth (your action — opens a browser login on this machine)
if [ "$DO_OAUTH" = "1" ]; then
  say "Codex login (main model) — use the COMPANY account first; if it fails, personal."
  if [ "${AUTH_ARGS[*]:-}" != "" ]; then say "Using manual-paste OAuth flow (remote/SSH session detected)."; fi
  authed "openai-codex" || auth_add_oauth "openai-codex" "${AUTH_ARGS[@]}" || \
    warn "Codex OAuth failed — Dev OS runs on OpenRouter gpt-5.5 (policy-allowed fallback)."
  say "Grok login (web search) — SuperGrok / Premium+ account."
  authed "xai" || auth_add_oauth "xai-oauth" "${AUTH_ARGS[@]}" || \
    warn "Grok OAuth failed — web search stays off until xAI creds exist (or: hermes auth add xai --type api-key)."
fi

# 2) Coordinator profile (idempotent)
hermes profile list 2>/dev/null | grep -q "\b$PROFILE\b" && say "profile '$PROFILE' exists" || { say "creating '$PROFILE'"; hermes profile create "$PROFILE" || true; }
cfg(){ hermes --profile "$PROFILE" config set "$1" "$2" >/dev/null 2>&1 && echo "  set $1=$2" || warn "could not set $1"; }

# 3) Model policy — Codex if authed, else OpenRouter gpt-5.5 (directive-sanctioned fallback)
if authed "openai-codex"; then
  say "Codex authed → primary = Codex"; cfg model.provider openai-codex
else
  warn "Codex not authed → primary = OpenRouter gpt-5.5 (allowed). Re-run after 'hermes auth add openai-codex --type oauth'."
  cfg model.provider openrouter; cfg model.default openai/gpt-5.5; cfg model.base_url https://openrouter.ai/api/v1
fi
say "Add the recommended fallbacks (interactive picker):"
echo "    hermes --profile $PROFILE fallback add   # → openai/gpt-5.5, then deepseek/deepseek-v4-flash"

# 4) Grok web search
cfg x_search.model grok-4.20-reasoning      # quick. Deep research: set to grok-4.3 per run.
hermes --profile "$PROFILE" tools enable x_search >/dev/null 2>&1 && echo "  enabled x_search" || warn "enable x_search after Grok auth: hermes --profile $PROFILE tools enable x_search"

# 5) Propagate OpenRouter key to the profile (no secret printed)
if [ -f "$HOME_DIR/.env" ]; then
  while IFS= read -r line; do case "$line" in OPENROUTER*) v="${line%%=*}"; pe="$HOME_DIR/profiles/$PROFILE/.env"; [ -d "${pe%/*}" ] && { touch "$pe"; grep -q "^$v=" "$pe" 2>/dev/null || printf '%s\n' "$line" >> "$pe"; };; esac; done < "$HOME_DIR/.env"
  echo "  propagated OPENROUTER_* to $PROFILE"
fi

cat <<DONE

✅ Dev OS '$PROFILE' configured (see DEVOS.md).
   Main: Codex (or OpenRouter gpt-5.5) · Search: Grok x_search · Gateway: Discord · No Claude/Gemini
Next:
  hermes --profile $PROFILE fallback add        # add gpt-5.5 + deepseek/deepseek-v4-flash
  hermes gateway start                          # talk to it on Discord
  hermes --profile $PROFILE -z "ping"           # smoke test
DONE
