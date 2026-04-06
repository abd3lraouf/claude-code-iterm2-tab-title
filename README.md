# Claude Code iTerm2 Tab Title

Smart, contextual iTerm2 tab titles for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions. See what every session is doing at a glance.

## What It Does

Each iTerm2 tab running Claude Code shows a dynamic title combining:

- **Session state** &mdash; running, idle, or needs attention
- **Branch-derived work title** &mdash; parsed from your git branch name
- **Current task name** &mdash; what Claude is actively working on (from TaskCreate)

### Title Examples

| Context | Tab Title |
|---|---|
| Working on a feature branch, task active | `⚡ Share Celebration Callback > Implement Share Dialog [myproject]` |
| Idle on a feature branch | `💤 Share Celebration Callback [myproject]` |
| Needs permission input | `🔴 Share Celebration Callback [myproject]` |
| On main branch, running | `⚡ myproject` |
| Task active, no feature branch | `⚡ Fix CI Pipeline [myproject]` |

### Three States

| State | Prefix | Meaning |
|---|---|---|
| **Running** | ⚡ | Claude is processing |
| **Idle** | 💤 | Claude finished |
| **Attention** | 🔴 | Claude needs permission |

## How It Works

```
Claude Code hooks  -->  hook.sh  -->  escape sequence to TTY  -->  Tab title updates
                                 -->  signal file (optional)
```

A single bash script (`hook.sh`) runs on Claude Code [hook events](https://docs.anthropic.com/en/docs/claude-code/hooks). It discovers the parent TTY and writes an escape sequence directly to it. No Python adapter, no iTerm2 API, no background processes.

### Branch Name Parsing

Branch names are automatically parsed into readable titles:

| Branch | Title |
|---|---|
| `feat/143-share-celebration-callback` | Share Celebration Callback |
| `fix/TW-123-ui-theme-fixes` | Ui Theme Fixes |
| `chore/remove-ads-code` | Remove Ads Code |
| `refactor/cocoapods-consolidation` | Cocoapods Consolidation |
| `main` | *(uses project name)* |

Strips the prefix (`feat/`, `fix/`, `chore/`, `refactor/`), strips leading ticket numbers (`143-`, `TW-123-`), and converts kebab-case to Title Case.

### Task Name Integration

When Claude creates tasks via `TaskCreate`, the tab title updates automatically. When a task is marked `completed`, it clears. No manual intervention needed.

## Requirements

- macOS
- [iTerm2](https://iterm2.com/)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Python 3 (for JSON parsing in the hook)

## Installation

```bash
git clone https://github.com/abd3lraouf/claude-code-iterm2-tab-title.git
cd claude-code-iterm2-tab-title
bash install.sh
```

The installer:
1. Copies `hook.sh` to `~/.claude/scripts/`
2. Merges hooks into `~/.claude/settings.json`

Tab titles start updating on your next Claude Code prompt. No restart needed.

## Uninstall

```bash
bash uninstall.sh
```

Then remove the hooks from `~/.claude/settings.json` manually.

## Architecture

### Hook Events

| Hook | Signal Type | Task Update |
|---|---|---|
| `SessionStart` | idle | &mdash; |
| `UserPromptSubmit` | running | &mdash; |
| `Stop` | idle | &mdash; |
| `Notification` (permission) | attention | &mdash; |
| `PostToolUse` (TaskCreate) | *(preserves current)* | Sets task name |
| `PostToolUse` (TaskUpdate) | *(preserves current)* | Sets/clears task |

### Files

```
~/.claude/scripts/hook.sh          # The single hook script
~/.claude/iterm2-tab-title.log     # Debug log
/tmp/claude-tab-status/*.json      # Signal files (one per session)
```

### Signal Files

Each session writes a JSON signal to `/tmp/claude-tab-status/{session_id}.json`:

```json
{
  "session_id": "ses-abc-123",
  "type": "running",
  "tty": "/dev/ttys011",
  "pid": "53250",
  "branch": "feat/143-share-celebration-callback",
  "project": "myproject",
  "task": "Implement share dialog",
  "cwd": "/Users/me/myproject",
  "ts": "1712444800"
}
```

Signal files are preserved for future use (e.g., an iTerm2 Python adapter for tab flashing and badges).

## Logging

All hook activity is logged to `~/.claude/iterm2-tab-title.log`:

```
01:58:18 EVENT: UserPromptSubmit tool= sid=459c6a50...
01:58:18 CONTEXT: project=myproject branch=fix/151-start-focus-shortcut tty=/dev/ttys002 pid=27343
01:58:18 STATE: type=running task='' update=''
01:58:19 TITLE: '⚡ Start Focus Shortcut [myproject]' -> /dev/ttys002
```

## Troubleshooting

**Tab title not changing** &mdash; Check `~/.claude/iterm2-tab-title.log`. If no log entries, hooks aren't firing. Verify `~/.claude/settings.json` has the hook configuration. If log shows `SKIP TITLE: no writable TTY`, the TTY discovery failed.

**Title resets after a moment** &mdash; Another process (e.g., shell prompt) may be overriding the title. Check your `.zshrc` / `.bashrc` for `PROMPT_COMMAND` or `precmd` that sets the title.

**Wrong project name in worktrees** &mdash; The project name comes from `basename $PWD`. In git worktrees, this is the worktree directory name, not the original repo name.

## Running Tests

```bash
bash tests/test_hook.sh
```

## Acknowledgments

Inspired by [JasperSui/claude-code-iterm2-tab-status](https://github.com/JasperSui/claude-code-iterm2-tab-status).

## License

[GPL-3.0](LICENSE)
