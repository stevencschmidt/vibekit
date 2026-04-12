#!/usr/bin/env bash
# Ralph Loop — Autonomous task executor (project-agnostic template)
# Usage: ./ralph.sh [--tool claude|amp] [--model MODEL] [--max N] [--dry-run]
#
# Reads tasks.md via ralph-prompt.md, executes one task per iteration,
# resets context between iterations to stay under 100K tokens.
#
# Rate limit handling:
#   - Checks Claude Pro usage before each iteration via OAuth API
#   - On rate limit: calculates exact reset time, sleeps until renewal + 30s buffer
#   - Does NOT count rate limits as stalls or iterations
#   - Shows live countdown to reset time
#
# Safety features:
#   - Git rollback on stall (git reset --hard to pre-iteration SHA)
#   - Post-iteration verification (project-specific — see verify_build below)
#   - Separate stall counter and verification-failure counter per task
#   - 3-strike limit on each failure type independently
#   - Decisions log for inter-task coherence

set -e

# === Configuration ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../vibekit.config.sh
source "$SCRIPT_DIR/../vibekit.config.sh"
# shellcheck source=./sync-helpers.sh
source "$SCRIPT_DIR/sync-helpers.sh"
# shellcheck source=./monitor.sh
source "$SCRIPT_DIR/monitor.sh"

# === Skills Loading ===
# SKILLS is defined in vibekit.config.sh as an array of skill names.
# Each name maps to skills/<name>/ under PROJECT_ROOT.
# Builds SKILLS_CONTEXT_TEXT for prompt substitution and collects
# skill verify.sh paths for post-completion verification.
# Permission enforcement (no tasks.md writes, no non-ralph sync.json blocks)
# is declared in ralph-prompt.md Rules and the manifest.md schema constraints.
SKILLS_CONTEXT_TEXT=""
_SKILL_VERIFY_SCRIPTS=()

if [[ "${#SKILLS[@]}" -gt 0 ]]; then
  for _skill in "${SKILLS[@]}"; do
    _manifest="$PROJECT_ROOT/skills/${_skill}/manifest.md"
    if [[ -f "$_manifest" ]]; then
      [[ -n "$SKILLS_CONTEXT_TEXT" ]] && SKILLS_CONTEXT_TEXT+=$'\n---\n\n'
      SKILLS_CONTEXT_TEXT+="### Skill: ${_skill}"$'\n\n'
      SKILLS_CONTEXT_TEXT+="$(cat "$_manifest")"$'\n'
      _skill_verify="$PROJECT_ROOT/skills/${_skill}/verify.sh"
      if [[ -f "$_skill_verify" ]]; then
        _SKILL_VERIFY_SCRIPTS+=("$_skill_verify")
      fi
    else
      echo "Warning: skill '${_skill}' registered but manifest not found: $_manifest" >&2
    fi
  done
fi

# Combines project verify_build() with any registered skill verify.sh scripts.
# ralph.sh calls run_all_verifications() instead of verify_build() directly.
run_all_verifications() {
  verify_build || return 1
  for _sv in "${_SKILL_VERIFY_SCRIPTS[@]}"; do
    bash "$_sv" || return 1
  done
  return 0
}

CREDS_FILE="$HOME/.claude/.credentials.json"
RATE_LIMIT_BUFFER=30
MAX_RATE_LIMIT_WAITS=10

# Resolve python interpreter (Windows uses 'python', not 'python3')
if command -v python3 &>/dev/null && python3 -c "" 2>/dev/null; then
  PYTHON="python3"
else
  PYTHON="python"
fi

