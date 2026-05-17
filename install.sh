#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Qovery Skills — Installer
# Installs all Qovery skills (deploy, troubleshoot, onboard, optimize, speedup, preview).
# Compatible with Claude Code, OpenCode, Cursor, VS Code
# Copilot, Gemini CLI, Roo Code, and 30+ more agent tools.
# https://github.com/Qovery/qovery-skills
# ============================================================

SKILLS=("qovery" "qovery-onboard" "qovery-deploy" "qovery-troubleshoot" "qovery-optimize" "qovery-speedup" "qovery-preview" "qovery-rde" "qovery-terraform")
TARBALL_URL="https://codeload.github.com/Qovery/qovery-skills/tar.gz/refs/heads/main"

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
      if [ -e "$target/SKILL.md" ] || [ -L "$target" ]; then
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

# Determine source root: either the cloned repo we're running from,
# or a freshly downloaded tarball.
SOURCE_ROOT=""
if [ -f "qovery-deploy/SKILL.md" ]; then
  SOURCE_ROOT="$(pwd)"
  echo -e "  Source: local repo (${BLUE}$SOURCE_ROOT${NC})"
else
  TEMP_DIR=$(mktemp -d)
  echo -e "  Downloading qovery-skills tarball from GitHub..."
  if ! curl -fsSL "$TARBALL_URL" | tar -xz -C "$TEMP_DIR"; then
    echo -e "  ${RED}Error:${NC} Failed to download or extract tarball from $TARBALL_URL"
    echo "  Make sure the repo is public: https://github.com/Qovery/qovery-skills"
    exit 1
  fi
  # The extracted directory is named "qovery-skills-<branch>" — pick the first one
  SOURCE_ROOT="$(find "$TEMP_DIR" -maxdepth 1 -type d -name 'qovery-skills-*' | head -n 1)"
  if [ -z "$SOURCE_ROOT" ] || [ ! -f "$SOURCE_ROOT/qovery-deploy/SKILL.md" ]; then
    echo -e "  ${RED}Error:${NC} Tarball did not contain expected layout"
    exit 1
  fi
  echo -e "  ${GREEN}Downloaded${NC} ($(du -sh "$SOURCE_ROOT" | cut -f1))"
fi

# Determine skill version — commit SHA baked in at install time
if [ -d "$SOURCE_ROOT/.git" ]; then
  # Local repo — use git directly
  SKILLS_VERSION=$(git -C "$SOURCE_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
else
  # Tarball install — fetch latest commit SHA from GitHub API (no jq needed)
  SKILLS_VERSION=$(curl -sf "https://api.github.com/repos/Qovery/qovery-skills/git/ref/heads/main" \
    | sed -n 's/.*"sha": *"\([a-f0-9]*\)".*/\1/p' | head -1 | cut -c1-7)
  SKILLS_VERSION="${SKILLS_VERSION:-unknown}"
fi
echo -e "  Version: ${BLUE}${SKILLS_VERSION}${NC}"
echo ""

# Clean up stale qovery-* skill dirs from previous installs
# (e.g. skills that were renamed or removed from the SKILLS array).
cleaned=0
while IFS= read -r base; do
  for existing in "$base"/qovery-*; do
    [ -e "$existing" ] || [ -L "$existing" ] || continue
    skill_name=$(basename "$existing")
    is_current=0
    for s in "${SKILLS[@]}"; do
      [ "$s" = "$skill_name" ] && { is_current=1; break; }
    done
    if [ "$is_current" = "0" ]; then
      rm -rf "$existing"
      echo -e "  ${RED}Cleaned stale${NC} $existing"
      cleaned=$((cleaned + 1))
    fi
  done
done < <(get_base_dirs "$MODE")
[ "$cleaned" -gt 0 ] && echo ""

installed=0

for skill in "${SKILLS[@]}"; do
  src="$SOURCE_ROOT/$skill"
  if [ ! -f "$src/SKILL.md" ]; then
    echo -e "  ${YELLOW}[$skill]${NC} skipped (not found in source)"
    echo ""
    continue
  fi

  echo -e "  ${BLUE}[$skill]${NC}"

  while IFS= read -r base; do
    target="$base/$skill"
    mkdir -p "$base"
    # Replace any existing install (file, dir, or symlink)
    rm -rf "$target"

    # Copy the whole skill directory EXCEPT the commands/ subdir.
    # commands/<skill>.md is intentionally NOT installed — the slash commands
    # are auto-generated by the agent from each skill's name. See the comment
    # below for the full rationale.
    mkdir -p "$target"
    # shellcheck disable=SC2010
    for entry in "$src"/*; do
      name=$(basename "$entry")
      [ "$name" = "commands" ] && continue
      cp -R "$entry" "$target/$name"
    done

    # Write version file for User-Agent tracking
    echo "$SKILLS_VERSION" > "$target/_version.txt"

    file_count=$(find "$target" -type f | wc -l | tr -d ' ')
    echo -e "    ${GREEN}Installed${NC} $target ($file_count files)"
    installed=$((installed + 1))
  done < <(get_base_dirs "$MODE")

  echo ""
done

# Slash commands (`/qovery-<name>`) are auto-generated by Claude Code and
# OpenCode from each installed skill's frontmatter `name`. We deliberately do
# NOT install the per-skill commands/<skill>.md files: they would be re-scanned
# alongside the skill itself and produce duplicate `/skills` entries — one for
# the skill (long 3rd-person description) and one for the command (short
# imperative description). The `commands/` dirs stay in the repo as reference
# only.

echo -e "${GREEN}${BOLD}Successfully installed ${#SKILLS[@]} skills to $installed locations.${NC}"
echo ""

if [ "$MODE" = "global" ]; then
  echo -e "Skills are now available ${BOLD}globally${NC} in all your projects."
else
  echo -e "Skills are now available in ${BOLD}this project${NC} only."
fi

echo ""
echo -e "${BOLD}Skills installed:${NC}"
echo -e "  ${YELLOW}qovery${NC}               — Route to skills + quick operations"
echo -e "  ${YELLOW}qovery-onboard${NC}       — Guided onboarding for new Qovery users"
echo -e "  ${YELLOW}qovery-deploy${NC}        — Deploy any app to Kubernetes with Qovery"
echo -e "  ${YELLOW}qovery-troubleshoot${NC}  — Diagnose and fix deployment issues"
echo -e "  ${YELLOW}qovery-optimize${NC}      — Optimize costs and right-size resources"
echo -e "  ${YELLOW}qovery-speedup${NC}       — Speed up deployments and builds"
echo -e "  ${YELLOW}qovery-preview${NC}       — Create preview environments from PRs"
echo -e "  ${YELLOW}qovery-rde${NC}           — Set up Remote Development Environments (RDEs)"
echo -e "  ${YELLOW}qovery-terraform${NC}     — Terraformize existing Qovery setups"
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
echo -e "  ${YELLOW}\"set up remote dev environments for my team\"${NC}"
echo ""
echo -e "Documentation: ${BLUE}https://github.com/Qovery/qovery-skills${NC}"
