#!/usr/bin/env bash
# claude-code-iterm2-tab-title unified hook
# Sets iTerm2 tab title via escape sequences written directly to the TTY.
# Also writes signal files for future use (flash/badge via iTerm2 Python API).
#
# Handles:
#   SessionStart            → type "idle"
#   UserPromptSubmit        → type "running"
#   Stop                    → type "idle"
#   Notification(perm)      → type "attention"
#   PostToolUse(TaskCreate) → merges task name
#   PostToolUse(TaskUpdate) → merges/clears task name
set -euo pipefail

LOG_FILE="$HOME/.claude/iterm2-tab-title.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%H:%M:%S') $1" >> "$LOG_FILE"; }

STATUS_DIR="${CLAUDE_ITERM2_TAB_STATUS_DIR:-/tmp/claude-tab-status}"
mkdir -p "$STATUS_DIR"

# Read all of stdin
INPUT="$(cat)"

# JSON field extraction via python3
extract() {
  local key="$1"
  printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    v = d.get('$key', '')
    print(v if isinstance(v, str) else '', end='')
except: pass
" 2>/dev/null
}

SESSION_ID="$(extract "session_id")"
if [[ -z "$SESSION_ID" ]]; then
  log "SKIP: no session_id"
  exit 0
fi

HOOK_EVENT="$(extract "hook_event_name")"
TOOL_NAME="$(extract "tool_name")"
log "EVENT: $HOOK_EVENT tool=$TOOL_NAME sid=${SESSION_ID:0:8}..."

# --- Determine signal type and task update ---
SIGNAL_TYPE=""
TASK_UPDATE=""
MESSAGE=""

case "$HOOK_EVENT" in
  SessionStart)
    SIGNAL_TYPE="idle"
    ;;
  UserPromptSubmit)
    SIGNAL_TYPE="running"
    ;;
  Stop)
    SIGNAL_TYPE="idle"
    ;;
  Notification)
    NOTIF_TYPE="$(extract "notification_type")"
    case "$NOTIF_TYPE" in
      permission_prompt) SIGNAL_TYPE="attention" ;;
    esac
    MESSAGE="$(extract "message")"
    ;;
  PostToolUse)
    case "$TOOL_NAME" in
      TaskCreate)
        TASK_SUBJECT="$(extract "subject")"
        if [[ -n "$TASK_SUBJECT" ]]; then
          TASK_UPDATE="set:$TASK_SUBJECT"
        fi
        ;;
      TaskUpdate)
        TASK_STATUS="$(extract "status")"
        case "$TASK_STATUS" in
          in_progress)
            TASK_SUBJECT="$(extract "subject")"
            if [[ -n "$TASK_SUBJECT" ]]; then
              TASK_UPDATE="set:$TASK_SUBJECT"
            fi
            ;;
          completed|deleted)
            TASK_UPDATE="clear"
            ;;
        esac
        ;;
    esac
    ;;
esac

# --- Gather context ---
CWD="$(extract "cwd")"
CWD="${CWD:-$PWD}"
PROJECT="$(basename "${CWD:-unknown}")"
BRANCH="$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")"

# Find TTY and stable PID (highest ancestor with same TTY = login shell)
TTY=""
STABLE_PID="$$"
_find_tty_info() {
  local pid="$$"
  local depth=0
  while (( pid > 1 && depth < 15 )); do
    local tty_val
    tty_val="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')" || true
    if [[ -n "$tty_val" && "$tty_val" != "??" && "$tty_val" != "-" ]]; then
      TTY="/dev/$tty_val"
      STABLE_PID="$pid"
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" || break
    depth=$((depth + 1))
  done
}
_find_tty_info

log "CONTEXT: project=$PROJECT branch=$BRANCH tty=$TTY pid=$STABLE_PID"

TS="$(date +%s)"
SIGNAL_FILE="${STATUS_DIR}/${SESSION_ID}.json"

# --- For PostToolUse: merge into existing signal ---
if [[ -z "$SIGNAL_TYPE" && -n "$TASK_UPDATE" && -f "$SIGNAL_FILE" ]]; then
  SIGNAL_TYPE="$(python3 -c "import json; print(json.load(open('$SIGNAL_FILE')).get('type','idle'),end='')" 2>/dev/null)"
  SIGNAL_TYPE="${SIGNAL_TYPE:-idle}"