# === Parse Arguments ===
# TOOL and MODEL default values come from vibekit.config.sh; CLI flags override them.
MAX_ITERATIONS=50
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)      TOOL="$2";               shift 2 ;;
    --tool=*)    TOOL="${1#*=}";          shift   ;;
    --model)     MODEL="$2";              shift 2 ;;
    --model=*)   MODEL="${1#*=}";         shift   ;;
    --max)       MAX_ITERATIONS="$2";     shift 2 ;;
    --max=*)     MAX_ITERATIONS="${1#*=}"; shift  ;;
    --dry-run)   DRY_RUN=true;            shift   ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# === Validate ===
if [[ "$TOOL" != "claude" && "$TOOL" != "amp" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'claude' or 'amp'."
  exit 1
fi

if [[ ! -f "$SYNC_FILE" ]]; then
  echo "Error: sync.json not found: $SYNC_FILE"
  echo "Run scripts/init.sh to initialize the project first."
  exit 1
fi

# Validate sync.json is well-formed JSON (corrupted file causes silent failures downstream)
if ! $PYTHON -c "import json, sys; json.load(open(sys.argv[1]))" "$SYNC_FILE" 2>/dev/null; then
  echo "Error: sync.json is corrupted or invalid JSON: $SYNC_FILE"
  echo "Restore from git: git checkout HEAD -- state/sync.json"
  echo "Or re-initialize:  bash scripts/init.sh"
  exit 1
fi

if [[ ! -f "$RALPH_PROMPT" ]]; then
  echo "Error: Ralph prompt not found: $RALPH_PROMPT"
  exit 1
fi

# Ensure decisions.md exists
if [[ ! -f "$DECISIONS_FILE" ]]; then
  echo "# Decisions Log" > "$DECISIONS_FILE"
  echo "" >> "$DECISIONS_FILE"
  echo "Patterns and key choices recorded by Ralph iterations." >> "$DECISIONS_FILE"
  echo "" >> "$DECISIONS_FILE"
fi

# Ensure git is initialized
if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
  echo "Error: Git not initialized in $PROJECT_ROOT"
  echo "Run: git init && git add -A && git commit -m 'initial commit'"
  exit 1
fi

# Ensure at least one commit exists (HEAD must be resolvable for rollback)
if ! git -C "$PROJECT_ROOT" rev-parse HEAD &>/dev/null; then
  echo "Error: No commits in repo — rollback requires at least one commit."
  echo "Run: git add -A && git commit -m 'initial commit'"
  exit 1
fi

# === OAuth Token ===
get_oauth_token() {
  if [[ -f "$CREDS_FILE" ]]; then
    $PYTHON -c "
import json
with open('$CREDS_FILE') as f:
    print(json.load(f)['claudeAiOauth']['accessToken'])
" 2>/dev/null
  fi
}

# === Usage API ===
get_usage() {
  local token
  token=$(get_oauth_token)
  if [[ -z "$token" ]]; then
    echo ""
    return 1
  fi
  curl -s -X GET "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null
}

# Returns the binding window: "five_hour" or "seven_day"
# The binding window is whichever is at 100% utilization.
# If both are at 100%, seven_day takes precedence (longer wait).
# If neither is at 100%, returns "five_hour" as default.
get_binding_window() {
  local usage="$1"
  echo "$usage" | $PYTHON -c "
import sys, json
data = json.load(sys.stdin)
five_util  = float(data.get('five_hour',  {}).get('utilization', 0))
seven_util = float(data.get('seven_day',  {}).get('utilization', 0))
if seven_util >= 100:
    print('seven_day')
elif five_util >= 100:
    print('five_hour')
else:
    print('five_hour')
" 2>/dev/null || echo "five_hour"
}

seconds_until_reset() {
  local usage="$1"
  local window="$2"  # "five_hour" or "seven_day"
  window="${window:-five_hour}"
  echo "$usage" | $PYTHON -c "
import sys, json
from datetime import datetime, timezone
data = json.load(sys.stdin)
window_data = data.get('$window', data.get('five_hour', {}))
reset = window_data.get('resets_at', '')
if not reset:
    print(300)
    sys.exit(0)
reset_dt = datetime.fromisoformat(reset)
now = datetime.now(timezone.utc)
diff = (reset_dt - now).total_seconds()
print(int(max(0, diff)))
" 2>/dev/null || echo "300"
}

get_utilization() {
  local usage="$1"
  local window="${2:-five_hour}"
  echo "$usage" | $PYTHON -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('$window', {}).get('utilization', 0))
" 2>/dev/null || echo "0"
}

get_reset_time() {
  local usage="$1"
  local window="${2:-five_hour}"
  echo "$usage" | $PYTHON -c "
import sys, json
from datetime import datetime
data = json.load(sys.stdin)
window_data = data.get('$window', data.get('five_hour', {}))
reset = window_data.get('resets_at', '')
if not reset:
    print('unknown')
    sys.exit(0)
reset_dt = datetime.fromisoformat(reset)
print(reset_dt.strftime('%H:%M:%S %Z'))
" 2>/dev/null || echo "unknown"
}

# === Rate Limit Detection ===
is_rate_limited_output() {
  local output="$1"
  if echo "$output" | grep -qi "rate limit";        then return 0; fi
  if echo "$output" | grep -qi "usage limit";       then return 0; fi
  if echo "$output" | grep -qi "too many requests"; then return 0; fi
  if echo "$output" | grep -qi "exceeded.*quota";   then return 0; fi
  return 1
}

# === Wait for Rate Limit Reset ===
wait_for_reset() {
  local task_id="$1"
  local source="$2"

  local usage
  usage=$(get_usage)

  if [[ -z "$usage" ]]; then
    echo "  ⏳ Rate limited ($source) — API unreachable, waiting 5 minutes"
    echo "[$ITERATION] RATE LIMITED ($source) on $task_id — API unreachable, waiting 300s: $(date)" >> "$LOG_FILE"
    local remaining=300
    while [[ $remaining -gt 0 ]]; do
      printf "\r     Resuming in %02d:%02d..." $(( remaining / 60 )) $(( remaining % 60 ))
      sleep 1
      remaining=$(( remaining - 1 ))
    done
    printf "\r     Resuming now...          \n"
    echo "[$ITERATION] Rate limit wait complete — retrying $task_id: $(date)" >> "$LOG_FILE"
    return
  fi

  # Determine which window is the binding constraint
  local window
  window=$(get_binding_window "$usage")

  local five_util;  five_util=$(get_utilization  "$usage" "five_hour")
  local seven_util; seven_util=$(get_utilization "$usage" "seven_day")
  local reset_time; reset_time=$(get_reset_time  "$usage" "$window")
  local wait_secs;  wait_secs=$(seconds_until_reset "$usage" "$window")

  if [[ $wait_secs -eq 0 ]]; then wait_secs=60; fi
  wait_secs=$(( wait_secs + RATE_LIMIT_BUFFER ))

  echo ""
  echo "  ⏳ Rate limited ($source)"
  echo "     5-hour utilization:  ${five_util}%"
  echo "     7-day utilization:   ${seven_util}%"
  if [[ "$window" == "seven_day" ]]; then
    echo "     ⚠ Weekly limit reached — waiting for 7-day window to reset"
  fi
  echo "     Binding window:  $window"
  echo "     Resets at:       $reset_time"
  echo "     Waiting:         $(( wait_secs / 60 ))m $(( wait_secs % 60 ))s (includes ${RATE_LIMIT_BUFFER}s buffer)"
  echo "     Ctrl+C to stop"
  echo "[$ITERATION] RATE LIMITED ($source) on $task_id — window=$window 5h=${five_util}% 7d=${seven_util}% resets=$reset_time waiting=${wait_secs}s: $(date)" >> "$LOG_FILE"

  local remaining=$wait_secs
  while [[ $remaining -gt 0 ]]; do
    printf "\r     Resuming in %02d:%02d..." "$((remaining/60))" "$((remaining%60))"
    sleep 1
    remaining=$(( remaining - 1 ))
  done
  printf "\r     Resuming now...          \n"
  echo "[$ITERATION] Rate limit wait complete — retrying $task_id: $(date)" >> "$LOG_FILE"
}

# === Pre-iteration Usage Check ===
check_usage_before_iteration() {
  local task_id="$1"
  if [[ "$TOOL" != "claude" ]]; then return 0; fi

  local usage
  usage=$(get_usage)
  if [[ -z "$usage" ]]; then return 0; fi

  # Check both windows — either can be the binding constraint
  local five_util;  five_util=$(get_utilization  "$usage" "five_hour")
  local seven_util; seven_util=$(get_utilization "$usage" "seven_day")

  # Block if either window is exhausted (use python3 for float compare — bc not reliable on Windows)
  if $PYTHON -c "import sys; sys.exit(0 if float('${five_util}') >= 100 else 1)" 2>/dev/null; then return 1; fi
  if $PYTHON -c "import sys; sys.exit(0 if float('${seven_util}') >= 100 else 1)" 2>/dev/null; then return 1; fi

  # Warn if approaching limits
  if $PYTHON -c "import sys; sys.exit(0 if float('${seven_util}') > 80 else 1)" 2>/dev/null; then
    echo "  ⚡ Weekly usage at ${seven_util}% — approaching 7-day limit"
  elif $PYTHON -c "import sys; sys.exit(0 if float('${five_util}') > 80 else 1)" 2>/dev/null; then
    echo "  ⚡ 5-hour usage at ${five_util}% — approaching rate limit"
  fi

  return 0
}

# verify_build() is sourced from vibekit.config.sh — project-specific hook.

# === Safety Commit ===
safety_commit() {
  local task_id="$1"
  if git -C "$PROJECT_ROOT" diff --quiet && \
     git -C "$PROJECT_ROOT" diff --cached --quiet; then
    return 0
  fi
  echo "  ⚠ Uncommitted changes detected — creating safety commit"
  git -C "$PROJECT_ROOT" add -A
  git -C "$PROJECT_ROOT" commit \
    -m "Ralph safety commit: $task_id completed (Claude did not commit)" \
    --no-verify 2>/dev/null || true
  echo "[$ITERATION] SAFETY COMMIT for $task_id — Claude did not commit: $(date)" >> "$LOG_FILE"
}

# === Effective Prompt (with SKILLS_CONTEXT substituted) ===
# Creates a temp file with {{SKILLS_CONTEXT}} replaced by loaded skill manifests.
# Temp file is deleted on exit via trap. Falls back to original prompt on error.
_RALPH_PROMPT_EFFECTIVE="$RALPH_PROMPT"
_RALPH_PROMPT_TEMP=""
if grep -q '{{SKILLS_CONTEXT}}' "$RALPH_PROMPT" 2>/dev/null; then
  _RALPH_PROMPT_TEMP=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/ralph_prompt_$$")
  _skills_ctx_arg="$SKILLS_CONTEXT_TEXT"
  [[ -z "$_skills_ctx_arg" ]] && _skills_ctx_arg="(No skills registered for this project.)"
  $PYTHON -c "
import sys
path, skills_ctx = sys.argv[1], sys.argv[2]
with open(path, 'r') as f:
    content = f.read()
content = content.replace('{{SKILLS_CONTEXT}}', skills_ctx)
sys.stdout.write(content)
" "$RALPH_PROMPT" "$_skills_ctx_arg" > "$_RALPH_PROMPT_TEMP" 2>/dev/null \
    || cp "$RALPH_PROMPT" "$_RALPH_PROMPT_TEMP"
  _RALPH_PROMPT_EFFECTIVE="$_RALPH_PROMPT_TEMP"
fi
# shellcheck disable=SC2064
trap 'rm -f "$_RALPH_PROMPT_TEMP" 2>/dev/null || true' EXIT

# Graceful shutdown on SIGINT (Ctrl+C) or SIGTERM
_ralph_interrupted() {
  echo ""
  echo "Interrupted — stopping Ralph"
  if [[ -n "${PRE_SHA:-}" ]]; then
    echo "  Rolling back uncommitted changes from current iteration..."
    git -C "$PROJECT_ROOT" reset --hard "$PRE_SHA" 2>/dev/null || true
  fi
  echo "=== Stopped: interrupted at $(date) ===" >> "$LOG_FILE" 2>/dev/null || true
  exit 130
}
trap '_ralph_interrupted' SIGINT SIGTERM

# === Initialize Log ===
if [[ ! -f "$LOG_FILE" ]]; then
  echo "# Ralph Loop Log" > "$LOG_FILE"
fi
echo "" >> "$LOG_FILE"
echo "=== Run started: $(date) ===" >> "$LOG_FILE"
echo "Tool: $TOOL | Model: $MODEL | Max: $MAX_ITERATIONS" >> "$LOG_FILE"

# === Pre-flight Summary ===
PREFLIGHT_TASK_ID=$(sync_read "ralph.task_id" 2>/dev/null || echo "null")
PREFLIGHT_TASK_TITLE=$(sync_read "ralph.task_title" 2>/dev/null || echo "")
PREFLIGHT_STATUS=$(sync_read "execution.current_task_status" 2>/dev/null || echo "unknown")

PREFLIGHT_USAGE=$(get_usage 2>/dev/null) || true
PREFLIGHT_5H="?"
PREFLIGHT_7D="?"
if [[ -n "$PREFLIGHT_USAGE" ]]; then
  PREFLIGHT_5H=$(get_utilization "$PREFLIGHT_USAGE" "five_hour")
  PREFLIGHT_7D=$(get_utilization "$PREFLIGHT_USAGE" "seven_day")
fi

echo "============================================"
echo "  Ralph Loop — VibeKit Agent Toolkit"
echo "============================================"
echo "  Tool:          $TOOL"
echo "  Model:         $MODEL"
echo "  Usage (5h):    ${PREFLIGHT_5H}%"
echo "  Usage (7d):    ${PREFLIGHT_7D}%"
echo "  Sync file:     $SYNC_FILE"
echo "  Task status:   $PREFLIGHT_STATUS"
echo "  Current task:  $PREFLIGHT_TASK_ID — $PREFLIGHT_TASK_TITLE"
echo "  Max iter:      $MAX_ITERATIONS"
echo "  Dry run:       $DRY_RUN"
echo "============================================"
echo ""

if [[ -z "$PREFLIGHT_TASK_ID" || "$PREFLIGHT_TASK_ID" == "null" ]]; then
  echo "No task assigned in sync.json — nothing to do."
  echo "The Supervisor must write a task to the ralph block before Ralph can run."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run — task ready: $PREFLIGHT_TASK_ID. Exiting."
  exit 0
fi

# === Session Tracking ===
RALPH_SESSION=$(sync_read "ralph.session" 2>/dev/null || echo "1")
if [[ -z "$RALPH_SESSION" || "$RALPH_SESSION" == "null" ]]; then
  RALPH_SESSION=1
fi
SESSION_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TASKS_COMPLETED_SESSION=()

# === Main Loop ===
ITERATION=0
STALL_COUNT=0          # Counts iterations where task was not marked complete
BUILD_FAIL_COUNT=0     # Counts iterations where task completed but verification failed
LAST_FAILED_TASK=""    # Tracks which task the counters apply to
RATE_LIMIT_WAITS=0

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))

  TASK_ID=$(sync_read "ralph.task_id" 2>/dev/null || echo "")

  if [[ -z "$TASK_ID" || "$TASK_ID" == "null" ]]; then
    echo ""
    echo "No task assigned in sync.json — all done or awaiting Supervisor."
    echo "Completed at iteration $ITERATION of $MAX_ITERATIONS"
    echo "=== Completed: $(date) (iteration $ITERATION) ===" >> "$LOG_FILE"
    exit 0
  fi

  echo ""
  echo "─────────────────────────────────────────"
  echo "  Iteration $ITERATION/$MAX_ITERATIONS — $TASK_ID"
  echo "─────────────────────────────────────────"

  # --- Pre-iteration usage check ---
  if ! check_usage_before_iteration "$TASK_ID"; then
    RATE_LIMIT_WAITS=$((RATE_LIMIT_WAITS + 1))
    if [[ $RATE_LIMIT_WAITS -ge $MAX_RATE_LIMIT_WAITS ]]; then
      echo ""
      echo "STOPPED: Hit rate limit $MAX_RATE_LIMIT_WAITS consecutive times."
      echo "Check your Claude Pro plan status."
      echo "=== Stopped: rate limit wait cap ($MAX_RATE_LIMIT_WAITS) at $(date) ===" >> "$LOG_FILE"
      exit 1
    fi
    wait_for_reset "$TASK_ID" "pre-check"
    ITERATION=$((ITERATION - 1))
    continue
  fi

  echo "[$ITERATION] Starting $TASK_ID: $(date)" >> "$LOG_FILE"

  # Save HEAD SHA for rollback
  PRE_SHA=$(git -C "$PROJECT_ROOT" rev-parse HEAD)

  # --- Run Claude Code or Amp ---
  # Use temp file instead of tee /dev/stderr — more reliable on Windows/Git Bash.
  _TMPOUT=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/ralph_out_$$")
  if [[ "$TOOL" == "claude" ]]; then
    claude --dangerously-skip-permissions --print \
      --model "$MODEL" \
      "Read $_RALPH_PROMPT_EFFECTIVE and execute the task in $SYNC_FILE" \
      2>&1 | tee "$_TMPOUT" || true
  else
    echo "Read $_RALPH_PROMPT_EFFECTIVE and execute the task in $SYNC_FILE" \
      | amp --dangerously-allow-all 2>&1 | tee "$_TMPOUT" || true
  fi
  OUTPUT=$(cat "$_TMPOUT" 2>/dev/null || echo "")
  rm -f "$_TMPOUT" 2>/dev/null || true

  # --- Rate Limit Check (from output) ---
  if is_rate_limited_output "$OUTPUT"; then
    RATE_LIMIT_WAITS=$((RATE_LIMIT_WAITS + 1))
    if [[ $RATE_LIMIT_WAITS -ge $MAX_RATE_LIMIT_WAITS ]]; then
      echo ""
      echo "STOPPED: Hit rate limit $MAX_RATE_LIMIT_WAITS consecutive times."
      echo "Check your Claude Pro plan status."
      echo "=== Stopped: rate limit wait cap ($MAX_RATE_LIMIT_WAITS) at $(date) ===" >> "$LOG_FILE"
      exit 1
    fi
    wait_for_reset "$TASK_ID" "mid-execution"
    ITERATION=$((ITERATION - 1))
    continue
  fi

  # Reset rate limit counter on successful execution
  RATE_LIMIT_WAITS=0

  # --- Sentinel Detection from Output ---
  # Parse OUTPUT for sentinels emitted by the Claude agent. If TASK_COMPLETE is found
  # in stdout, write to ralph.last_sentinel as a safety net (the agent also writes there
  # directly via sync_write, but this ensures consistency if it fails).
  # TASK_BLOCKED causes immediate exit — Supervisor intervention is required.
  # SESSION_HANDOFF continues the main loop to spawn a fresh Claude session.
  SENTINEL_TYPE=$(detect_sentinel "$OUTPUT" 2>/dev/null || echo "")
  NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$SENTINEL_TYPE" == "TASK_COMPLETE" ]]; then
    sync_write "ralph.last_sentinel" "[TASK_COMPLETE: ${TASK_ID}]" 2>/dev/null || true
    sync_write "ralph.last_updated" "$NOW_ISO" 2>/dev/null || true
  elif [[ "$SENTINEL_TYPE" == "TASK_BLOCKED" ]]; then
    BLOCK_REASON=$(extract_block_reason "$OUTPUT" 2>/dev/null || echo "unknown reason")
    sync_write "ralph.last_sentinel" "[TASK_BLOCKED: ${BLOCK_REASON}]" 2>/dev/null || true
    sync_write "ralph.last_updated" "$NOW_ISO" 2>/dev/null || true
    echo "[$ITERATION] TASK_BLOCKED on $TASK_ID: $BLOCK_REASON: $(date)" >> "$LOG_FILE"
    echo "  ⛔ $TASK_ID blocked: $BLOCK_REASON"
    echo ""
    echo "STOPPED: Task blocked — Supervisor intervention required."
    echo "Reason: $BLOCK_REASON"
    echo "Check $LOG_FILE and $SYNC_FILE for details."
    echo "=== Stopped: $TASK_ID blocked at $(date) ===" >> "$LOG_FILE"
    exit 1
  elif [[ "$SENTINEL_TYPE" == "SESSION_HANDOFF" ]]; then
    # Build JSON array of tasks completed this session
    if [[ ${#TASKS_COMPLETED_SESSION[@]} -gt 0 ]]; then
      TASKS_JSON=$($PYTHON -c "import sys, json; print(json.dumps(sys.argv[1:]))" \
        "${TASKS_COMPLETED_SESSION[@]}" 2>/dev/null || echo "[]")
    else
      TASKS_JSON="[]"
    fi
    sync_write "ralph.last_sentinel" "[SESSION_HANDOFF]" 2>/dev/null || true
    sync_write "ralph.last_updated" "$NOW_ISO" 2>/dev/null || true
    session_log_append "ralph" "$RALPH_SESSION" "$SESSION_START_ISO" "$NOW_ISO" \
      "SESSION_HANDOFF" "0" "$TASKS_JSON" 2>/dev/null || true
    echo "[$ITERATION] SESSION_HANDOFF on $TASK_ID (session $RALPH_SESSION): $(date)" >> "$LOG_FILE"
    echo "  ↻ SESSION_HANDOFF — session $RALPH_SESSION complete, spawning fresh session"
    # Reset session tracking for the new session
    RALPH_SESSION=$((RALPH_SESSION + 1))
    SESSION_START_ISO="$NOW_ISO"
    TASKS_COMPLETED_SESSION=()
    continue
  fi

  # --- Task Completion Check ---
  # Verify the SPECIFIC task_id was signalled complete via sync.json last_sentinel.
  # Ralph writes [TASK_COMPLETE: T###] to ralph.last_sentinel on completion (above
  # sentinel detection writes it too as a safety net from stdout parsing).
  LAST_SENTINEL=$(sync_read "ralph.last_sentinel" 2>/dev/null || echo "null")
  # Use SENTINEL_TYPE as primary signal — avoids sync.json round-trip failures on Windows.
  # Fall back to sync.json last_sentinel for cross-session detection.
  if [[ "$SENTINEL_TYPE" == "TASK_COMPLETE" ]] || [[ "$LAST_SENTINEL" == "[TASK_COMPLETE: ${TASK_ID}]" ]]; then

    # --- Verification (build/test) ---
    if run_all_verifications; then
      echo "[$ITERATION] Completed $TASK_ID (verified OK): $(date)" >> "$LOG_FILE"
      echo "  ✓ $TASK_ID complete (verified)"
      safety_commit "$TASK_ID"
      TASKS_COMPLETED_SESSION+=("$TASK_ID")

      # Mark task complete in tasks.md (fallback when running without Supervisor)
      _spec_tasks="${SPEC_TASKS_FILE:-$PROJECT_ROOT/specs/001-vibekit-agent-toolkit/tasks.md}"
      if [[ -f "$_spec_tasks" ]]; then
        $PYTHON -c "
import sys, re
path, tid = sys.argv[1], sys.argv[2]
try:
    with open(path, 'r') as f: content = f.read()
    content = re.sub(r'^(- )\[ \] (' + re.escape(tid) + r' )', r'\1[x] \2', content, flags=re.MULTILINE)
    with open(path, 'w') as f: f.write(content)
except Exception: pass
" "$_spec_tasks" "${TASK_ID}" 2>/dev/null || true
      fi

      # Clear ralph.task_id so the next iteration exits cleanly (Supervisor assigns next task)
      sync_write "ralph.task_id" "null" 2>/dev/null || true

      # Reset both counters on clean success
      STALL_COUNT=0
      BUILD_FAIL_COUNT=0
      LAST_FAILED_TASK=""

    else
      # Task marked complete but verification failed — roll back
      echo "[$ITERATION] ROLLBACK $TASK_ID (verification failed): $(date)" >> "$LOG_FILE"
      echo "  ✗ $TASK_ID failed verification — rolling back"
      git -C "$PROJECT_ROOT" reset --hard "$PRE_SHA"

      # Track build failures separately from stalls
      if [[ "$TASK_ID" == "$LAST_FAILED_TASK" ]]; then
        BUILD_FAIL_COUNT=$((BUILD_FAIL_COUNT + 1))
      else
        BUILD_FAIL_COUNT=1
        STALL_COUNT=0
        LAST_FAILED_TASK="$TASK_ID"
      fi

      if [[ $BUILD_FAIL_COUNT -ge 3 ]]; then
        echo ""
        echo "STOPPED: $TASK_ID failed verification 3 consecutive times."
        echo "The code compiles/runs but fails the quality check."
        echo "Review the verification output above and check $LOG_FILE."
        echo "=== Stopped: $TASK_ID verify-failed 3x at $(date) ===" >> "$LOG_FILE"
        exit 1
      fi
      echo "  Retrying ($BUILD_FAIL_COUNT/3 verification attempts)..."
    fi

  else
    # Task was not marked complete — Claude stalled or hit an error
    echo "[$ITERATION] STALLED on $TASK_ID: $(date)" >> "$LOG_FILE"
    echo "  ⚠ $TASK_ID not marked complete — rolling back partial changes"
    git -C "$PROJECT_ROOT" reset --hard "$PRE_SHA"

    # Track stalls separately from build failures
    if [[ "$TASK_ID" == "$LAST_FAILED_TASK" ]]; then
      STALL_COUNT=$((STALL_COUNT + 1))
    else
      STALL_COUNT=1
      BUILD_FAIL_COUNT=0
      LAST_FAILED_TASK="$TASK_ID"
    fi

    if [[ $STALL_COUNT -ge 3 ]]; then
      echo ""
      echo "STOPPED: $TASK_ID stalled 3 consecutive times."
      echo "Claude is not completing the task. Possible causes:"
      echo "  - Task is too large or ambiguous"
      echo "  - Missing context (check relevant_files in sync.json ralph block)"
      echo "  - Dependency on a USER task not yet completed"
      echo ""
      echo "Check $LOG_FILE and $SYNC_FILE for details."
      echo "=== Stopped: $TASK_ID stalled 3x at $(date) ===" >> "$LOG_FILE"
      exit 1
    fi

    echo "  Retrying ($STALL_COUNT/3 stall attempts)..."
  fi

  sleep 2
done

echo ""
echo "Reached max iterations ($MAX_ITERATIONS)."
echo "Run ralph again to continue, or increase --max."
echo "Check $LOG_FILE and $SYNC_FILE for status."
echo "=== Stopped at max iterations: $(date) ===" >> "$LOG_FILE"
exit 1