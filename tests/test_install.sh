#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1: $2"; }

echo "=== Install script tests ==="

# ---------------------------------------------------------------------------
# Test 1: Fresh install (no existing settings.json)
# ---------------------------------------------------------------------------
echo "Test 1: Fresh install with no existing settings.json"
FAKE_HOME="$TMPDIR_BASE/t1"
mkdir -p "$FAKE_HOME/.claude"

HOME="$FAKE_HOME" bash "$REPO_DIR/install.sh" > /dev/null 2>&1

if [[ -f "$FAKE_HOME/.claude/scripts/hook.sh" ]]; then
  pass "hook.sh installed"
else
  fail "hook.sh" "not found"
fi

if [[ -x "$FAKE_HOME/.claude/scripts/hook.sh" ]]; then
  pass "hook.sh is executable"
else
  fail "hook.sh" "not executable"
fi

if [[ -f "$FAKE_HOME/.claude/settings.json" ]]; then
  pass "settings.json created"
else
  fail "settings.json" "not found"
fi

# Verify all hook events present
for event in SessionStart UserPromptSubmit Stop Notification PostToolUse; do
  if python3 -c "import json; d=json.load(open('$FAKE_HOME/.claude/settings.json')); assert '$event' in d['hooks']" 2>/dev/null; then
    pass "hook event '$event' configured"
  else
    fail "hook event" "'$event' missing"
  fi
done

# Verify settings.json is valid JSON
if python3 -c "import json; json.load(open('$FAKE_HOME/.claude/settings.json'))" 2>/dev/null; then
  pass "settings.json is valid JSON"
else
  fail "settings.json" "invalid JSON"
fi

# ---------------------------------------------------------------------------
# Test 2: Install with existing settings.json (has other settings)
# ---------------------------------------------------------------------------
echo ""
echo "Test 2: Install preserves existing settings"
FAKE_HOME="$TMPDIR_BASE/t2"
mkdir -p "$FAKE_HOME/.claude"
cat > "$FAKE_HOME/.claude/settings.json" <<'JSON'
{
  "env": {
    "ENABLE_LSP_TOOLS": "1"
  },
  "includeCoAuthoredBy": false,
  "skipDangerousModePermissionPrompt": true
}
JSON

HOME="$FAKE_HOME" bash "$REPO_DIR/install.sh" > /dev/null 2>&1

# Check existing settings preserved
if python3 -c "
import json
d = json.load(open('$FAKE_HOME/.claude/settings.json'))
assert d['env']['ENABLE_LSP_TOOLS'] == '1'
assert d['includeCoAuthoredBy'] == False
assert d['skipDangerousModePermissionPrompt'] == True
" 2>/dev/null; then
  pass "existing settings preserved"
else
  fail "settings" "existing settings lost"
fi

# Check hooks added
if python3 -c "import json; d=json.load(open('$FAKE_HOME/.claude/settings.json')); assert 'SessionStart' in d['hooks']" 2>/dev/null; then
  pass "hooks added alongside existing settings"
else
  fail "hooks" "not added"
fi

# ---------------------------------------------------------------------------
# Test 3: Install with existing hooks (doesn't duplicate)
# ---------------------------------------------------------------------------
echo ""
echo "Test 3: Install doesn't duplicate existing hooks"
FAKE_HOME="$TMPDIR_BASE/t3"
mkdir -p "$FAKE_HOME/.claude"

# First install
HOME="$FAKE_HOME" bash "$REPO_DIR/install.sh" > /dev/null 2>&1
# Second install
HOME="$FAKE_HOME" bash "$REPO_DIR/install.sh" > /dev/null 2>&1

# Count SessionStart entries (should be exactly 1)
count=$(python3 -c "
import json
d = json.load(open('$FAKE_HOME/.claude/settings.json'))
print(len(d['hooks']['SessionStart']))
" 2>/dev/null)
if [[ "$count" == "1" ]]; then
  pass "no duplicate SessionStart hooks"
else
  fail "duplicates" "SessionStart has $count entries (expected 1)"
fi

# Count PostToolUse entries (should be exactly 2: TaskCreate + TaskUpdate)
count=$(python3 -c "
import json
d = json.load(open('$FAKE_HOME/.claude/settings.json'))
print(len(d['hooks']['PostToolUse']))
" 2>/dev/null)
if [[ "$count" == "2" ]]; then
  pass "no duplicate PostToolUse hooks (2 entries: TaskCreate + TaskUpdate)"
else
  fail "duplicates" "PostToolUse has $count entries (expected 2)"
fi

# ---------------------------------------------------------------------------
# Test 4: Install with existing hooks from other tools (preserves them)
# ---------------------------------------------------------------------------
echo ""
echo "Test 4: Install preserves hooks from other tools"
FAKE_HOME="$TMPDIR_BASE/t4"
mkdir -p "$FAKE_HOME/.claude"
cat > "$FAKE_HOME/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/some-other-tool.sh"
          }
        ]
      }
    ]
  }
}
JSON

HOME="$FAKE_HOME" bash "$REPO_DIR/install.sh" > /dev/null 2>&1

