#!/usr/bin/env bash
# Upgrade dev-os agent profiles and runners to latest from GitHub.
#   DEV_OS_DIR=<path> scripts/upgrade.sh
# Idempotent — safe to re-run.
set -euo pipefail

INSTALL_DIR="${DEV_OS_DIR:-${DEV_OS_STACK_DIR:-/opt/dev-os}}"
echo "dev-os upgrade: $INSTALL_DIR"

if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "no git checkout at $INSTALL_DIR — cloning"
  git clone https://github.com/must-mohsin1/dev-os "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
git fetch --tags --force
# If DEVCREW_VERSION given, checkout that tag; otherwise latest main
if [ -n "${DEVCREW_VERSION:-}" ]; then
  echo "pinning to version ${DEVCREW_VERSION}"
  git checkout "v${DEVCREW_VERSION#v}" 2>/dev/null || git checkout "${DEVCREW_VERSION}"
else
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
    git pull --ff-only origin "$CURRENT_BRANCH"
  else
    # Detached HEAD or named branch — rebase
    git pull --ff-only origin main 2>/dev/null || git pull --ff-only origin master 2>/dev/null || true
  fi
fi

# Re-run install to update agent profiles (idempotent — preserves keys + memory)
bash install.sh --yes --skip-oauth 2>&1 || echo "install.sh completed with warnings"

# Update the runner symlinks
chmod +x devos-run devos-improve 2>/dev/null || true
[ -d "$HOME/.local/bin" ] && {
  ln -sf "$INSTALL_DIR/devos-run" "$HOME/.local/bin/devos-run"
  ln -sf "$INSTALL_DIR/devos-improve" "$HOME/.local/bin/devos-improve"
}

# Propagate doctrine seeds (global tree + stray profiles + categorized duplicates)
bash "$INSTALL_DIR/scripts/sync-doctrine.sh" || echo "sync-doctrine completed with warnings"

echo "dev-os upgrade: done ($(cat VERSION 2>/dev/null || echo unknown))"