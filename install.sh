#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Qovery Deploy Skill — Installer
# Compatible with Claude Code, OpenCode, Cursor, VS Code
# Copilot, Gemini CLI, Roo Code, and 30+ more agent tools.
# https://github.com/Qovery/qovery-skills
# ============================================================

SKILL_NAME="qovery-deploy"
REPO_RAW_URL="https://skill.qovery.com"

# Colors (if terminal supports them)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' BLUE='' YELLOW='' RED='' BOLD='' NC=''
fi

usage() {
  cat <<EOF
${BOLD}Qovery Deploy Skill — Installer${NC}

Usage:
  install.sh [OPTIONS]

Options:
  --global      Install globally (default) — available in all projects
  --project     Install in the current project directory only
  --uninstall   Remove the skill from all known locations
  --help        Show this help message

Examples:
  # Install globally (recommended)
  curl -fsSL https://skill.qovery.com/install.sh | bash

  # Install in current project only
  curl -fsSL https://skill.qovery.com/install.sh | bash -s -- --project

  # Uninstall from everywhere
  curl -fsSL https://skill.qovery.com/install.sh | bash -s -- --uninstall
EOF
  exit 0
}

# Parse arguments
MODE="global"
for arg in "$@"; do
  case "$arg" in
    --global)    MODE="global" ;;
    --project)   MODE="project" ;;
    --uninstall) MODE="uninstall" ;;
    --help|-h)   usage ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}"
      echo "Run with --help for usage."
      exit 1
      ;;
  esac
done

# Determine target directories
# We install to ALL compatible paths so the skill is discovered by any tool.
# The file is ~80KB — installing to 3 locations costs nothing.
get_targets() {
  local mode="$1"
  if [ "$mode" = "global" ]; then
    echo "$HOME/.claude/skills/$SKILL_NAME"
    echo "$HOME/.config/opencode/skills/$SKILL_NAME"
    echo "$HOME/.agents/skills/$SKILL_NAME"
  elif [ "$mode" = "project" ]; then
    echo ".claude/skills/$SKILL_NAME"
    echo ".opencode/skills/$SKILL_NAME"
    echo ".agents/skills/$SKILL_NAME"
  fi
}

# Uninstall
if [ "$MODE" = "uninstall" ]; then
  echo -e "${BOLD}Uninstalling ${SKILL_NAME}...${NC}"
  echo ""
  found=0

  # Check all possible locations (both global and project)
  ALL_PATHS=(
    "$HOME/.claude/skills/$SKILL_NAME"
    "$HOME/.config/opencode/skills/$SKILL_NAME"
    "$HOME/.agents/skills/$SKILL_NAME"
    ".claude/skills/$SKILL_NAME"
    ".opencode/skills/$SKILL_NAME"
    ".agents/skills/$SKILL_NAME"
  )

  for target in "${ALL_PATHS[@]}"; do
    if [ -f "$target/SKILL.md" ]; then
      rm -rf "$target"
      echo -e "  ${RED}Removed${NC} $target"
      found=1
    fi
  done

  if [ "$found" = "0" ]; then
    echo "  No installations found."
  else
    echo ""
    echo -e "${GREEN}Uninstall complete.${NC}"
  fi
  exit 0
fi

# Get the SKILL.md content
echo -e "${BOLD}Installing ${SKILL_NAME} skill...${NC}"
echo ""

TEMP_FILE=""
cleanup() {
  [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
}
trap cleanup EXIT

if [ -f "qovery-deploy/SKILL.md" ]; then
  # Running from cloned repo
  SOURCE="qovery-deploy/SKILL.md"
  echo -e "  ${BLUE}Source:${NC} local file (qovery-deploy/SKILL.md)"
else
  # Running via curl | bash — download from GitHub
  TEMP_FILE=$(mktemp)
  SOURCE="$TEMP_FILE"
  echo -e "  ${BLUE}Downloading${NC} from GitHub..."
  if ! curl -fsSL "$REPO_RAW_URL/qovery-deploy/SKILL.md" -o "$SOURCE" 2>/dev/null; then
    echo -e "  ${RED}Error:${NC} Failed to download SKILL.md from GitHub."
    echo "  Make sure the repo is public or you have access: https://github.com/Qovery/qovery-skills"
    exit 1
  fi
  echo -e "  ${GREEN}Downloaded${NC} SKILL.md ($(wc -c < "$SOURCE" | tr -d ' ') bytes)"
fi

echo ""

# Install to all target directories
installed=0
while IFS= read -r target; do
  mkdir -p "$target"
  cp "$SOURCE" "$target/SKILL.md"
  echo -e "  ${GREEN}Installed${NC} $target/SKILL.md"
  installed=$((installed + 1))
done < <(get_targets "$MODE")

echo ""
echo -e "${GREEN}${BOLD}Successfully installed to $installed locations.${NC}"
echo ""

if [ "$MODE" = "global" ]; then
  echo -e "The skill is now available ${BOLD}globally${NC} in all your projects."
else
  echo -e "The skill is now available in ${BOLD}this project${NC} only."
fi

echo ""
echo -e "${BOLD}Compatible with:${NC}"
echo "  Claude Code, OpenCode, Cursor, VS Code Copilot, Gemini CLI,"
echo "  Roo Code, Goose, Amp, Junie (JetBrains), Kiro, OpenHands,"
echo "  and 20+ more tools supporting the Agent Skills standard."
echo ""
echo -e "${BOLD}Try it:${NC} ask your AI agent:"
echo -e "  ${YELLOW}\"deploy my application with Qovery\"${NC}"
echo ""
echo -e "Documentation: ${BLUE}https://github.com/Qovery/qovery-skills${NC}"