# Check both hooks present
count=$(python3 -c "
import json
d = json.load(open('$FAKE_HOME/.claude/settings.json'))
print(len(d['hooks']['SessionStart']))
" 2>/dev/null)
if [[ "$count" == "2" ]]; then
  pass "both SessionStart hooks present (other tool + ours)"
else
  fail "merge" "SessionStart has $count entries (expected 2)"
fi

# Check the other tool's hook is still there
if python3 -c "
import json
d = json.load(open('$FAKE_HOME/.claude/settings.json'))
cmds = [h['command'] for e in d['hooks']['SessionStart'] for h in e.get('hooks',[])]
assert '\$HOME/.claude/scripts/some-other-tool.sh' in cmds
" 2>/dev/null; then
  pass "other tool's hook preserved"
else
  fail "merge" "other tool's hook lost"
fi

# ---------------------------------------------------------------------------
# Test 5: Installed hook.sh matches repo source
# ---------------------------------------------------------------------------
echo ""
echo "Test 5: Installed hook.sh matches repo source"
FAKE_HOME="$TMPDIR_BASE/t5"
mkdir -p "$FAKE_HOME/.claude"
HOME="$FAKE_HOME" bash "$REPO_DIR/install.sh" > /dev/null 2>&1

if diff "$REPO_DIR/scripts/hook.sh" "$FAKE_HOME/.claude/scripts/hook.sh" > /dev/null 2>&1; then
  pass "installed hook.sh matches repo source"
else
  fail "hook.sh" "content differs from repo"
fi

echo ""
echo "=== Uninstall script tests ==="

# ---------------------------------------------------------------------------
# Test 6: Uninstall removes hook script
# ---------------------------------------------------------------------------
echo "Test 6: Uninstall removes hook script"
FAKE_HOME="$TMPDIR_BASE/t6"
mkdir -p "$FAKE_HOME/.claude/scripts"
touch "$FAKE_HOME/.claude/scripts/hook.sh"
touch "$FAKE_HOME/.claude/iterm2-tab-title.log"
mkdir -p /tmp/claude-tab-status-test-uninstall
touch /tmp/claude-tab-status-test-uninstall/test.json

# Patch uninstall to use test signal dir
HOME="$FAKE_HOME" bash -c "
  $(sed 's|/tmp/claude-tab-status|/tmp/claude-tab-status-test-uninstall|' "$REPO_DIR/uninstall.sh")
" > /dev/null 2>&1

if [[ ! -f "$FAKE_HOME/.claude/scripts/hook.sh" ]]; then
  pass "hook.sh removed"
else
  fail "hook.sh" "still exists"
fi

if [[ ! -f "$FAKE_HOME/.claude/iterm2-tab-title.log" ]]; then
  pass "log file removed"
else
  fail "log" "still exists"
fi

if [[ ! -d /tmp/claude-tab-status-test-uninstall ]]; then
  pass "signal dir removed"
else
  fail "signal dir" "still exists"
  rm -rf /tmp/claude-tab-status-test-uninstall
fi

# ---------------------------------------------------------------------------
# Test 7: Uninstall is safe with missing files
# ---------------------------------------------------------------------------
echo ""
echo "Test 7: Uninstall handles missing files gracefully"
FAKE_HOME="$TMPDIR_BASE/t7"
mkdir -p "$FAKE_HOME/.claude"
# Don't create any files — uninstall should not error

if HOME="$FAKE_HOME" bash -c "
  $(sed 's|/tmp/claude-tab-status|/tmp/claude-tab-status-nonexistent|' "$REPO_DIR/uninstall.sh")
" > /dev/null 2>&1; then
  pass "uninstall exits cleanly with no files"
else
  fail "uninstall" "errored on missing files"
fi

# ---------------------------------------------------------------------------
# Test 8: Full round-trip (install -> verify -> uninstall -> verify)
# ---------------------------------------------------------------------------
echo ""
echo "Test 8: Full round-trip install/uninstall"
FAKE_HOME="$TMPDIR_BASE/t8"
mkdir -p "$FAKE_HOME/.claude"

# Install
HOME="$FAKE_HOME" bash "$REPO_DIR/install.sh" > /dev/null 2>&1
[[ -f "$FAKE_HOME/.claude/scripts/hook.sh" ]] && pass "round-trip: installed" || fail "round-trip" "install failed"

# Uninstall
HOME="$FAKE_HOME" bash "$REPO_DIR/uninstall.sh" > /dev/null 2>&1
[[ ! -f "$FAKE_HOME/.claude/scripts/hook.sh" ]] && pass "round-trip: uninstalled" || fail "round-trip" "uninstall failed"
[[ ! -f "$FAKE_HOME/.claude/iterm2-tab-title.log" ]] && pass "round-trip: log cleaned" || fail "round-trip" "log not cleaned"

# settings.json should still exist (we don't delete it)
[[ -f "$FAKE_HOME/.claude/settings.json" ]] && pass "round-trip: settings.json preserved" || fail "round-trip" "settings.json deleted"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
