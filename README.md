# coding-agents-devcontainers

A pre-built, security-scanned devcontainer for running coding agents like
**Claude Code** and **Codex** — with one command.

## The problem

Getting a coding agent productive on a new machine is more work than it looks:

- **Install sprawl.** The agent CLI is the easy part. You also need the right
  Node/Python/Go toolchains, a package manager, `git`, `ripgrep`, `fzf`, build
  essentials, language servers, and whatever the agent shells out to. Miss one
  and you hit cryptic failures mid-task.
- **"Works on my machine."** Versions drift between laptops, CI, and teammates.
  An agent that behaves on one setup breaks on another because the underlying
  tools differ.
- **Config archaeology.** MCP servers, hooks, permissions, API keys, shell
  profiles — every guide assumes a slightly different baseline, and you end up
  stitching together half-working setups.
- **Blast radius.** An autonomous agent with shell access running directly on
  your host can touch anything you can. Most people either lock it down so hard
  it's useless, or run it wide open and hope for the best.
- **Security uncertainty.** Even when you do containerize, you rarely know
  whether the base image and the packages you pulled in are actually safe.

## The fix

## Quick start

From any project directory (assuming it has no `.devcontainer` yet), drop in
ours with one line:

```bash
mkdir -p .devcontainer && printf '{\n  "image": "ghcr.io/cdennison/coding-agents-devcontainers:latest"\n}\n' > .devcontainer/devcontainer.json
```

That's it. The image is pre-built and published, so there's nothing to compile
locally. Now open the folder:

- **VS Code** — "Dev Containers: Reopen in Container"
- **CLI** — `devcontainer up --workspace-folder .` then
  `devcontainer exec --workspace-folder . bash`

You land in a reproducible, isolated workspace where Claude Code and its tools
are already installed and wired up — the same way on every machine.

Want to pin to a fixed version instead of `latest`? Swap the tag (e.g.
`:claude-superpowers-headroom-0.1`) in the `image` field.

## What's in the box

Everything below is installed, wired up, and verified on every build:

- **Claude Code** CLI, pre-installed and on `PATH`
- **[Superpowers](https://github.com/obra/superpowers)** plugin — TDD,
  debugging, and collaboration skills, enabled out of the box (its SessionStart
  hook greets you with "You have superpowers")
- **[Caveman](https://github.com/JuliusBrussee/caveman)** plugin — enabled and
  ready (`caveman mode` / `/caveman`)
- **[Headroom](https://pypi.org/project/headroom-ai/)** — prompt/context
  compression (proxy, MCP, code/image compression, relevance, agno, langchain),
  installed torch-free so there's no unusable multi-GB CUDA payload
- **[ccusage](https://github.com/ryoppippi/ccusage)** — Claude Code usage/cost
  reporting, installed globally so it runs instantly (no first-use download)
- **Node 22** and **Python 3** runtimes
- Runs as the non-root `vscode` user, fully isolated from your host

## The best part: it's been scanned and found secure

The image and its dependencies are scanned for known vulnerabilities, and the
container ships with a sane, least-privilege default configuration. You get a
known-good baseline instead of a pile of packages you have to vet yourself —
so you can hand an agent shell access without holding your breath.

## Technical details

The image is defined in [`.devcontainer/`](.devcontainer/) and built/published
with the [`devcontainer` CLI](https://github.com/devcontainers/cli):

```bash
devcontainer build \
  --workspace-folder . \
  --image-name ghcr.io/cdennison/coding-agents-devcontainers:latest \
  --push true
```

**Base image.** `mcr.microsoft.com/devcontainers/base:ubuntu` — the standard
devcontainer Ubuntu base, which provides the `vscode` non-root user that the
agent and its config run as.

**Claude Code install.** Installed via npm:

```dockerfile
npm install -g @anthropic-ai/claude-code
```

This is the same method the official
[`anthropics/devcontainer-features/claude-code`](https://github.com/anthropics/devcontainer-features/blob/main/src/claude-code/install.sh)
feature uses — npm global install, with Node provisioned from the NodeSource
apt repository. We install it directly in the Dockerfile (rather than via the
feature) so the toolchain is baked into the image layers. Two deliberate
choices:

- **Node 22.x** (current LTS) instead of the feature's Node 18.x (end-of-life).
  The Claude Code package requires Node ≥18, so 22 is both safe and current.
- We do **not** use the `claude.ai/install.sh` curl bootstrap. Its post-install
  `claude install` step ("Checking installation status…") hangs indefinitely in
  a non-interactive Docker build; the npm path is deterministic.

**Superpowers plugin, baked in.** Claude Code has no non-interactive
`/plugin install`, so the [Superpowers](https://github.com/obra/superpowers)
plugin (v6.0.3) is installed at build time by:

1. Cloning the plugin and copying only the runtime parts into the plugin cache
   (`.claude-plugin/`, `skills/`, `hooks/`, `LICENSE`) — tests, docs, dev
   scripts, and other-agent plugin dirs are excluded to keep the image lean.
2. Writing the config Claude Code reads on startup so the plugin is registered
   and enabled with no interactive step:
   `~/.claude/plugins/known_marketplaces.json`,
   `~/.claude/plugins/installed_plugins.json`, and `~/.claude/settings.json`
   (`enabledPlugins`).

**Headroom.** Installed via pip:

```dockerfile
pip3 install --break-system-packages \
  "headroom-ai[proxy,mcp,code,relevance,image,agno,langchain]"
```

We deliberately do **not** use the documented `headroom-ai[all]` extra. `[all]`
(and the `memory` / `evals` extras) pull in `torch` plus the full NVIDIA CUDA
stack — ~2–3 GB of GPU wheels that cannot run in this no-GPU Linux container.
The curated set above is torch-free and still covers the proxy server, MCP,
code/image compression, semantic relevance, agno, and langchain.

**Caveman.** Installed via its official one-liner, as the **last** build step:

```dockerfile
curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash
```

Caveman's installer runs `claude plugin install caveman@caveman` and *merges*
into the existing `~/.claude/settings.json` rather than overwriting it — so it
preserves the Superpowers entries and adds its own. Running it last guarantees
that merge order. It runs non-interactively in the build because there's no TTY
(no prompts).

**ccusage.** Installed globally via npm (`npm install -g ccusage`) rather than
run through `bunx` / `pnpx` / `pnpm dlx` / `nix run`, all of which fetch on
first invocation. ccusage ships a per-architecture native binary whose wrapper
tries to `chmod +x` itself on first run — which fails for the non-root `vscode`
user (`EPERM`). The Dockerfile marks the binary executable at build time (as
root) so `ccusage` works immediately for everyone, with no first-use fixup.

## Building

Use the helper script to build, smoke-test, and publish the image:

```bash
scripts/build-and-deploy.sh            # build + test locally, then push
scripts/build-and-deploy.sh --no-push  # build + test only
```

It builds the image with the `devcontainer` CLI, runs it as the non-root
`vscode` user, and asserts that Claude Code, Headroom, ccusage, and both plugins
are present and working before pushing. Override the target with
`IMAGE=ghcr.io/you/img:tag`. Pushing requires `docker login ghcr.io`.

**Gotcha worth noting.** The base image ships an empty shim at
`/usr/local/bin/git` that shadows the real `git` on `PATH` — `git` commands
silently no-op and exit 0. The Dockerfile removes it (`rm -f
/usr/local/bin/git`) so the plugin clone actually works.
