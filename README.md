# Claude Code iTerm2 Tab Title

Smart, contextual iTerm2 tab titles for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions. See what every session is doing at a glance.

## Quick Start

```bash
git clone https://github.com/abd3lraouf/claude-code-iterm2-tab-title.git
cd claude-code-iterm2-tab-title
bash install.sh
```

That's it. Your tab titles start updating on the next Claude Code prompt. No iTerm2 restart needed.

The installer copies one script to `~/.claude/scripts/` and merges hooks into `~/.claude/settings.json` (preserves your existing hooks).

### What You Get Immediately

| Before | After |
|---|---|
| `* Claude Code (node)` | `⚡ Stripe Payment Integration > Add Webhook Handler [noctua-api]` |
| `* Claude Code (node)` | `💤 Recipe Search Filters [noctua-web]` |
| `* Claude Code (node)` | `🔴 Docker Compose Setup [noctua-infra]` |

Three identical tabs become three distinct, scannable labels. No clicking through to find the right one.

### Uninstall

```bash
bash uninstall.sh
```

---

## The Problem

You have six iTerm2 tabs open. Each one says `* Claude Code (node)`. Which tab is working on the checkout flow? Which one is debugging the API? Which one needs your permission to write a file? You have no idea. You click through all of them.

**This fixes that.** Each tab shows what it's actually doing.

## What It Does

Each iTerm2 tab running Claude Code shows a dynamic title combining:

- **Session state** &mdash; is Claude thinking, done, or waiting for you?
- **Branch-derived work title** &mdash; parsed from your git branch name into a readable label
- **Current task name** &mdash; what Claude is actively working on (from TaskCreate)

### Real-World Scenarios

Imagine you're building **Noctua**, a full-stack recipe sharing platform. You have multiple Claude Code sessions open across backend, frontend, and infra:

| Tab | What You See | What's Happening |
|---|---|---|
| 1 | `⚡ Stripe Payment Integration > Add Webhook Handler [noctua-api]` | Claude is implementing the Stripe webhook on the backend |
| 2 | `💤 Recipe Search Filters [noctua-web]` | Claude finished the search UI and is idle |
| 3 | `🔴 Docker Compose Setup [noctua-infra]` | Claude needs permission to write `docker-compose.yml` |
| 4 | `⚡ noctua-api` | Claude is working on main branch, no specific task yet |
| 5 | `💤 Email Verification Flow > Write Integration Tests [noctua-api]` | Tests done, waiting for you to review |

At a glance you know: tab 3 needs you, tabs 1 and 4 are busy, tabs 2 and 5 are done.

### Three States

| State | Prefix | Meaning |
|---|---|---|
| **Running** | ⚡ | Claude is thinking, reading files, writing code |
| **Idle** | 💤 | Claude finished its turn, waiting for your next prompt |
| **Attention** | 🔴 | Claude needs your permission (file write, command, etc.) |

### How Titles Are Built

```
{state} {branch title} > {task name} [{project}]
```

With graceful fallbacks when pieces are missing:

| Branch | Task | Title |
|---|---|---|
| `feat/52-stripe-payment-integration` | `Add Webhook Handler` | `⚡ Stripe Payment Integration > Add Webhook Handler [noctua-api]` |
| `feat/52-stripe-payment-integration` | *(none)* | `💤 Stripe Payment Integration [noctua-api]` |
| `main` | `Fix CORS headers` | `⚡ Fix Cors Headers [noctua-api]` |
| `main` | *(none)* | `💤 noctua-api` |

### Branch Name Parsing

Your branch names are automatically parsed into readable titles:

| Branch | Title |
|---|---|
| `feat/52-stripe-payment-integration` | Stripe Payment Integration |
| `fix/BUG-314-login-redirect-loop` | Login Redirect Loop |
| `chore/upgrade-node-dependencies` | Upgrade Node Dependencies |
| `refactor/extract-auth-middleware` | Extract Auth Middleware |
| `main` / `master` / `develop` | *(uses project folder name)* |

Strips the prefix (`feat/`, `fix/`, `chore/`, `refactor/`), strips leading ticket numbers (`52-`, `BUG-314-`), and converts kebab-case to Title Case.

### Task Name Integration

When Claude creates tasks via `TaskCreate`, the tab title updates automatically:

```
⚡ Stripe Payment Integration [noctua-api]                          # before task
⚡ Stripe Payment Integration > Add Webhook Handler [noctua-api]    # TaskCreate fires
💤 Stripe Payment Integration > Add Webhook Handler [noctua-api]    # Claude finishes
💤 Stripe Payment Integration [noctua-api]                          # task marked completed
```

No manual intervention. The hook watches `TaskCreate` and `TaskUpdate` events.

## Requirements

- macOS
- [iTerm2](https://iterm2.com/)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Python 3 (ships with macOS; used for JSON parsing in the hook)

## How It Works

```
Claude Code hooks  -->  hook.sh  -->  escape sequence to TTY  -->  Tab title updates
                                 -->  signal file (optional)
```

A single bash script (`hook.sh`) runs on Claude Code [hook events](https://docs.anthropic.com/en/docs/claude-code/hooks). It discovers the parent TTY and writes an escape sequence directly to it. No Python adapter, no iTerm2 API, no background processes.

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
~/.claude/scripts/hook.sh          # The single hook script (everything happens here)
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
  "branch": "feat/52-stripe-payment-integration",
  "project": "noctua-api",
  "task": "Add Webhook Handler",
  "cwd": "/Users/me/dev/noctua-api",
  "ts": "1712444800"
}
```

Signal files are preserved for future use (e.g., an iTerm2 Python adapter for tab color flashing and badges).

## Logging

All hook activity is logged to `~/.claude/iterm2-tab-title.log`:

```
14:23:05 EVENT: UserPromptSubmit tool= sid=a3f8b2c1...
14:23:05 CONTEXT: project=noctua-api branch=feat/52-stripe-payment-integration tty=/dev/ttys002 pid=27343
14:23:05 STATE: type=running task='' update=''
14:23:06 TITLE: '⚡ Stripe Payment Integration [noctua-api]' -> /dev/ttys002
```

## Troubleshooting

**Tab title not changing** &mdash; Check `~/.claude/iterm2-tab-title.log`. If no log entries appear after you send a prompt, hooks aren't firing. Verify `~/.claude/settings.json` has the hook configuration. If the log shows `SKIP TITLE: no writable TTY`, the TTY discovery failed.

**Title resets after a moment** &mdash; Your shell prompt may be overriding the tab title. Check your `.zshrc` / `.bashrc` for `PROMPT_COMMAND` or `precmd` functions that set the terminal title.

**Wrong project name in worktrees** &mdash; The project name comes from `basename $PWD`. In git worktrees, this is the worktree directory name, not the original repo name. This is expected.

## Running Tests

```bash
bash tests/test_hook.sh       # 29 tests: signals, events, task merge, title rendering
bash tests/test_install.sh    # 24 tests: fresh install, upgrades, idempotency, round-trip
```

## Acknowledgments

Inspired by [JasperSui/claude-code-iterm2-tab-status](https://github.com/JasperSui/claude-code-iterm2-tab-status).

## License

[GPL-3.0](LICENSE)
