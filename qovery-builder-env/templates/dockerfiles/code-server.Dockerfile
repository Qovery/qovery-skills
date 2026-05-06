# Builder Workspace — VS Code Server
# Includes: VS Code, GitHub Copilot, Qovery CLI, Qovery Skills, Node.js, Python, Git
FROM codercom/code-server:4.99.4

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Install Qovery Skills (deploy, troubleshoot, builder-env)
RUN mkdir -p /home/coder/.local/share/code-server/skills \
    && curl -fsSL https://skill.qovery.com/install.sh | bash

# Install Claude Code (AI coding agent)
RUN npm install -g @anthropic-ai/claude-code 2>/dev/null || true

# Install OpenCode (AI coding agent)
RUN curl -fsSL https://opencode.ai/install.sh | bash 2>/dev/null || true

# Pre-install VS Code extensions
RUN code-server --install-extension github.copilot 2>/dev/null || true \
    && code-server --install-extension ms-python.python 2>/dev/null || true \
    && code-server --install-extension bradlc.vscode-tailwindcss 2>/dev/null || true \
    && code-server --install-extension esbenp.prettier-vscode 2>/dev/null || true

# Configure code-server
RUN mkdir -p /home/coder/.config/code-server
COPY <<'EOF' /home/coder/.config/code-server/config.yaml
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF

# Set correct ownership
RUN chown -R coder:coder /home/coder

USER coder
WORKDIR /home/coder/project

EXPOSE 8080

ENTRYPOINT ["code-server", "--host", "0.0.0.0", "--port", "8080"]
```
