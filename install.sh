#!/usr/bin/env bash
# Install claude-code-iterm2-tab-title
# Copies hook.sh to ~/.claude/scripts/ and merges hooks into settings.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/scripts"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing claude-code-iterm2-tab-title..."

# Copy hook script
mkdir -p "$DEST"
cp "$SCRIPT_DIR/scripts/hook.sh" "$DEST/hook.sh"
chmod +x "$DEST/hook.sh"

echo "Hook installed to $DEST/hook.sh"

# Merge hooks into settings.json
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

python3 -c "
import json, sys

settings_path = '$SETTINGS'
hooks_path = '$SCRIPT_DIR/hooks.json'

with open(settings_path) as f:
    settings = json.load(f)

with open(hooks_path) as f:
    new_hooks = json.load(f)['hooks']

existing_hooks = settings.get('hooks', {})

for event, entries in new_hooks.items():
    if event not in existing_hooks:
        existing_hooks[event] = entries
    else:
        existing_cmds = set()
        for entry in existing_hooks[event]:
            for h in entry.get('hooks', []):
                existing_cmds.add(h.get('command', ''))
        for entry in entries:
            new_cmds = [h.get('command', '') for h in entry.get('hooks', [])]
            if not any(c in existing_cmds for c in new_cmds):
                existing_hooks[event].append(entry)

settings['hooks'] = existing_hooks

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print('Hooks merged into', settings_path)
"

# Create signal directory
mkdir -p /tmp/claude-tab-status

echo ""
echo "Installation complete!"
echo "Tab titles will update on your next Claude Code prompt."
echo "Log file: ~/.claude/iterm2-tab-title.log"
