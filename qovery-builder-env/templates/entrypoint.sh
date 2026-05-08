#!/bin/bash
# entrypoint.sh — Builder Workspace startup script
# Clones a git repo (if configured), installs dependencies, starts code-server.
#
# Environment variables (all optional — set per-builder in Qovery):
#   GIT_REPO_URL    — HTTPS URL of the repo to clone (e.g., https://github.com/org/project.git)
#   GIT_TOKEN       — Personal access token for git auth (secret). Auto-detects provider.
#   GITHUB_TOKEN    — Fallback token if GIT_TOKEN is not set (GitHub only)
#   GIT_BRANCH      — Branch to checkout (default: main)
#   GIT_USER_NAME   — Git author name for commits
#   GIT_USER_EMAIL  — Git author email for commits
set -e

PROJECT_DIR="/home/coder/project"

# ── Detect git provider from URL and return the correct credential username ──
detect_git_username() {
  local url="$1"
  case "$url" in
    *github.com*)    echo "x-access-token" ;;
    *gitlab.com*|*gitlab.*)  echo "oauth2" ;;
    *bitbucket.org*) echo "x-token-auth" ;;
    *)               echo "x-access-token" ;;
  esac
}

# ── Configure git credentials ───────────────────────────────────────────────
TOKEN="${GIT_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -n "$TOKEN" ]]; then
  GIT_USERNAME=$(detect_git_username "${GIT_REPO_URL:-}")
  git config --global credential.helper \
    '!f() { echo "username='"$GIT_USERNAME"'"; echo "password='"$TOKEN"'"; }; f'
fi

# Git user identity (for commits)
if [[ -n "${GIT_USER_NAME:-}" ]]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# ── Clone or pull project from GIT_REPO_URL ─────────────────────────────────
if [[ -n "${GIT_REPO_URL:-}" ]]; then
  BRANCH="${GIT_BRANCH:-main}"

  if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    # First start — clone the repo
    echo "Cloning $GIT_REPO_URL (branch: $BRANCH)..."
    if git clone --branch "$BRANCH" --single-branch "$GIT_REPO_URL" "$PROJECT_DIR" 2>&1; then
      echo "Clone successful."
    else
      echo "WARNING: Git clone failed. Starting with empty project directory."
    fi
  else
    # Container restart — pull latest changes
    echo "Project already cloned. Pulling latest from $BRANCH..."
    cd "$PROJECT_DIR" && git pull origin "$BRANCH" 2>&1 || echo "WARNING: Git pull failed (non-critical)."
  fi

  # Auto-install dependencies
  if [[ -f "$PROJECT_DIR/package.json" && ! -d "$PROJECT_DIR/node_modules" ]]; then
    echo "Installing Node.js dependencies..."
    cd "$PROJECT_DIR" && npm install 2>&1 || echo "WARNING: npm install failed (non-critical)."
  fi

  if [[ -f "$PROJECT_DIR/requirements.txt" ]]; then
    echo "Installing Python dependencies..."
    cd "$PROJECT_DIR" && pip install --user -r requirements.txt 2>&1 || echo "WARNING: pip install failed (non-critical)."
  fi
fi

# ── Start code-server ────────────────────────────────────────────────────────
echo "Starting Builder Workspace..."
exec code-server --host 0.0.0.0 --port 8080 "$PROJECT_DIR"