fi

# If we still have no signal type, nothing to do
if [[ -z "$SIGNAL_TYPE" ]]; then
  log "SKIP: no signal type to write"
  exit 0
fi

# --- Resolve task field ---
TASK=""
if [[ "$TASK_UPDATE" == clear ]]; then
  TASK=""
elif [[ "$TASK_UPDATE" == set:* ]]; then
  TASK="${TASK_UPDATE#set:}"
elif [[ -f "$SIGNAL_FILE" ]]; then
  TASK="$(python3 -c "import json; print(json.load(open('$SIGNAL_FILE')).get('task',''),end='')" 2>/dev/null)"
fi

log "STATE: type=$SIGNAL_TYPE task='$TASK' update='$TASK_UPDATE'"

# --- Write signal file (atomic via tmp + mv) ---
escape_json() { printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1],end='')" 2>/dev/null; }

S_SID="$(escape_json "$SESSION_ID")"
S_TYPE="$(escape_json "$SIGNAL_TYPE")"
S_MSG="$(escape_json "$MESSAGE")"
S_PROJ="$(escape_json "$PROJECT")"
S_CWD="$(escape_json "$CWD")"
S_TTY="$(escape_json "$TTY")"
S_BRANCH="$(escape_json "$BRANCH")"
S_TASK="$(escape_json "$TASK")"

TMP_SIGNAL="$(mktemp "${STATUS_DIR}/.tmp.XXXXXX")"
cat > "$TMP_SIGNAL" <<SIGNAL
{
  "session_id": "${S_SID}",
  "type": "${S_TYPE}",
  "message": "${S_MSG}",
  "project": "${S_PROJ}",
  "cwd": "${S_CWD}",
  "tty": "${S_TTY}",
  "pid": "${STABLE_PID}",
  "branch": "${S_BRANCH}",
  "task": "${S_TASK}",
  "ts": "${TS}"
}
SIGNAL
mv "$TMP_SIGNAL" "$SIGNAL_FILE"

# =============================================================
# SET iTERM2 TAB TITLE via escape sequence written to TTY
# =============================================================
if [[ -z "$TTY" || ! -w "$TTY" ]]; then
  log "SKIP TITLE: no writable TTY (tty=$TTY)"
  exit 0
fi

# State prefix
case "$SIGNAL_TYPE" in
  running)   PREFIX="⚡" ;;
  idle)      PREFIX="💤" ;;
  attention) PREFIX="🔴" ;;
  *)         PREFIX="●"  ;;
esac

# Parse branch name into readable title
BRANCH_TITLE=""
if [[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "master" && "$BRANCH" != "develop" && "$BRANCH" != "development" ]]; then
  # Strip prefix (feat/, fix/, etc.)
  WORK="${BRANCH#*/}"
  # Strip leading ticket number (143-, TW-123-, etc.)
  WORK="$(echo "$WORK" | sed -E 's/^[A-Z]*-?[0-9]+-//')"
  # kebab-case to Title Case
  BRANCH_TITLE="$(echo "$WORK" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')"
fi

# Title-case the task (preserve acronyms by only uppercasing first letter)
TASK_TITLE=""
if [[ -n "$TASK" ]]; then
  TASK_TITLE="$(echo "$TASK" | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1')"
fi

# Build title: {prefix} {branch_title} > {task} [{project}]
TITLE="$PREFIX"
if [[ -n "$BRANCH_TITLE" ]]; then
  TITLE="$TITLE $BRANCH_TITLE"
  if [[ -n "$TASK_TITLE" ]]; then
    TITLE="$TITLE > $TASK_TITLE"
  fi
elif [[ -n "$TASK_TITLE" ]]; then
  TITLE="$TITLE $TASK_TITLE"
fi

if [[ -n "$BRANCH_TITLE" || -n "$TASK_TITLE" ]]; then
  TITLE="$TITLE [$PROJECT]"
else
  TITLE="$TITLE $PROJECT"
fi

# Write escape sequence to TTY
# \033]1; = set tab title, \007 = bell (terminator)
printf '\033]1;%s\007' "$TITLE" > "$TTY" 2>/dev/null

log "TITLE: '$TITLE' -> $TTY"
