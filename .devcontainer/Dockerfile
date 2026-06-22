FROM mcr.microsoft.com/devcontainers/base:ubuntu

# 1. Install Claude Code (via npm — the native curl installer's `claude install`
#    step hangs in non-interactive builds). Needs Node, which base:ubuntu lacks.
#    Also install ccusage globally so it's ready on first use — running it via
#    bunx/pnpx/pnpm dlx/nix would fetch on first invocation instead.
USER root
# The base image ships an empty shim at /usr/local/bin/git that shadows the real
# git on PATH (git commands silently no-op); remove it so clones actually work.
RUN rm -f /usr/local/bin/git
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code ccusage \
    # ccusage ships a per-arch native binary that its wrapper tries to chmod on
    # first run — which fails for the non-root user (EPERM). Make it executable
    # now, as root, so it works for everyone with no first-use fixup.
    && find /usr/lib/node_modules/ccusage -path '*@ccusage/*/bin/*' -exec chmod a+rx {} +

# 2. Install Headroom. We deliberately skip the `[all]` extra: it drags in
#    torch + the full NVIDIA CUDA stack (~2-3 GB) that can't run in this
#    no-GPU Linux container. This curated, torch-free set covers proxy, MCP,
#    code/image compression, semantic relevance, agno and langchain. The
#    `memory` and `evals` extras are omitted on purpose — they pull in torch.
RUN pip3 install --no-cache-dir --break-system-packages \
    "headroom-ai[proxy,mcp,code,relevance,image,agno,langchain]"

# Run the rest as the default devcontainer user so config lands in their home.
USER vscode
ENV HOME=/home/vscode

# 2. Bake in the Superpowers plugin (obra/superpowers) so it's active on startup.
#    Claude Code has no non-interactive `/plugin install`, so we clone the plugin
#    into its cache and write the marketplace/installed/enabled config by hand.
ARG SUPERPOWERS_VERSION=6.0.3
ARG SUPERPOWERS_REF=896224c4b1879920ab573417e68fd51d2ccc9072

RUN set -eux; \
    PLUGIN_DIR="${HOME}/.claude/plugins/cache/superpowers-marketplace/superpowers/${SUPERPOWERS_VERSION}"; \
    MP_DIR="${HOME}/.claude/plugins/marketplaces/superpowers-marketplace"; \
    mkdir -p "${PLUGIN_DIR}/.claude-plugin" "${MP_DIR}/.claude-plugin"; \
    git clone https://github.com/obra/superpowers.git /tmp/superpowers; \
    git -C /tmp/superpowers checkout "${SUPERPOWERS_REF}"; \
    # Copy only what the Claude Code plugin runtime needs — skip tests, docs,
    # assets, dev scripts, and other-agent plugin dirs (.codex-plugin, etc.).
    cp -a /tmp/superpowers/.claude-plugin/. "${PLUGIN_DIR}/.claude-plugin/"; \
    cp -a /tmp/superpowers/skills "${PLUGIN_DIR}/"; \
    cp -a /tmp/superpowers/hooks "${PLUGIN_DIR}/"; \
    cp -a /tmp/superpowers/LICENSE "${PLUGIN_DIR}/"; \
    git clone https://github.com/obra/superpowers-marketplace.git /tmp/superpowers-marketplace; \
    cp -a /tmp/superpowers-marketplace/.claude-plugin/marketplace.json "${MP_DIR}/.claude-plugin/"; \
    rm -rf /tmp/superpowers /tmp/superpowers-marketplace

RUN set -eux; \
    PLUGIN_DIR="${HOME}/.claude/plugins/cache/superpowers-marketplace/superpowers/${SUPERPOWERS_VERSION}"; \
    MP_DIR="${HOME}/.claude/plugins/marketplaces/superpowers-marketplace"; \
    TS="2026-06-22T00:00:00.000Z"; \
    printf '%s\n' \
'{' \
'  "superpowers-marketplace": {' \
'    "source": { "source": "github", "repo": "obra/superpowers-marketplace" },' \
"    \"installLocation\": \"${MP_DIR}\"," \
"    \"lastUpdated\": \"${TS}\"" \
'  }' \
'}' > "${HOME}/.claude/plugins/known_marketplaces.json"; \
    printf '%s\n' \
'{' \
'  "version": 2,' \
'  "plugins": {' \
'    "superpowers@superpowers-marketplace": [' \
'      {' \
'        "scope": "user",' \
"        \"installPath\": \"${PLUGIN_DIR}\"," \
"        \"version\": \"${SUPERPOWERS_VERSION}\"," \
"        \"installedAt\": \"${TS}\"," \
"        \"lastUpdated\": \"${TS}\"," \
"        \"gitCommitSha\": \"${SUPERPOWERS_REF}\"" \
'      }' \
'    ]' \
'  }' \
'}' > "${HOME}/.claude/plugins/installed_plugins.json"; \
    printf '%s\n' \
'{' \
'  "enabledPlugins": { "superpowers@superpowers-marketplace": true },' \
'  "extraKnownMarketplaces": {' \
'    "superpowers-marketplace": {' \
'      "source": { "source": "github", "repo": "obra/superpowers-marketplace" }' \
'    }' \
'  }' \
'}' > "${HOME}/.claude/settings.json"

# 4. Install Caveman last, so its installer (`claude plugin install caveman@caveman`)
#    merges into the existing settings.json — it preserves the superpowers entries
#    and adds its own. Runs non-interactively here (no TTY = no prompts).
RUN set -eux; \
    curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash
