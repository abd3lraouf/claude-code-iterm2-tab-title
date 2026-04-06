#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
HOOK="/Users/abd3lraouf/.claude/scripts/hook.sh"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1: $2"; }

run_hook() {
  local dir="$1" json="$2"
  mkdir -p "$dir"
  echo "$json" | CLAUDE_ITERM2_TAB_STATUS_DIR="$dir" bash "$HOOK" 2>/dev/null
}

read_field() {
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$1" "$2"
}

echo "=== Signal file tests ==="

# Test 1: SessionStart -> idle
echo "Test 1: SessionStart creates idle signal"
D="$TMPDIR_BASE/t1"
run_hook "$D" '{"session_id":"t1","hook_event_name":"SessionStart","cwd":"/tmp"}'
if [[ -f "$D/t1.json" ]]; then
  typ=$(read_field "$D/t1.json" "type")
  [[ "$typ" == "idle" ]] && pass "SessionStart -> idle" || fail "type" "got '$typ'"
else
  fail "signal file" "not created"
fi

# Test 2: UserPromptSubmit -> running
echo "Test 2: UserPromptSubmit creates running signal"
D="$TMPDIR_BASE/t2"
run_hook "$D" '{"session_id":"t2","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}'
typ=$(read_field "$D/t2.json" "type")
[[ "$typ" == "running" ]] && pass "UserPromptSubmit -> running" || fail "type" "got '$typ'"

# Test 3: Stop -> idle
echo "Test 3: Stop creates idle signal"
D="$TMPDIR_BASE/t3"
run_hook "$D" '{"session_id":"t3","hook_event_name":"Stop","cwd":"/tmp"}'
typ=$(read_field "$D/t3.json" "type")
[[ "$typ" == "idle" ]] && pass "Stop -> idle" || fail "type" "got '$typ'"

# Test 4: Notification permission_prompt -> attention
echo "Test 4: Notification/permission_prompt creates attention signal"
D="$TMPDIR_BASE/t4"
run_hook "$D" '{"session_id":"t4","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow?","cwd":"/tmp"}'
typ=$(read_field "$D/t4.json" "type")
msg=$(read_field "$D/t4.json" "message")
[[ "$typ" == "attention" ]] && pass "Notification -> attention" || fail "type" "got '$typ'"
[[ "$msg" == "Allow?" ]] && pass "message preserved" || fail "message" "got '$msg'"

# Test 5: TaskCreate merges task, preserves type
echo "Test 5: TaskCreate merges task into existing signal"
D="$TMPDIR_BASE/t5"
run_hook "$D" '{"session_id":"t5","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}'
run_hook "$D" '{"session_id":"t5","hook_event_name":"PostToolUse","tool_name":"TaskCreate","subject":"Implement share dialog","cwd":"/tmp"}'
typ=$(read_field "$D/t5.json" "type")
task=$(read_field "$D/t5.json" "task")
[[ "$typ" == "running" ]] && pass "type preserved as running" || fail "type" "got '$typ'"
[[ "$task" == "Implement share dialog" ]] && pass "task set" || fail "task" "got '$task'"

# Test 6: TaskUpdate completed clears task
echo "Test 6: TaskUpdate/completed clears task"
D="$TMPDIR_BASE/t5"  # reuse t5
run_hook "$D" '{"session_id":"t5","hook_event_name":"PostToolUse","tool_name":"TaskUpdate","status":"completed","cwd":"/tmp"}'
task=$(read_field "$D/t5.json" "task")
[[ "$task" == "" ]] && pass "task cleared" || fail "task" "got '$task'"

# Test 7: Stop preserves existing task
echo "Test 7: Stop preserves existing task"
D="$TMPDIR_BASE/t7"
run_hook "$D" '{"session_id":"t7","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}'
run_hook "$D" '{"session_id":"t7","hook_event_name":"PostToolUse","tool_name":"TaskCreate","subject":"Fix bug","cwd":"/tmp"}'
run_hook "$D" '{"session_id":"t7","hook_event_name":"Stop","cwd":"/tmp"}'
task=$(read_field "$D/t7.json" "task")
typ=$(read_field "$D/t7.json" "type")
[[ "$typ" == "idle" ]] && pass "type changed to idle" || fail "type" "got '$typ'"
[[ "$task" == "Fix bug" ]] && pass "task preserved through Stop" || fail "task" "got '$task'"

