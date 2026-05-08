# Builder Workspace — All-in-One
# VS Code (code-server) + OpenCode + Claude Code + Qovery CLI + Node.js + Python + Git
# Non-tech builders use the VS Code UI; tech builders open the terminal and run opencode or claude.
FROM codercom/code-server:4.99.4

USER root

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git jq python3 python3-pip python3-venv unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Qovery Skills
RUN curl -fsSL https://skill.qovery.com/install.sh | bash

# Claude Code (AI coding agent — available in the integrated terminal)
RUN npm install -g @anthropic-ai/claude-code 2>/dev/null || true

# OpenCode (AI coding agent — available in the integrated terminal)
RUN curl -fsSL https://opencode.ai/install.sh | bash 2>/dev/null || true

# VS Code extensions
RUN code-server --install-extension github.copilot 2>/dev/null || true \
    && code-server --install-extension ms-python.python 2>/dev/null || true \
    && code-server --install-extension bradlc.vscode-tailwindcss 2>/dev/null || true \
    && code-server --install-extension esbenp.prettier-vscode 2>/dev/null || true

# Configure code-server (no auth — Qovery handles access control)
RUN mkdir -p /home/coder/.config/code-server \
    && printf 'bind-addr: 0.0.0.0:8080\nauth: none\ncert: false\n' \
       > /home/coder/.config/code-server/config.yaml

RUN chown -R coder:coder /home/coder

USER coder
WORKDIR /home/coder/project

EXPOSE 8080

ENTRYPOINT ["code-server", "--host", "0.0.0.0", "--port", "8080"]
