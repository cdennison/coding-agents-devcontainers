#!/usr/bin/env bash
#
# Build the devcontainer image locally, smoke-test it, and (on success) push it
# to the registry.
#
# Usage:
#   scripts/build-and-deploy.sh              # build + test locally, then push
#   scripts/build-and-deploy.sh --no-push    # build + test only (no push)
#   IMAGE=ghcr.io/you/img:tag scripts/build-and-deploy.sh
#
# On success it leaves a long-lived container running and prints the
# `docker exec` command to use for the next step. Claude Code auth is stored in
# a named volume, so you only have to `claude login` once: the credentials
# survive across container restarts and rebuilds.
#
# Requires: docker, and the devcontainer CLI (npm i -g @devcontainers/cli).
# Pushing requires you to be logged in to the registry (e.g. `docker login ghcr.io`).

set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/cdennison/coding-agents-devcontainers:latest}"
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_NAME="${CONTAINER_NAME:-coding-agents-dev}"
CLAUDE_VOLUME="${CLAUDE_VOLUME:-coding-agents-claude-home}"
PUSH=true
[[ "${1:-}" == "--no-push" ]] && PUSH=false

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$1" >&2; exit 1; }

command -v docker >/dev/null       || fail "docker not found"
command -v devcontainer >/dev/null || fail "devcontainer CLI not found (npm i -g @devcontainers/cli)"

step "Building image locally: ${IMAGE}"
devcontainer build --workspace-folder "${WORKSPACE}" --image-name "${IMAGE}" \
  || fail "image build failed"

step "Smoke-testing image as the non-root 'vscode' user"
docker run --rm -u vscode -e HOME=/home/vscode "${IMAGE}" bash -lc '
  set -e
  fail() { echo "  ✗ $1"; exit 1; }
  ok()   { echo "  ✓ $1"; }

  command -v claude   >/dev/null || fail "claude not on PATH";   ok "claude:   $(claude --version 2>&1 | head -1)"
  command -v headroom >/dev/null || fail "headroom not on PATH"; ok "headroom: $(headroom --version 2>&1 | head -1)"
  command -v ccusage  >/dev/null || fail "ccusage not on PATH"
  ccusage daily >/dev/null 2>&1  || fail "ccusage failed to run (first-use binary issue?)"
  ok "ccusage:  $(ccusage --version 2>&1 | head -1)"

  # headroom must be torch-free (CUDA wheels cannot run here)
  if pip3 list 2>/dev/null | grep -qi "^torch "; then fail "torch present — image bloated with unusable CUDA"; fi
  ok "headroom is torch-free"

  S=~/.claude/settings.json
  grep -q "superpowers@superpowers-marketplace" "$S" || fail "superpowers plugin not enabled"; ok "superpowers enabled"
  grep -q "caveman@caveman"                     "$S" || fail "caveman plugin not enabled";     ok "caveman enabled"
  [ "$(ls ~/.claude/plugins/cache/superpowers-marketplace/superpowers/*/skills | wc -l)" -gt 0 ] \
    || fail "no superpowers skills found"; ok "superpowers skills present"
' || fail "smoke tests failed"

step "Smoke tests passed ✅"

if [[ "${PUSH}" == "true" ]]; then
  step "Pushing image: ${IMAGE}"
  devcontainer build --workspace-folder "${WORKSPACE}" --image-name "${IMAGE}" --push true \
    || fail "push failed (are you logged in? e.g. docker login ghcr.io)"
  step "Pushed ${IMAGE} ✅"
else
  step "Skipping push (--no-push)"
fi

# Leave a long-lived container running so you can exec in and test interactively.
# The named volume keeps /home/vscode/.claude (including the login token) so you
# don't have to re-authenticate Claude Code every time.
step "Starting container '${CONTAINER_NAME}' for interactive testing"
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
docker run -d --name "${CONTAINER_NAME}" \
  -u vscode -e HOME=/home/vscode \
  -v "${CLAUDE_VOLUME}:/home/vscode/.claude" \
  -v "${WORKSPACE}:/workspaces/$(basename "${WORKSPACE}")" \
  -w "/workspaces/$(basename "${WORKSPACE}")" \
  "${IMAGE}" sleep infinity >/dev/null \
  || fail "could not start test container"

printf '\n\033[1;32mNext step — exec in and test:\033[0m\n\n'
printf '    docker exec -it %s bash\n\n' "${CONTAINER_NAME}"
printf 'Then run `claude` (login persists in the \047%s\047 volume, so only once).\n' "${CLAUDE_VOLUME}"
printf 'Tear down with:  docker rm -f %s\n' "${CONTAINER_NAME}"
