```dockerfile
# Builder Workspace — OpenVSCode Server
# Lighter than code-server, same VS Code experience
FROM gitpod/openvscode-server:latest

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Install Qovery Skills
RUN curl -fsSL https://skill.qovery.com/install.sh | bash

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code 2>/dev/null || true

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install.sh | bash 2>/dev/null || true

USER openvscode-server
WORKDIR /home/workspace/project

EXPOSE 3000

ENTRYPOINT ["/home/.openvscode-server/bin/openvscode-server", "--host", "0.0.0.0", "--port", "3000", "--without-connection-token"]
```
