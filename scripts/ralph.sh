#!/usr/bin/env bash
# Ralph Loop — Autonomous task executor (project-agnostic template)
# Usage: ./ralph.sh [--tool claude|amp] [--model MODEL] [--max N] [--task T###] [--dry-run]
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
MAX_RATE_LIMIT_WAITS=${MAX_RATE_LIMIT_WAITS:-50}

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
RESUME_TASK=""
SKIP_QC=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)      TOOL="$2";               shift 2 ;;
    --tool=*)    TOOL="${1#*=}";          shift   ;;
    --model)     MODEL="$2";              shift 2 ;;
    --model=*)   MODEL="${1#*=}";         shift   ;;
    --max)       MAX_ITERATIONS="$2";     shift 2 ;;
    --max=*)     MAX_ITERATIONS="${1#*=}"; shift  ;;
    --task)      RESUME_TASK="$2";        shift 2 ;;
    --task=*)    RESUME_TASK="${1#*=}";   shift   ;;
    --dry-run)   DRY_RUN=true;            shift   ;;
    --skip-qc)   SKIP_QC=true;            shift   ;;
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
  # Only check the last 20 lines — API errors appear at the tail of output,
  # not embedded in content the agent generated (which may quote these phrases).
  local tail_output
  tail_output=$(echo "$output" | tail -n 20)
  if echo "$tail_output" | grep -qi "rate limit";        then return 0; fi
  if echo "$tail_output" | grep -qi "usage limit";       then return 0; fi
  if echo "$tail_output" | grep -qi "too many requests"; then return 0; fi
  if echo "$tail_output" | grep -qi "exceeded.*quota";   then return 0; fi
  if echo "$tail_output" | grep -qi "5-hour limit";      then return 0; fi
  if echo "$tail_output" | grep -qi "weekly limit";      then return 0; fi
  if echo "$tail_output" | grep -qi "subscription limit"; then return 0; fi
  if echo "$tail_output" | grep -qi "reset at";          then return 0; fi
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
  echo "[$ITERATION] RATE_LIMIT until $reset_time ($wait_secs s)" >> "$LOG_FILE"

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
    -m "Ralph post-complete fallback commit: $task_id (Claude did not commit)" \
    2>/dev/null || true
  echo "[$ITERATION] POST-COMPLETE FALLBACK COMMIT for $task_id: $(date)" >> "$LOG_FILE"
}

