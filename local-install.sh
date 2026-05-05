#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Qovery Skills — Local Dev Installer (Symlinks)
# Creates symlinks from this repo to the standard skill paths.
# Edits in the repo are instantly available — no re-install needed.
# https://github.com/Qovery/qovery-skills
# ============================================================

SKILLS=("qovery-onboard" "qovery-deploy" "qovery-troubleshoot" "qovery-optimize" "qovery-speedup" "qovery-preview" "qovery-builder-env")
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# Verify we're in the repo
if [ ! -f "$REPO_DIR/qovery-deploy/SKILL.md" ]; then
  echo -e "${RED}Error:${NC} Cannot find qovery-deploy/SKILL.md in $REPO_DIR"
  echo "Make sure this script is in the qovery-skills repo root."
  exit 1
fi

usage() {
  cat <<EOF
${BOLD}Qovery Skills — Local Dev Installer (Symlinks)${NC}

Creates symlinks from this repo to the standard skill installation paths.
Edits in the repo are instantly reflected — no re-install needed.

Usage:
  local-install.sh [OPTIONS]

Options:
  --global      Install globally (default) — available in all projects
  --project     Install in the current project directory only
  --uninstall   Remove all Qovery skill symlinks from all known locations
  --help        Show this help message

Examples:
  # Symlink globally (recommended for development)
  ./local-install.sh

  # Symlink in current project only
  ./local-install.sh --project

  # Remove all symlinks
  ./local-install.sh --uninstall
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

# Helper: remove an existing target (symlink, file, or directory)
# Returns 0 if something was removed, 1 if nothing existed
remove_existing() {
  local target="$1"
  if [ -L "$target" ]; then
    rm "$target"
    return 0
  elif [ -e "$target" ]; then
    echo -e "    ${YELLOW}Warning:${NC} $target exists and is not a symlink — replacing it"
    rm -rf "$target"
    return 0
  fi
  return 1
}

# Uninstall
if [ "$MODE" = "uninstall" ]; then
  echo -e "${BOLD}Removing Qovery skill symlinks...${NC}"
  echo ""
  found=0

  BASE_PATHS=(
    "$HOME/.claude/skills"
    "$HOME/.config/opencode/skills"
    "$HOME/.agents/skills"
    ".claude/skills"
    ".opencode/skills"
    ".agents/skills"
  )

  CMD_PATHS=(
    "$HOME/.claude/commands"
    "$HOME/.config/opencode/commands"
    "$HOME/.agents/commands"
    ".claude/commands"
    ".opencode/commands"
    ".agents/commands"
  )

  # Remove skill symlinks
  for base in "${BASE_PATHS[@]}"; do
    for skill in "${SKILLS[@]}"; do
      target="$base/$skill"
      if [ -L "$target" ]; then
        rm "$target"
        echo -e "  ${RED}Removed symlink${NC} $target"
        found=1
      elif [ -d "$target" ] && [ -f "$target/SKILL.md" ]; then
        echo -e "  ${YELLOW}Skipped${NC} $target (not a symlink — use install.sh --uninstall to remove copies)"
      fi
    done
  done

  # Remove command symlinks
  for cmd_base in "${CMD_PATHS[@]}"; do
    for skill in "${SKILLS[@]}"; do
      cmd_name="${skill}"
      cmd_target="$cmd_base/$cmd_name.md"
      if [ -L "$cmd_target" ]; then
        rm "$cmd_target"
        echo -e "  ${RED}Removed symlink${NC} $cmd_target"
        found=1
      fi
    done
  done

  if [ "$found" = "0" ]; then
    echo "  No symlinks found."
  else
    echo ""
    echo -e "${GREEN}Uninstall complete.${NC}"
  fi
  exit 0
fi

# Install (symlinks)
echo -e "${BOLD}Installing Qovery skills (symlinks)...${NC}"
echo -e "  Source: ${BLUE}$REPO_DIR${NC}"
echo ""

installed=0

for skill in "${SKILLS[@]}"; do
  skill_source="$REPO_DIR/$skill"

  # Skip skills that don't exist in the repo yet
  if [ ! -f "$skill_source/SKILL.md" ]; then
    echo -e "  ${YELLOW}[$skill]${NC} — skipped (not found in repo)"
    echo ""
    continue
  fi

  echo -e "  ${BLUE}[$skill]${NC}"

  while IFS= read -r base; do
    target="$base/$skill"
    mkdir -p "$base"
    remove_existing "$target" || true
    ln -s "$skill_source" "$target"
    echo -e "    ${GREEN}Linked${NC} $target -> $skill_source"
    installed=$((installed + 1))
  done < <(get_base_dirs "$MODE")

  echo ""
done

# Install slash commands (symlink individual .md files)
cmd_installed=0
for skill in "${SKILLS[@]}"; do
  CMD_DIR="$REPO_DIR/$skill/commands"
  if [ -d "$CMD_DIR" ]; then
    for cmd_file in "$CMD_DIR"/*.md; do
      [ -f "$cmd_file" ] || continue
      cmd_name=$(basename "$cmd_file" .md)

      while IFS= read -r base; do
        cmd_target_dir="$(dirname "$base")/commands"
        cmd_target="$cmd_target_dir/$cmd_name.md"
        mkdir -p "$cmd_target_dir"
        remove_existing "$cmd_target" || true
        ln -s "$cmd_file" "$cmd_target"
        echo -e "  ${GREEN}Linked${NC} /$cmd_name -> $cmd_target"
        cmd_installed=$((cmd_installed + 1))
      done < <(get_base_dirs "$MODE")
    done
  fi
done

echo ""
echo -e "${GREEN}${BOLD}Successfully linked ${#SKILLS[@]} skills to $installed locations.${NC}"
if [ "$cmd_installed" -gt 0 ]; then
  echo -e "${GREEN}${BOLD}Linked $cmd_installed slash command(s).${NC}"
fi
echo ""

if [ "$MODE" = "global" ]; then
  echo -e "Skills are now available ${BOLD}globally${NC} in all your projects."
else
  echo -e "Skills are now available in ${BOLD}this project${NC} only."
fi

echo ""
echo -e "${BOLD}Skills linked:${NC}"
echo -e "  ${YELLOW}qovery-onboard${NC}       — Guided onboarding for new Qovery users"
echo -e "  ${YELLOW}qovery-deploy${NC}        — Deploy any app to Kubernetes with Qovery"
echo -e "  ${YELLOW}qovery-troubleshoot${NC}  — Diagnose and fix deployment issues"
echo -e "  ${YELLOW}qovery-optimize${NC}      — Optimize costs and right-size resources"
echo -e "  ${YELLOW}qovery-speedup${NC}       — Speed up deployments and builds"
echo -e "  ${YELLOW}qovery-preview${NC}       — Create preview environments from PRs"
echo -e "  ${YELLOW}qovery-builder-env${NC}   — Self-service builder environments for non-tech teams"
echo ""
echo -e "${BOLD}Slash commands:${NC}"
echo -e "  ${YELLOW}/qovery-deploy${NC}  ${YELLOW}/qovery-troubleshoot${NC}  ${YELLOW}/qovery-onboard${NC}"
echo -e "  ${YELLOW}/qovery-optimize${NC}  ${YELLOW}/qovery-speedup${NC}  ${YELLOW}/qovery-preview${NC}"
echo ""
echo -e "Changes in ${BLUE}$REPO_DIR${NC} are now ${BOLD}instantly available${NC} — no re-install needed."
echo ""
echo -e "Documentation: ${BLUE}https://github.com/Qovery/qovery-skills${NC}"
