# Builder Workspace — Terminal Only
# Includes: OpenCode, Claude Code, Qovery CLI, web terminal (ttyd)
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

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
    build-essential \
    tmux \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install ttyd (web-based terminal)
RUN curl -fsSL -o /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 \
    && chmod +x /usr/local/bin/ttyd

# Install Qovery CLI
RUN curl -s https://get.qovery.com | bash

# Install Qovery Skills
RUN curl -fsSL https://skill.qovery.com/install.sh | bash

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Install OpenCode
RUN curl -fsSL https://opencode.ai/install.sh | bash

# Create non-root user
RUN useradd -m -s /bin/bash builder
USER builder
WORKDIR /home/builder/project

EXPOSE 8080

# Launch web terminal
ENTRYPOINT ["ttyd", "--port", "8080", "--writable", "bash"]
```
