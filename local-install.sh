#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Qovery Skills — Local Dev Installer (Symlinks)
# Creates symlinks from this repo to the standard skill paths.
# Edits in the repo are instantly available — no re-install needed.
# https://github.com/Qovery/qovery-skills
# ============================================================

SKILLS=("qovery" "qovery-onboard" "qovery-deploy" "qovery-troubleshoot" "qovery-optimize" "qovery-speedup" "qovery-preview" "qovery-terraform" "qovery-cluster-ops")
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

  # Remove skill installs created by local-install.sh (legacy whole-dir symlink
  # OR new dir-of-per-entry-symlinks). Anything else is left alone with a hint.
  for base in "${BASE_PATHS[@]}"; do
    for skill in "${SKILLS[@]}"; do
      target="$base/$skill"
      if [ -L "$target" ]; then
        # Legacy: single symlink to the whole skill dir
        rm "$target"
        echo -e "  ${RED}Removed symlink${NC} $target"
        found=1
      elif [ -d "$target" ] && [ -L "$target/SKILL.md" ]; then
        # New layout: dir containing per-entry symlinks
        rm -rf "$target"
        echo -e "  ${RED}Removed symlinked dir${NC} $target"
        found=1
      elif [ -d "$target" ] && [ -f "$target/SKILL.md" ]; then
        echo -e "  ${YELLOW}Skipped${NC} $target (real copy — use install.sh --uninstall to remove)"
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

# Clean up stale qovery-* skill dirs and command symlinks from previous installs
# (e.g. skills that were renamed or removed from the SKILLS array).
cleaned=0
while IFS= read -r base; do
  # Clean stale skill directories
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
  # Clean stale command symlinks (commands/ sits alongside skills/)
  cmd_base="$(dirname "$base")/commands"
  if [ -d "$cmd_base" ]; then
    for cmd_file in "$cmd_base"/qovery-*.md; do
      [ -e "$cmd_file" ] || [ -L "$cmd_file" ] || continue
      cmd_name=$(basename "$cmd_file" .md)
      is_current=0
      for s in "${SKILLS[@]}"; do
        [ "$s" = "$cmd_name" ] && { is_current=1; break; }
      done
      if [ "$is_current" = "0" ]; then
        rm -f "$cmd_file"
        echo -e "  ${RED}Cleaned stale${NC} $cmd_file"
        cleaned=$((cleaned + 1))
      fi
    done
  fi
done < <(get_base_dirs "$MODE")
[ "$cleaned" -gt 0 ] && echo ""

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
    # Per-entry symlinks (skip commands/ — installed separately to commands/
    # alongside skills/, otherwise it gets re-scanned as a sibling skill).
    mkdir -p "$target"
    for entry in "$skill_source"/*; do
      name=$(basename "$entry")
      [ "$name" = "commands" ] && continue
      ln -sf "$entry" "$target/$name"
    done
    echo -e "    ${GREEN}Linked${NC} $target -> $skill_source (commands/ excluded)"
    installed=$((installed + 1))

    # Symlink slash command file into the sibling commands/ directory
    cmd_src="$skill_source/commands/$skill.md"
    if [ -f "$cmd_src" ]; then
      cmd_base="$(dirname "$base")/commands"
      mkdir -p "$cmd_base"
      ln -sf "$cmd_src" "$cmd_base/$skill.md"
      echo -e "    ${GREEN}Linked${NC} $cmd_base/$skill.md"
    fi
  done < <(get_base_dirs "$MODE")

  echo ""
done
echo ""
echo -e "${GREEN}${BOLD}Successfully linked ${#SKILLS[@]} skills to $installed locations.${NC}"
echo ""

if [ "$MODE" = "global" ]; then
  echo -e "Skills are now available ${BOLD}globally${NC} in all your projects."
else
  echo -e "Skills are now available in ${BOLD}this project${NC} only."
fi

echo ""
echo -e "${BOLD}Skills linked:${NC}"
echo -e "  ${YELLOW}qovery${NC}               — Route to skills + quick operations"
echo -e "  ${YELLOW}qovery-onboard${NC}       — Guided onboarding for new Qovery users"
echo -e "  ${YELLOW}qovery-deploy${NC}        — Deploy any app to Kubernetes with Qovery"
echo -e "  ${YELLOW}qovery-troubleshoot${NC}  — Diagnose and fix deployment issues"
echo -e "  ${YELLOW}qovery-optimize${NC}      — Optimize costs and right-size resources"
echo -e "  ${YELLOW}qovery-speedup${NC}       — Speed up deployments and builds"
echo -e "  ${YELLOW}qovery-preview${NC}       — Create preview environments from PRs"
echo -e "  ${YELLOW}qovery-terraform${NC}     — Terraformize existing Qovery setups"
echo ""
echo -e "${BOLD}Slash commands:${NC} /qovery-<skill> (e.g. /qovery-deploy, /qovery-troubleshoot, /qovery-terraform…)."
echo ""
echo -e "Changes in ${BLUE}$REPO_DIR${NC} are now ${BOLD}instantly available${NC} — no re-install needed."
echo ""
echo -e "Documentation: ${BLUE}https://github.com/Qovery/qovery-skills${NC}"
