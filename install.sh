#!/usr/bin/env bash
# dev-os installer — one command sets up the whole autonomous agent org.
# Handles prerequisites (Hermes), credentials (Codex + Grok OAuth), the build-team
# dependency (hermes-devcrew), and the 3 dev-os agents.
#
#   curl -fsSL https://raw.githubusercontent.com/must-mohsin1/dev-os/main/install.sh | bash
#   # or, from a clone:  ./install.sh
#
# Flags / env:
#   --yes            auto-accept install prompts (Hermes, devcrew)
#   --skip-oauth     don't run the Codex/Grok logins (set them up later)
#   --manual-paste   pass OAuth callback text manually (browser-only remotes)
#   --with-cron      register the nightly improvement loop (needs DEVOS_IMPROVE_REPO)
#   DEVOS_REPO       git URL to clone when piped (default: the public repo)
set -euo pipefail
DEVOS_REPO="${DEVOS_REPO:-https://github.com/must-mohsin1/dev-os}"
DEVCREW_REPO="${DEVCREW_REPO:-https://github.com/must-mohsin1/hermes-devcrew}"
HERMES_INSTALL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"
HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
YES=0; SKIP_OAUTH=0; WITH_CRON=0; MANUAL_PASTE=0
for a in "${@:-}"; do case "$a" in
  --yes) YES=1 ;; --skip-oauth) SKIP_OAUTH=1 ;; --manual-paste) MANUAL_PASTE=1 ;; --with-cron) WITH_CRON=1 ;;
  -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;; "") ;;
