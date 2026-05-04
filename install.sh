#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Qovery Skills — Installer
# Installs all Qovery skills (deploy, troubleshoot, onboard, optimize, speedup, preview).
# Compatible with Claude Code, OpenCode, Cursor, VS Code
# Copilot, Gemini CLI, Roo Code, and 30+ more agent tools.
# https://github.com/Qovery/qovery-skills
# ============================================================

SKILLS=("qovery-onboard" "qovery-deploy" "qovery-troubleshoot" "qovery-optimize" "qovery-speedup" "qovery-preview")
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
${BOLD}Qovery Skills — Installer${NC}

Installs all Qovery skills.

Usage:
  install.sh [OPTIONS]

Options:
  --global      Install globally (default) — available in all projects
  --project     Install in the current project directory only
  --uninstall   Remove all Qovery skills from all known locations
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

# Determine target base directories (without skill name)
get_base_dirs() {
  local mode="$1"
  if [ "$mode" = "global" ]; then
    echo "$HOME/.claude/skills"
    echo "$HOME/.config/opencode/skills"
    echo "$HOME/.agents/skills"
  elif [ "$mode" = "project" ]; then
    echo ".claude/skills"
    echo ".opencode/skills"
    echo ".agents/skills"
  fi
}

# Uninstall
if [ "$MODE" = "uninstall" ]; then
  echo -e "${BOLD}Uninstalling Qovery skills...${NC}"
  echo ""
  found=0

  # Check all possible locations (both global and project) for all skills
  BASE_PATHS=(
    "$HOME/.claude/skills"
    "$HOME/.config/opencode/skills"
    "$HOME/.agents/skills"
    ".claude/skills"
    ".opencode/skills"
    ".agents/skills"
  )

  for base in "${BASE_PATHS[@]}"; do
    for skill in "${SKILLS[@]}"; do
      target="$base/$skill"
      if [ -f "$target/SKILL.md" ]; then
        rm -rf "$target"
        echo -e "  ${RED}Removed${NC} $target"
        found=1
      fi
    done
  done

  if [ "$found" = "0" ]; then
    echo "  No installations found."
  else
    echo ""
    echo -e "${GREEN}Uninstall complete.${NC}"
  fi
  exit 0
fi

# Install
echo -e "${BOLD}Installing Qovery skills...${NC}"
echo ""

TEMP_DIR=""
cleanup() {
  [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

installed=0

for skill in "${SKILLS[@]}"; do
  echo -e "  ${BLUE}[$skill]${NC}"

  if [ -f "$skill/SKILL.md" ]; then
    # Running from cloned repo
    SOURCE="$skill/SKILL.md"
    echo -e "    Source: local file ($skill/SKILL.md)"
  else
    # Running via curl | bash — download from GitHub
    if [ -z "$TEMP_DIR" ]; then
      TEMP_DIR=$(mktemp -d)
    fi
    SOURCE="$TEMP_DIR/$skill.md"
    echo -e "    Downloading from GitHub..."
    if ! curl -fsSL "$REPO_RAW_URL/$skill/SKILL.md" -o "$SOURCE" 2>/dev/null; then
      echo -e "    ${RED}Error:${NC} Failed to download $skill/SKILL.md"
      echo "    Make sure the repo is public: https://github.com/Qovery/qovery-skills"
      continue
    fi
    echo -e "    ${GREEN}Downloaded${NC} ($(wc -c < "$SOURCE" | tr -d ' ') bytes)"
  fi

  # Install to all target directories
  while IFS= read -r base; do
    target="$base/$skill"
    mkdir -p "$target"
    cp "$SOURCE" "$target/SKILL.md"
    echo -e "    ${GREEN}Installed${NC} $target/SKILL.md"
    installed=$((installed + 1))
  done < <(get_base_dirs "$MODE")

  echo ""
done

# Install slash commands (from skills that have a commands/ directory)
cmd_installed=0
for skill in "${SKILLS[@]}"; do
  CMD_DIR="$skill/commands"
  if [ -d "$CMD_DIR" ]; then
    for cmd_file in "$CMD_DIR"/*.md; do
      [ -f "$cmd_file" ] || continue
      cmd_name=$(basename "$cmd_file" .md)
      while IFS= read -r base; do
        # commands/ lives alongside skills/ in the parent directory
        cmd_target="$(dirname "$base")/commands"
        mkdir -p "$cmd_target"
        cp "$cmd_file" "$cmd_target/$cmd_name.md"
        echo -e "  ${GREEN}Installed${NC} command /$cmd_name -> $cmd_target/$cmd_name.md"
        cmd_installed=$((cmd_installed + 1))
      done < <(get_base_dirs "$MODE")
    done
  fi
done

echo -e "${GREEN}${BOLD}Successfully installed ${#SKILLS[@]} skills to $installed locations.${NC}"
if [ "$cmd_installed" -gt 0 ]; then
  echo -e "${GREEN}${BOLD}Installed $cmd_installed slash command(s).${NC}"
fi
echo ""

if [ "$MODE" = "global" ]; then
  echo -e "Skills are now available ${BOLD}globally${NC} in all your projects."
else
  echo -e "Skills are now available in ${BOLD}this project${NC} only."
fi

echo ""
echo -e "${BOLD}Skills installed:${NC}"
echo -e "  ${YELLOW}qovery-onboard${NC}       — Guided onboarding for new Qovery users"
echo -e "  ${YELLOW}qovery-deploy${NC}        — Deploy any app to Kubernetes with Qovery"
echo -e "  ${YELLOW}qovery-troubleshoot${NC}  — Diagnose and fix deployment issues"
echo -e "  ${YELLOW}qovery-optimize${NC}      — Optimize costs and right-size resources"
echo -e "  ${YELLOW}qovery-speedup${NC}       — Speed up deployments and builds"
echo -e "  ${YELLOW}qovery-preview${NC}       — Create preview environments from PRs"
echo ""
echo -e "${BOLD}Compatible with:${NC}"
echo "  Claude Code, OpenCode, Cursor, VS Code Copilot, Gemini CLI,"
echo "  Roo Code, Goose, Amp, Junie (JetBrains), Kiro, OpenHands,"
echo "  and 20+ more tools supporting the Agent Skills standard."
echo ""
echo -e "${BOLD}Try it:${NC} ask your AI agent:"
echo -e "  ${YELLOW}\"I'm new to Qovery, help me get started\"${NC}"
echo -e "  ${YELLOW}\"deploy my application with Qovery\"${NC}"
echo -e "  ${YELLOW}\"my Qovery deployment is failing, can you help?\"${NC}"
echo -e "  ${YELLOW}\"optimize my Qovery costs\"${NC}"
echo -e "  ${YELLOW}\"my deployments are slow, can you speed them up?\"${NC}"
echo -e "  ${YELLOW}\"create a preview environment for PR-123\"${NC}"
echo ""
echo -e "Documentation: ${BLUE}https://github.com/Qovery/qovery-skills${NC}"