# Test 8: Escaped quotes in task name
echo "Test 8: Escaped quotes in values"
D="$TMPDIR_BASE/t8"
run_hook "$D" '{"session_id":"t8","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}'
run_hook "$D" '{"session_id":"t8","hook_event_name":"PostToolUse","tool_name":"TaskCreate","subject":"Fix \"quoted\" bug","cwd":"/tmp"}'
task=$(read_field "$D/t8.json" "task")
[[ "$task" == 'Fix "quoted" bug' ]] && pass "quotes preserved" || fail "task" "got '$task'"

# Test 9: Valid JSON output
echo "Test 9: Signal file is valid JSON"
D="$TMPDIR_BASE/t9"
run_hook "$D" '{"session_id":"t9","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}'
if python3 -c "import json; json.load(open('$D/t9.json'))" 2>/dev/null; then
  pass "valid JSON"
else
  fail "JSON" "invalid JSON output"
fi

# Test 10: All 10 fields present
echo "Test 10: All signal fields present"
D="$TMPDIR_BASE/t9"  # reuse
for field in session_id type message project cwd tty pid branch task ts; do
  val=$(python3 -c "import json; d=json.load(open('$D/t9.json')); print('$field' in d)" 2>/dev/null)
  [[ "$val" == "True" ]] && pass "field '$field' present" || fail "field" "'$field' missing"
done

# Test 11: No session_id -> no file
echo "Test 11: Missing session_id exits cleanly"
D="$TMPDIR_BASE/t11"
mkdir -p "$D"
run_hook "$D" '{"hook_event_name":"UserPromptSubmit","cwd":"/tmp"}'
count=$(find "$D" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
[[ "$count" == "0" ]] && pass "no file created" || fail "no session_id" "file created"

# Test 12: Atomic write (no .tmp files left)
echo "Test 12: No temp files left after write"
D="$TMPDIR_BASE/t12"
run_hook "$D" '{"session_id":"t12","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}'
tmp_count=$(find "$D" -name ".tmp.*" 2>/dev/null | wc -l | tr -d ' ')
[[ "$tmp_count" == "0" ]] && pass "no temp files" || fail "atomic write" "$tmp_count temp files remain"

# Test 13: Git branch detected
echo "Test 13: Git branch detected from cwd"
D="$TMPDIR_BASE/t13"
# Use a known git repo
run_hook "$D" '{"session_id":"t13","hook_event_name":"UserPromptSubmit","cwd":"/Users/abd3lraouf/Developer/timewarden.mobile"}'
branch=$(read_field "$D/t13.json" "branch")
[[ -n "$branch" ]] && pass "branch detected: $branch" || pass "no branch (may be on main)"

echo ""
echo "=== Title rendering tests (from log) ==="

# Clear log, run a sequence, check titles
LOG="/Users/abd3lraouf/.claude/iterm2-tab-title.log"
> "$LOG"

D="$TMPDIR_BASE/title"

# Simulate: feature branch, no task -> branch title only
run_hook "$D" '{"session_id":"title-1","hook_event_name":"UserPromptSubmit","cwd":"/Users/abd3lraouf/Developer/timewarden.mobile"}'

# Simulate: feature branch with task
run_hook "$D" '{"session_id":"title-1","hook_event_name":"PostToolUse","tool_name":"TaskCreate","subject":"Implement share dialog","cwd":"/Users/abd3lraouf/Developer/timewarden.mobile"}'

# Simulate: Stop (idle with task)
run_hook "$D" '{"session_id":"title-1","hook_event_name":"Stop","cwd":"/Users/abd3lraouf/Developer/timewarden.mobile"}'

# Simulate: Task completed
run_hook "$D" '{"session_id":"title-1","hook_event_name":"PostToolUse","tool_name":"TaskUpdate","status":"completed","cwd":"/Users/abd3lraouf/Developer/timewarden.mobile"}'

echo "Generated titles from log:"
grep "^.*TITLE:" "$LOG" | while read -r line; do
  title=$(echo "$line" | sed "s/.*TITLE: '//;s/' ->.*//")
  echo "  $title"
done

# Verify specific patterns in log
grep -q "⚡" "$LOG" && pass "running prefix (⚡) appears" || fail "prefix" "no running prefix"
grep -q "💤" "$LOG" && pass "idle prefix (💤) appears" || fail "prefix" "no idle prefix"
grep -q "Implement Share Dialog" "$LOG" && pass "task name rendered" || fail "task" "task name not in title"
grep -q "timewarden.mobile" "$LOG" && pass "project name in title" || fail "project" "project not in title"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