esac; done
say(){ printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
die(){ printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ask(){ [ "$YES" = 1 ] && return 0; [ -e /dev/tty ] || return 1; printf '\033[1;33m? %s [y/N] \033[0m' "$1"; local r; read -r r </dev/tty || r=n; case "$r" in y|Y|yes) return 0;; *) return 1;; esac; }
remote_session(){ [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; }
AUTH_ARGS=()
if [ "$MANUAL_PASTE" = 1 ] || remote_session; then
  AUTH_ARGS+=(--manual-paste)
  say "Using manual-paste OAuth flow (remote/SSH session or --manual-paste was set)."
fi
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

# 0) Prerequisite: Hermes -----------------------------------------------------------------------
if ! command -v hermes >/dev/null 2>&1; then
  if ask "Hermes is not installed. Install it now (NousResearch one-liner)?"; then
    curl -fsSL "$HERMES_INSTALL" | bash || die "Hermes install failed — see https://hermes-agent.nousresearch.com/docs/"
    export PATH="$HOME/.local/bin:$PATH"; command -v hermes >/dev/null 2>&1 || die "Hermes installed but not on PATH — open a new shell and re-run."
  else die "Hermes required. Install: curl -fsSL $HERMES_INSTALL | bash"; fi
fi
say "Hermes: $(hermes --version 2>/dev/null | grep -oE '[0-9.]+' | head -1 || echo present)"
command -v git >/dev/null 2>&1 || die "git is required."

# 1) Locate the package (self-clone when piped via curl|bash) -----------------------------------
SRC=""
[ -n "${BASH_SOURCE:-}" ] && [ -f "${BASH_SOURCE:-}" ] && SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$SRC" ] || [ ! -d "$SRC/agents" ]; then
  TMP="$HOME/.dev-os-src"; say "Fetching $DEVOS_REPO"
  [ -d "$TMP/.git" ] && (cd "$TMP" && git pull --ff-only -q) || git clone -q "$DEVOS_REPO" "$TMP"
  SRC="$TMP"
fi
[ -d "$SRC/agents" ] || die "Could not locate agents/ under $SRC"

# 2) Dependency: hermes-devcrew (the build team) ------------------------------------------------
if command -v devcrew-run >/dev/null 2>&1; then say "build team hermes-devcrew: present"
elif ask "hermes-devcrew (the 9-agent build team) is not installed. Install it now?"; then
  DTMP="$HOME/.hermes-devcrew-src"; [ -d "$DTMP/.git" ] && (cd "$DTMP" && git pull --ff-only -q) || git clone -q "$DEVCREW_REPO" "$DTMP"
  ( cd "$DTMP" && DEVCREW_SKIP_KEYS="${DEVCREW_SKIP_KEYS:-}" ./install.sh ) || warn "devcrew install hit an issue — re-run later: cd $DTMP && ./install.sh"
else warn "Skipping devcrew — devos can research+plan but can't build until it's installed."; fi

# 3) Credentials: Codex + Grok OAuth (interactive) ----------------------------------------------
authed(){ hermes auth list 2>/dev/null | grep -qi "$1"; }
if [ "$SKIP_OAUTH" != 1 ]; then
  authed openai-codex && say "Codex: authed" || {
    say "Codex login (main model) — opens your browser"
    auth_add_oauth "openai-codex" "${AUTH_ARGS[@]}" || warn "Codex login skipped — run later: hermes auth add openai-codex --type oauth ${AUTH_ARGS[*]}"
  }
  authed xai && say "Grok: authed" || {
    say "Grok login (web search) — opens your browser"
    auth_add_oauth "xai-oauth" "${AUTH_ARGS[@]}" || warn "Grok login skipped — run later: hermes auth add xai-oauth --type oauth ${AUTH_ARGS[*]}"
  }
else warn "Skipping OAuth — set up later: hermes auth add openai-codex --type oauth ; hermes auth add xai-oauth --type oauth"; fi

# 4) Install the 3 agents -----------------------------------------------------------------------
for d in "$SRC"/agents/*/; do
  [ -f "$d/distribution.yaml" ] || continue
  name=$(grep -E '^name:' "$d/distribution.yaml" | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '"'"'"' ')
  hermes profile install "$d" --force --yes >/dev/null 2>&1 && say "installed $name" || warn "install failed: $name"
done

# 4b) Shared doctrine skills — fan the repo seed into the three profiles ------------------------
# Seed lives in skills/devops/kanban-worker/. Edit doctrine THERE, never in
# ~/.hermes/profiles/ — this block overwrites profile copies (with a drift
# warning) on every install/upgrade.
if [ -d "$SRC/skills/devops/kanban-worker" ]; then
  for p in devos devos-researcher devos-planner; do
    [ -d "$HOME_DIR/profiles/$p" ] || continue
    pdir="$HOME_DIR/profiles/$p/skills/devops/kanban-worker"
    if [ -f "$pdir/SKILL.md" ] && ! diff -q "$pdir/SKILL.md" "$SRC/skills/devops/kanban-worker/SKILL.md" >/dev/null 2>&1; then
      warn "overwriting drifted skill: $pdir/SKILL.md"
    fi
    mkdir -p "$pdir" && cp -R "$SRC/skills/devops/kanban-worker/." "$pdir/"
    say "skills: $p += kanban-worker (seed)"
  done
fi

# 5) Wire: descriptions, Grok tool, fallback key, runners ---------------------------------------
hermes profile describe devos --text "Dev OS coordinator: routes goals to researcher/planner/devcrew, gates at the plan, tracks the board." >/dev/null 2>&1 || true
hermes profile describe devos-researcher --text "Research specialist: Grok web research with parallel sub-searchers; cited briefs." >/dev/null 2>&1 || true
hermes profile describe devos-planner --text "Planning specialist: goal+brief -> approval-ready specs with checkable acceptance criteria." >/dev/null 2>&1 || true
# Researcher gets the full research stack; devos + planner get the power/recall toolsets.
for t in x_search moa context_engine; do hermes --profile devos-researcher tools enable "$t" >/dev/null 2>&1 || true; done
hermes --profile devos tools enable moa >/dev/null 2>&1 || true
hermes --profile devos-planner tools enable web >/dev/null 2>&1 || true
[ -f "$HOME_DIR/.env" ] && while IFS= read -r line; do case "$line" in OPENROUTER*) v="${line%%=*}"; for p in devos devos-researcher devos-planner; do pe="$HOME_DIR/profiles/$p/.env"; [ -d "${pe%/*}" ] && { touch "$pe"; grep -q "^$v=" "$pe" 2>/dev/null || printf '%s\n' "$line" >> "$pe"; }; done;; esac; done < "$HOME_DIR/.env" || true
chmod +x "$SRC/devos-run" "$SRC/devos-improve" 2>/dev/null || true
[ -d "$HOME/.local/bin" ] && { ln -sf "$SRC/devos-run" "$HOME/.local/bin/devos-run"; ln -sf "$SRC/devos-improve" "$HOME/.local/bin/devos-improve"; say "linked devos-run + devos-improve"; }

# 6) Optional nightly improvement loop ----------------------------------------------------------
if [ "$WITH_CRON" = 1 ] && [ -n "${DEVOS_IMPROVE_REPO:-}" ]; then
  hermes --profile devos cron add "0 3 * * *" "devos-improve $DEVOS_IMPROVE_REPO" >/dev/null 2>&1 && say "nightly improvement loop set for $DEVOS_IMPROVE_REPO" || warn "cron registration failed"
fi

cat <<DONE

✅ dev-os ready.  Agents: devos · devos-researcher · devos-planner   (build team: hermes-devcrew)
   Run:  devos-run "Add OAuth login with tests" /path/to/repo
         devos-improve /path/to/repo
         hermes gateway start          # drive devos from Discord
DONE
