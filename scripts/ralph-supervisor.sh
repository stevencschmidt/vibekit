#!/usr/bin/env bash
# Ralph Supervisor — Wraps ralph.sh with rate-limit auto-resume.
# Usage: ./ralph-supervisor.sh [--max-relaunch N] [ralph.sh args...]
#
# When ralph.sh exits with RALPH_EXIT_RATE_LIMIT (75/EX_TEMPFAIL), the supervisor
# relaunches immediately — ralph.sh handles the reset countdown on its next
# pre-iteration usage check. Any other exit code (0=complete, 1=stall/block/
# verify-fail, 130=interrupted) passes through unchanged: real failures still
# require human review. systemd handles reboot survival (Restart=no). See DECISION:014.
#
# Cross-reference: RALPH_EXIT_RATE_LIMIT must match the constant in ralph.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RALPH_EXIT_RATE_LIMIT=75

MAX_RELAUNCH=100
RELAUNCH_COUNT=0
_INTERRUPTED=0

RALPH_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-relaunch)   MAX_RELAUNCH="$2"; shift 2 ;;
    --max-relaunch=*) MAX_RELAUNCH="${1#*=}"; shift ;;
    *) RALPH_ARGS+=("$1"); shift ;;
  esac
done

_supervisor_interrupted() {
  _INTERRUPTED=1
  echo ""
  echo "Supervisor: interrupted — not relaunching."
}
trap '_supervisor_interrupted' SIGINT SIGTERM

while true; do
  rc=0
  bash "$SCRIPT_DIR/ralph.sh" "${RALPH_ARGS[@]}" || rc=$?

  if [[ "$_INTERRUPTED" -eq 1 ]]; then
    echo "Supervisor: stopped by signal (rc=$rc)."
    exit $rc
  fi

  if [[ $rc -eq $RALPH_EXIT_RATE_LIMIT ]]; then
    if [[ $RELAUNCH_COUNT -ge $MAX_RELAUNCH ]]; then
      echo "Supervisor: reached --max-relaunch $MAX_RELAUNCH limit — stopping."
      exit $RALPH_EXIT_RATE_LIMIT
    fi
    RELAUNCH_COUNT=$((RELAUNCH_COUNT + 1))
    echo "Supervisor: rate-limit exit — relaunching ($RELAUNCH_COUNT/$MAX_RELAUNCH)"
    continue
  fi

  exit $rc
done
