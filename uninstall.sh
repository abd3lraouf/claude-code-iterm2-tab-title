#!/usr/bin/env bash
# Uninstall claude-code-iterm2-tab-title
set -euo pipefail

echo "Uninstalling claude-code-iterm2-tab-title..."

rm -f "$HOME/.claude/scripts/hook.sh"
echo "Removed hook script"

rm -rf /tmp/claude-tab-status
echo "Removed signal files"

rm -f "$HOME/.claude/iterm2-tab-title.log"
echo "Removed log file"

echo ""
echo "Done. Remove the hooks from ~/.claude/settings.json manually."
