#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Project detection — exit silently when not in a vibekit project
[[ -f "$(pwd)/vibekit.config.sh" ]] || exit 0

# Resolve Python interpreter
PYTHON=""
if python3 -c "import sys; sys.exit(0)" 2>/dev/null; then
  PYTHON="python3"
elif python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
  PYTHON="python"
fi

(
  set +e

  SYNC_FILE="$(pwd)/state/sync.json"
  LOG_FILE="$(pwd)/state/ralph.log"
  TASK_ID="null"
  LAST_SENTINEL=""
  LAST_LOG=""

  # Read task_id and last_sentinel in one Python invocation
  if [[ -f "$SYNC_FILE" ]] && [[ -n "$PYTHON" ]]; then
    _py_out="$("$PYTHON" -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    r = d.get('ralph', {})
    print(r.get('task_id') or 'null')
    print(r.get('last_sentinel') or '')
except:
    print('null')
    print('')
" "$SYNC_FILE" 2>/dev/null)"
    TASK_ID="$(printf '%s\n' "$_py_out" | sed -n '1p')"
    LAST_SENTINEL="$(printf '%s\n' "$_py_out" | sed -n '2p')"
  elif [[ -f "$SYNC_FILE" ]] && command -v jq >/dev/null 2>&1; then
    TASK_ID="$(jq -r '.ralph.task_id // "null"' "$SYNC_FILE" 2>/dev/null)"
    LAST_SENTINEL="$(jq -r '.ralph.last_sentinel // ""' "$SYNC_FILE" 2>/dev/null)"
  fi

  # Read last 50 lines of ralph.log
  [[ -f "$LOG_FILE" ]] && LAST_LOG="$(tail -n 50 "$LOG_FILE")"

  # Priority-ordered status detection

  # 1. QC complete
  if [[ "$LAST_SENTINEL" == "[QC_COMPLETE]" ]] || printf '%s\n' "$LAST_LOG" | grep -qE "^=== QC_COMPLETE"; then
    printf 'vibekit · ✓ QC_COMPLETE\n'
    exit 0
  fi

  # 2. Stalled
  if printf '%s\n' "$LAST_LOG" | tail -1 | grep -qE "^=== Stopped:"; then
    printf 'vibekit · ⚠ STALLED — see ralph.log\n'
    exit 0
  fi

  # 3. Rate limited (T023 structured log line)
  RATE_LINE="$(printf '%s\n' "$LAST_LOG" | grep "RATE_LIMIT until" | tail -1)"
  if [[ -n "$RATE_LINE" ]]; then
    RESET_STR="$(printf '%s\n' "$RATE_LINE" | sed 's/.*RATE_LIMIT until \([^(]*\).*/\1/' | xargs)"
    STATUS_RL="vibekit · ⏳ rate limit, resuming --:--"
    if [[ -n "$RESET_STR" ]]; then
      RESET_EPOCH="$(date -d "$RESET_STR" +%s 2>/dev/null)"
      if [[ -n "$RESET_EPOCH" ]]; then
        NOW_EPOCH="$(date +%s)"
        REMAINING=$(( RESET_EPOCH - NOW_EPOCH ))
        [[ $REMAINING -lt 0 ]] && REMAINING=$(( REMAINING + 86400 ))
        MINS=$(( REMAINING / 60 ))
        SECS=$(( REMAINING % 60 ))
        STATUS_RL="$(printf 'vibekit · ⏳ rate limit, resuming %02d:%02d' "$MINS" "$SECS")"
      fi
    fi
    printf '%s\n' "$STATUS_RL"
    exit 0
  fi

  # 4. QC running
  QC_ROUND="$(printf '%s\n' "$LAST_LOG" | grep -oE "QC Round [0-9]+" | tail -1 | grep -oE "[0-9]+")"
  if [[ -n "$QC_ROUND" ]]; then
    printf 'vibekit · QC round %s\n' "$QC_ROUND"
    exit 0
  fi

  # 5. Running
  if [[ -n "$TASK_ID" && "$TASK_ID" != "null" ]]; then
    ITER_LINE="$(printf '%s\n' "$LAST_LOG" | grep -oE 'Iteration [0-9]+/[0-9]+' | tail -1)"
    if [[ -n "$ITER_LINE" ]]; then
      ITER_NUMS="$(printf '%s\n' "$ITER_LINE" | grep -oE '[0-9]+/[0-9]+')"
      printf 'vibekit · %s iter %s\n' "$TASK_ID" "$ITER_NUMS"
    else
      printf 'vibekit · %s running\n' "$TASK_ID"
    fi
    exit 0
  fi

  # 6. Idle
  printf 'vibekit · idle\n'
) 2>/dev/null || true
