# Builder Workspace — All-in-One
# VS Code (code-server) + OpenCode + Claude Code + RTK + GitHub CLI + Qovery CLI
# + Node.js + Python + Git
#
# Non-tech builders use the VS Code UI; tech builders open the integrated
# terminal and run `opencode` or `claude`. RTK auto-compresses shell output
# to reduce LLM token consumption by 60-90%.
FROM codercom/code-server:4.99.4

USER root

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git jq make python3 python3-pip python3-venv unzip xz-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (pinned + checksum verified)
ARG GH_VERSION=2.74.1
ARG GH_SHA256=d62406233a42e0dc577dcead8d7bafabcc4c548d9c3a6da761c6709bc8f4b373
RUN cd /tmp \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o gh.tar.gz \
    && echo "${GH_SHA256}  gh.tar.gz" | sha256sum -c - \
    && tar -xzf gh.tar.gz \
    && install "gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf gh.tar.gz "gh_${GH_VERSION}_linux_amd64"

# Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Qovery Skills (deploy, troubleshoot, optimize, etc.)
RUN curl -fsSL https://skill.qovery.com/install.sh | bash

# Claude Code (pinned version)
ARG CLAUDE_CODE_VERSION=2.1.129
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# OpenCode (AI coding agent)
RUN npm install -g opencode-ai

# RTK — reduces LLM token consumption by 60-90% on shell commands
# Pre-built binary from GitHub releases (single binary, zero dependencies)
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    && ln -sf /root/.local/bin/rtk /usr/local/bin/rtk

# VS Code extensions
RUN code-server --install-extension github.copilot 2>/dev/null || true \
    && code-server --install-extension ms-python.python 2>/dev/null || true \
    && code-server --install-extension bradlc.vscode-tailwindcss 2>/dev/null || true \
    && code-server --install-extension esbenp.prettier-vscode 2>/dev/null || true

# Configure code-server (no auth — Qovery handles access control)
RUN mkdir -p /home/coder/.config/code-server \
    && printf 'bind-addr: 0.0.0.0:8080\nauth: none\ncert: false\n' \
       > /home/coder/.config/code-server/config.yaml

# Git credential helper (uses $GITHUB_TOKEN env var for private repos)
USER coder
RUN git config --global credential.helper \
      '!f() { echo "username=x-access-token"; echo "password=${GITHUB_TOKEN}"; }; f'

# Initialize RTK hooks for Claude Code and OpenCode (auto-rewrite shell commands)
RUN rtk init -g 2>/dev/null || true \
    && rtk init -g --opencode 2>/dev/null || true

USER root
RUN chown -R coder:coder /home/coder

USER coder
WORKDIR /home/coder/project

EXPOSE 8080

ENTRYPOINT ["code-server", "--host", "0.0.0.0", "--port", "8080"]