# === State File Commit Helper ===
commit_state_files() {
  local reason="$1"
  git -C "$PROJECT_ROOT" add state/sync.json state/session-log.json 2>/dev/null || true
  git -C "$PROJECT_ROOT" diff --cached --quiet || \
    git -C "$PROJECT_ROOT" commit -m "[claude-docs] state files post-${reason}"
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
  _PREFLIGHT_SENTINEL=$(sync_read "ralph.last_sentinel" 2>/dev/null || echo "null")
  if [[ "$_PREFLIGHT_SENTINEL" == \[TASK_COMPLETE:* ]]; then
    echo "No task assigned — all tasks complete. Entering QC." | tee -a "$LOG_FILE"
    # Fall through to the main loop, which will detect null task_id and run QC.
  else
    echo "No task assigned in sync.json — nothing to do." | tee -a "$LOG_FILE"
    echo "Run /plan to create a spec, or set ralph.task_id in state/sync.json manually."
    echo "=== Stopped: no task assigned at $(date) ===" >> "$LOG_FILE"
    exit 0
  fi
fi

# === Resume: override task_id if --task was given ===
if [[ -n "$RESUME_TASK" ]]; then
  echo "Resuming at task: $RESUME_TASK"
  sync_write "ralph.task_id" "$RESUME_TASK" 2>/dev/null || true
  # Re-read preflight task after override
  PREFLIGHT_TASK_ID="$RESUME_TASK"
  echo "[$RESUME_TASK] Resuming via --task flag: $(date)" >> "$LOG_FILE"
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
HANDOFF_TASK=""        # Set when SESSION_HANDOFF fires — tells next iteration it's a continuation
QC_ROUND=0             # Counts QC loop iterations (post task-completion review)
MAX_QC_ROUNDS=5        # Safety cap — stops runaway QC loops
TASKS_SINCE_CHECKPOINT=0    # Incremented after each successful safety_commit; reset after checkpoint QC
CHECKPOINT_QC_ROUND=0       # Counts checkpoint QC rounds for [CKPT-N] log tags
: "${CHECKPOINT_QC_EVERY:=3}" # Default: fire checkpoint QC every 3 completed tasks; 0 disables

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))

  TASK_ID=$(sync_read "ralph.task_id" 2>/dev/null || echo "")

  if [[ -z "$TASK_ID" || "$TASK_ID" == "null" ]]; then
    # All scheduled tasks complete — enter QC loop if enabled
    _QC_PROMPT="${QC_PROMPT:-$PROJECT_ROOT/scripts/qc-prompt.md}"
    _BRIEF_FILE="${BRIEF_FILE:-$PROJECT_ROOT/brief.md}"

    if [[ "$SKIP_QC" == "true" || ! -f "$_QC_PROMPT" || ! -f "$_BRIEF_FILE" ]]; then
      echo ""
      echo "All tasks complete."
      echo "Completed at iteration $ITERATION of $MAX_ITERATIONS"
      echo "=== Completed: $(date) (iteration $ITERATION) ===" >> "$LOG_FILE"
      exit 0
    fi

    QC_ROUND=$((QC_ROUND + 1))
    if [[ $QC_ROUND -gt $MAX_QC_ROUNDS ]]; then
      echo ""
      echo "STOPPED: QC loop exceeded $MAX_QC_ROUNDS rounds without [QC_COMPLETE]."
      echo "Review brief.md and tasks.md — the QC agent may be identifying the same gaps repeatedly."
      echo "=== Stopped: QC round cap ($MAX_QC_ROUNDS) at $(date) ===" >> "$LOG_FILE"
      exit 1
    fi

    echo ""
    echo "─────────────────────────────────────────"
    echo "  QC Round $QC_ROUND/$MAX_QC_ROUNDS — reviewing against brief.md"
    echo "─────────────────────────────────────────"
    echo "[QC-$QC_ROUND] Starting QC review: $(date)" >> "$LOG_FILE"

    # Pre-QC usage check
    if ! check_usage_before_iteration "QC-$QC_ROUND"; then
      RATE_LIMIT_WAITS=$((RATE_LIMIT_WAITS + 1))
      if [[ $RATE_LIMIT_WAITS -ge $MAX_RATE_LIMIT_WAITS ]]; then
        echo "STOPPED: Hit rate limit $MAX_RATE_LIMIT_WAITS consecutive times."
        echo "=== Stopped: rate limit wait cap ($MAX_RATE_LIMIT_WAITS) at $(date) ===" >> "$LOG_FILE"
        exit 1
      fi
      wait_for_reset "QC-$QC_ROUND" "pre-check"
      ITERATION=$((ITERATION - 1))
      continue
    fi

    _QC_RUN_PROMPT="Read $_QC_PROMPT and review the project against $_BRIEF_FILE."
    _TMPOUT=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/ralph_qc_$$")
    if [[ "$TOOL" == "claude" ]]; then
      claude --dangerously-skip-permissions --print \
        --model "$MODEL" \
        "$_QC_RUN_PROMPT" \
        2>&1 | tee "$_TMPOUT" || true
    else
      echo "$_QC_RUN_PROMPT" \
        | amp --dangerously-allow-all 2>&1 | tee "$_TMPOUT" || true
    fi
    QC_OUTPUT=$(cat "$_TMPOUT" 2>/dev/null || echo "")
    rm -f "$_TMPOUT" 2>/dev/null || true

    if is_rate_limited_output "$QC_OUTPUT"; then
      RATE_LIMIT_WAITS=$((RATE_LIMIT_WAITS + 1))
      if [[ $RATE_LIMIT_WAITS -ge $MAX_RATE_LIMIT_WAITS ]]; then
        echo "STOPPED: Hit rate limit $MAX_RATE_LIMIT_WAITS consecutive times."
        echo "=== Stopped: rate limit wait cap ($MAX_RATE_LIMIT_WAITS) at $(date) ===" >> "$LOG_FILE"
        exit 1
      fi
      wait_for_reset "QC-$QC_ROUND" "mid-execution"
      ITERATION=$((ITERATION - 1))
      continue
    fi
    RATE_LIMIT_WAITS=0

    if echo "$QC_OUTPUT" | grep -q "\[QC_COMPLETE\]"; then
      echo ""
      echo "QC complete — no gaps found against brief.md."
      echo "=== QC_COMPLETE at $(date) (round $QC_ROUND) ===" >> "$LOG_FILE"
      _qc_end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      if [[ ${#TASKS_COMPLETED_SESSION[@]} -gt 0 ]]; then
        _qc_tasks_json=$($PYTHON -c "import sys, json; print(json.dumps(sys.argv[1:]))" \
          "${TASKS_COMPLETED_SESSION[@]}" 2>/dev/null || echo "[]")
      else
        _qc_tasks_json="[]"
      fi
      session_log_append "ralph" "$RALPH_SESSION" "$SESSION_START_ISO" "$_qc_end_iso" \
        "QC_COMPLETE" "0" "$_qc_tasks_json" 2>/dev/null || true
      commit_state_files "QC_COMPLETE"
      exit 0
    fi

    # QC agent should have appended tasks to tasks.md and updated sync.json
    TASK_ID=$(sync_read "ralph.task_id" 2>/dev/null || echo "")
    if [[ -z "$TASK_ID" || "$TASK_ID" == "null" ]]; then
      echo ""
      echo "QC ran but found no new tasks and did not emit [QC_COMPLETE]."
      echo "Check $LOG_FILE and review scripts/qc-prompt.md."
      echo "=== Stopped: QC stalled at $(date) ===" >> "$LOG_FILE"
      echo "[QC-$QC_ROUND] QC stalled — last 80 lines of QC output:" >> "$LOG_FILE"
      echo "$QC_OUTPUT" | tail -n 80 >> "$LOG_FILE"
      echo "[QC-$QC_ROUND] --- end QC output ---" >> "$LOG_FILE"
      session_log_append "ralph" "$RALPH_SESSION" "$SESSION_START_ISO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "QC_STALL" "0" "[]" 2>/dev/null || true
      exit 1
    fi

    echo "  QC identified gaps — resuming execution with $TASK_ID"
    echo "[QC-$QC_ROUND] Gaps found, new task: $TASK_ID: $(date)" >> "$LOG_FILE"
    continue
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

  # --- Build task prompt (base + relevant files from sync.json) ---
  _TASK_PROMPT="Read $_RALPH_PROMPT_EFFECTIVE and execute the task in $SYNC_FILE."
  _RELEVANT_FILES_JSON=$(sync_read "ralph.relevant_files" 2>/dev/null || echo "[]")
  if [[ "$_RELEVANT_FILES_JSON" != "[]" && "$_RELEVANT_FILES_JSON" != "null" && -n "$_RELEVANT_FILES_JSON" ]]; then
    _RELEVANT_FILES_STR=$($PYTHON -c "
import sys, json
try:
    files = json.loads(sys.argv[1])
    if files:
        print(', '.join(files))
except Exception: pass
" "$_RELEVANT_FILES_JSON" 2>/dev/null || echo "")
    if [[ -n "$_RELEVANT_FILES_STR" ]]; then
      _TASK_PROMPT="$_TASK_PROMPT Load these domain files before starting: $_RELEVANT_FILES_STR"
    fi
  fi

  # --- SESSION_HANDOFF continuation note ---
  # If the previous session emitted SESSION_HANDOFF on this same task, inject a
  # continuation note so the new session checks git log before re-doing any work.
  if [[ -n "$HANDOFF_TASK" && "$HANDOFF_TASK" == "$TASK_ID" ]]; then
    _TASK_PROMPT="$_TASK_PROMPT IMPORTANT: This is a SESSION_HANDOFF continuation for $TASK_ID. Run 'git log --oneline -5' first to see what was already committed in the previous session. Complete only what remains — do not redo committed work."
    HANDOFF_TASK=""
  fi

  # --- Run Claude Code or Amp ---
  # Use temp file instead of tee /dev/stderr — more reliable on Windows/Git Bash.
  _TMPOUT=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/ralph_out_$$")
  if [[ "$TOOL" == "claude" ]]; then
    claude --dangerously-skip-permissions --print \
      --model "$MODEL" \
      "$_TASK_PROMPT" \
      2>&1 | tee "$_TMPOUT" || true
  else
    echo "$_TASK_PROMPT" \
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
  # TASK_BLOCKED causes immediate exit — human intervention is required.
  # SESSION_HANDOFF continues the main loop to spawn a fresh Claude session.
  SENTINEL_TYPE=$(detect_sentinel "$OUTPUT" 2>/dev/null || echo "")
  NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$SENTINEL_TYPE" == "TASK_COMPLETE" ]]; then
    sync_write "ralph.last_updated" "$NOW_ISO" 2>/dev/null || true
  elif [[ "$SENTINEL_TYPE" == "TASK_BLOCKED" ]]; then
    BLOCK_REASON=$(extract_block_reason "$OUTPUT" 2>/dev/null || echo "unknown reason")
    sync_write "ralph.last_sentinel" "[TASK_BLOCKED: ${BLOCK_REASON}]" 2>/dev/null || true
    sync_write "ralph.last_updated" "$NOW_ISO" 2>/dev/null || true
    echo "[$ITERATION] TASK_BLOCKED on $TASK_ID: $BLOCK_REASON: $(date)" >> "$LOG_FILE"
    echo "  ⛔ $TASK_ID blocked: $BLOCK_REASON"
    echo ""
    echo "STOPPED: Task blocked — human intervention required."
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
    # Mark this task as a handoff so the next iteration injects a continuation note
    HANDOFF_TASK="$TASK_ID"
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
      sync_write "ralph.last_sentinel" "[TASK_COMPLETE: ${TASK_ID}]" 2>/dev/null || true
      TASKS_COMPLETED_SESSION+=("$TASK_ID")
      session_log_append "ralph" "$RALPH_SESSION" "$SESSION_START_ISO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "TASK_COMPLETE" "0" "[\"${TASK_ID}\"]" 2>/dev/null || true

      # Mark task complete in tasks.md (fallback if Ralph didn't mark the checkbox)
      _spec_tasks="${SPEC_TASKS_FILE:-}"
      if [[ -n "$_spec_tasks" && -f "$_spec_tasks" ]]; then
        $PYTHON -c "
import sys, re
path, tid = sys.argv[1], sys.argv[2]
try:
    with open(path, 'r') as f: content = f.read()
    # Match '- [ ] T001' or '- [ ] T001 · Title' in the checkbox list
    content = re.sub(r'^(- )\[ \] (' + re.escape(tid) + r')(\b.*)',
                     r'\1[x] \2\3', content, flags=re.MULTILINE)
    with open(path, 'w') as f: f.write(content)
except Exception: pass
" "$_spec_tasks" "${TASK_ID}" 2>/dev/null || true

        # Move completed task body to tasks-archive.md
        $PYTHON -c "
import sys, re, os
path, tid = sys.argv[1], sys.argv[2]
try:
    with open(path, 'r') as f: content = f.read()
    m = re.search(r'^(## ' + re.escape(tid) + r'\b[^\n]*\n.*?)(?=^## T|\Z)',
                  content, re.MULTILINE | re.DOTALL)
    if not m: sys.exit(0)
    body = m.group(0)
    new_content = content[:m.start()] + content[m.end():]
    tmp = path + '.tmp'
    with open(tmp, 'w') as f: f.write(new_content)
    os.rename(tmp, path)
    archive_path = os.path.join(os.path.dirname(path), 'tasks-archive.md')
    slug = os.path.basename(os.path.dirname(path))
    if not os.path.exists(archive_path):
        archive_content = '# Archive: ' + slug + '\n\n' + body
    else:
        with open(archive_path, 'r') as f: existing = f.read()
        archive_content = existing.rstrip('\n') + '\n\n' + body
    tmp2 = archive_path + '.tmp'
    with open(tmp2, 'w') as f: f.write(archive_content)
    os.rename(tmp2, archive_path)
except Exception: pass
" "$_spec_tasks" "${TASK_ID}" 2>/dev/null || true
      fi

      # Advance to the next unchecked task, or clear if all done
      _next_task_id=""
      _next_task_title=""
      _next_relevant_files="[]"
      if [[ -n "$_spec_tasks" && -f "$_spec_tasks" ]]; then
        _next_result=$($PYTHON -c "
import sys, re, json
with open(sys.argv[1], 'r') as f:
    content = f.read()
# Find the next unchecked task in the checkbox list
m = re.search(r'^- \[ \] (T[0-9]+)(.*)', content, re.MULTILINE)
if m:
    task_id = m.group(1)
    title = m.group(2).strip().lstrip('\u00b7\u2014- ').strip()
    # Find that task's ## section and extract its Relevant: line
    sec = re.search(r'^## ' + re.escape(task_id) + r'\b[^\n]*\n(.*?)(?=^## T|\Z)',
                    content, re.MULTILINE | re.DOTALL)
    relevant = []
    if sec:
        rel = re.search(r'^Relevant:\s*(.+)$', sec.group(1), re.MULTILINE)
        if rel:
            relevant = [f.strip() for f in rel.group(1).split(',') if f.strip()]
    print(task_id)
    print(title)
    print(json.dumps(relevant))
" "$_spec_tasks" 2>/dev/null || echo "")
        if [[ -n "$_next_result" ]]; then
          _next_task_id=$(echo    "$_next_result" | sed -n '1p')
          _next_task_title=$(echo "$_next_result" | sed -n '2p')
          _next_relevant_files=$(echo "$_next_result" | sed -n '3p')
          [[ -z "$_next_relevant_files" ]] && _next_relevant_files="[]"
        fi
      fi

      if [[ -n "$_next_task_id" ]]; then
        sync_write "ralph.task_id"       "$_next_task_id"       2>/dev/null || true
        sync_write "ralph.task_title"    "$_next_task_title"    2>/dev/null || true
        sync_write "ralph.relevant_files" "$_next_relevant_files" 2>/dev/null || true
        echo "  → Next: $_next_task_id — $_next_task_title"
        echo "[$ITERATION] Advanced to $_next_task_id: $(date)" >> "$LOG_FILE"
      else
        sync_write "ralph.task_id" "null" 2>/dev/null || true
      fi

      # --- Checkpoint QC ---
      TASKS_SINCE_CHECKPOINT=$((TASKS_SINCE_CHECKPOINT + 1))
      if [[ "${CHECKPOINT_QC_EVERY:-3}" -gt 0 && \
            $TASKS_SINCE_CHECKPOINT -ge "${CHECKPOINT_QC_EVERY:-3}" ]]; then
        _ckpt_remaining=0
        _ckpt_spec="${SPEC_TASKS_FILE:-}"
        if [[ -n "$_ckpt_spec" && -f "$_ckpt_spec" ]]; then
          _ckpt_remaining=$($PYTHON -c "
import sys, re
with open(sys.argv[1]) as f: content = f.read()
print(len(re.findall(r'^- \[ \] T[0-9]+', content, re.MULTILINE)))
" "$_ckpt_spec" 2>/dev/null || echo "0")
        fi
        if [[ $_ckpt_remaining -ge 2 ]]; then
          CHECKPOINT_QC_ROUND=$((CHECKPOINT_QC_ROUND + 1))
          _CKPT_QC_PROMPT="${QC_PROMPT:-$PROJECT_ROOT/scripts/qc-prompt.md}"
          _CKPT_BRIEF_FILE="${BRIEF_FILE:-$PROJECT_ROOT/brief.md}"
          echo ""
          echo "─────────────────────────────────────────"
          echo "  Checkpoint QC $CHECKPOINT_QC_ROUND — reviewing after $TASKS_SINCE_CHECKPOINT tasks"
          echo "─────────────────────────────────────────"
          echo "[CKPT-$CHECKPOINT_QC_ROUND] Starting checkpoint QC: $(date)" >> "$LOG_FILE"
          if [[ "$SKIP_QC" != "true" && -f "$_CKPT_QC_PROMPT" && -f "$_CKPT_BRIEF_FILE" ]]; then
            if ! check_usage_before_iteration "CKPT-$CHECKPOINT_QC_ROUND"; then
              RATE_LIMIT_WAITS=$((RATE_LIMIT_WAITS + 1))
              if [[ $RATE_LIMIT_WAITS -ge $MAX_RATE_LIMIT_WAITS ]]; then
                echo "STOPPED: Hit rate limit $MAX_RATE_LIMIT_WAITS consecutive times."
                echo "=== Stopped: rate limit wait cap ($MAX_RATE_LIMIT_WAITS) at $(date) ===" >> "$LOG_FILE"
                exit 1
              fi
              wait_for_reset "CKPT-$CHECKPOINT_QC_ROUND" "pre-check"
            fi
            _CKPT_RUN_PROMPT="Read $_CKPT_QC_PROMPT and review the project against $_CKPT_BRIEF_FILE."
            _TMPOUT=$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/ralph_ckpt_$$")
            if [[ "$TOOL" == "claude" ]]; then
              claude --dangerously-skip-permissions --print \
                --model "$MODEL" "$_CKPT_RUN_PROMPT" \
                2>&1 | tee "$_TMPOUT" || true
            else
              echo "$_CKPT_RUN_PROMPT" \
                | amp --dangerously-allow-all 2>&1 | tee "$_TMPOUT" || true
            fi
            CKPT_OUTPUT=$(cat "$_TMPOUT" 2>/dev/null || echo "")
            rm -f "$_TMPOUT" 2>/dev/null || true

            if is_rate_limited_output "$CKPT_OUTPUT"; then
              RATE_LIMIT_WAITS=$((RATE_LIMIT_WAITS + 1))
              if [[ $RATE_LIMIT_WAITS -ge $MAX_RATE_LIMIT_WAITS ]]; then
                echo "STOPPED: Hit rate limit $MAX_RATE_LIMIT_WAITS consecutive times."
                echo "=== Stopped: rate limit wait cap ($MAX_RATE_LIMIT_WAITS) at $(date) ===" >> "$LOG_FILE"
                exit 1
              fi
              wait_for_reset "CKPT-$CHECKPOINT_QC_ROUND" "mid-execution"
              echo "[CKPT-$CHECKPOINT_QC_ROUND] Rate limited — counter not reset; will retry after next task: $(date)" >> "$LOG_FILE"
              # Don't reset TASKS_SINCE_CHECKPOINT — will retry on next completed task
            else
              RATE_LIMIT_WAITS=0
              if echo "$CKPT_OUTPUT" | grep -q "\[QC_COMPLETE\]"; then
                echo ""
                echo "  ✓ Checkpoint QC $CHECKPOINT_QC_ROUND — no gaps found"
                echo "[CKPT-$CHECKPOINT_QC_ROUND] QC_COMPLETE — no gaps: $(date)" >> "$LOG_FILE"
              else
                _ckpt_new_task=$(sync_read "ralph.task_id" 2>/dev/null || echo "")
                if [[ -z "$_ckpt_new_task" || "$_ckpt_new_task" == "null" ]]; then
                  echo "[CKPT-$CHECKPOINT_QC_ROUND] QC stalled — last 80 lines of QC output:" >> "$LOG_FILE"
                  echo "$CKPT_OUTPUT" | tail -n 80 >> "$LOG_FILE"
                  echo "[CKPT-$CHECKPOINT_QC_ROUND] --- end QC output ---" >> "$LOG_FILE"
                fi
                echo "  Checkpoint QC $CHECKPOINT_QC_ROUND identified gaps — resuming with ${_ckpt_new_task:-next task}"
                echo "[CKPT-$CHECKPOINT_QC_ROUND] Gaps found, resuming with ${_ckpt_new_task:-next task}: $(date)" >> "$LOG_FILE"
              fi
              TASKS_SINCE_CHECKPOINT=0
            fi
          else
            echo "[CKPT-$CHECKPOINT_QC_ROUND] Skipped (SKIP_QC or missing files): $(date)" >> "$LOG_FILE"
            TASKS_SINCE_CHECKPOINT=0
          fi
        fi
      fi

      # Reset both counters on clean success
      STALL_COUNT=0
      BUILD_FAIL_COUNT=0
      LAST_FAILED_TASK=""
      HANDOFF_TASK=""

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
        session_log_append "ralph" "$RALPH_SESSION" "$SESSION_START_ISO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          "BUILD_FAIL" "0" "[]" 2>/dev/null || true
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
      session_log_append "ralph" "$RALPH_SESSION" "$SESSION_START_ISO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "STALL" "0" "[]" 2>/dev/null || true
      commit_state_files "stall-exit"
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
session_log_append "ralph" "$RALPH_SESSION" "$SESSION_START_ISO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "MAX_ITER" "0" "[]" 2>/dev/null || true
commit_state_files "max-iter"
exit 1