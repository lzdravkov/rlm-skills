#!/bin/bash
# install.sh — Install RLM skills into Claude Code skills directory
#
# Usage:
#   ./install.sh                          # installs to ~/.claude/skills/ (default)
#   ./install.sh /path/to/project/.claude/skills  # installs to a specific project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/skills"

# Determine target directory
if [ -n "$1" ]; then
    TARGET_DIR="$1"
else
    TARGET_DIR="$HOME/.claude/skills"
fi

echo "Installing RLM skills from: $SOURCE_DIR"
echo "Installing RLM skills to:   $TARGET_DIR"
echo ""

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Copy each rlm-* skill directory
INSTALLED=0
for skill_dir in "$SOURCE_DIR"/rlm-*/; do
    skill_name=$(basename "$skill_dir")
    target_skill="$TARGET_DIR/$skill_name"
    cp -r "$skill_dir" "$target_skill"
    echo "  ✓ $skill_name"
    INSTALLED=$((INSTALLED + 1))
done

# Copy shared directory as rlm-shared
if [ -d "$SOURCE_DIR/shared" ]; then
    cp -r "$SOURCE_DIR/shared" "$TARGET_DIR/rlm-shared"
    echo "  ✓ rlm-shared (error reference)"
    INSTALLED=$((INSTALLED + 1))
fi

# Copy WORKFLOW_GUIDE into a browsable skill-like directory
mkdir -p "$TARGET_DIR/rlm-workflow-guide"
cp "$SOURCE_DIR/WORKFLOW_GUIDE.md" "$TARGET_DIR/rlm-workflow-guide/WORKFLOW_GUIDE.md"
echo "  ✓ rlm-workflow-guide"
INSTALLED=$((INSTALLED + 1))

echo ""
echo "Done. $INSTALLED skill packages installed to: $TARGET_DIR"
echo ""
echo "Restart Claude Code (or start a new session) to pick up the new skills."
