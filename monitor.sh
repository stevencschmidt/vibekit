#!/usr/bin/env bash
# scripts/monitor.sh — Shared sentinel detection functions
# Source this file in all layer scripts: source "$(dirname "$0")/../scripts/monitor.sh"
#
# Sentinel formats (from sentinel-protocol contract):
#   [TASK_COMPLETE: T###]
#   [TASK_BLOCKED: <reason>]
#   [SESSION_HANDOFF]

# detect_sentinel <output>
# Prints the sentinel type found in output: TASK_COMPLETE, TASK_BLOCKED, SESSION_HANDOFF, or empty.
# Returns 0 if a sentinel was detected, 1 if none found.
detect_sentinel() {
  local output="$1"
  if echo "$output" | grep -qE '\[TASK_COMPLETE: T[0-9]+\]'; then
    echo "TASK_COMPLETE"
    return 0
  elif echo "$output" | grep -q '\[TASK_BLOCKED:'; then
    echo "TASK_BLOCKED"
    return 0
  elif echo "$output" | grep -q '\[SESSION_HANDOFF\]'; then
    echo "SESSION_HANDOFF"
    return 0
  fi
  return 1
}

# extract_task_id <output>
# Extracts the task ID (e.g. T042) from a [TASK_COMPLETE: T042] sentinel.
# Prints the task ID on success. Prints nothing and returns 1 if not found.
extract_task_id() {
  local output="$1"
  local match
  match=$(echo "$output" | grep -oE '\[TASK_COMPLETE: T[0-9]+\]' | head -1)
  if [ -z "$match" ]; then
    return 1
  fi
  # Strip brackets and prefix to isolate T###
  echo "$match" | grep -oE 'T[0-9]+'
}

# extract_block_reason <output>
# Extracts the reason string from a [TASK_BLOCKED: <reason>] sentinel.
# Prints the reason on success. Prints nothing and returns 1 if not found.
extract_block_reason() {
  local output="$1"
  local match
  match=$(echo "$output" | grep -o '\[TASK_BLOCKED: [^]]*\]' | head -1)
  if [ -z "$match" ]; then
    return 1
  fi
  # Strip the surrounding sentinel markers to get just the reason
  echo "$match" | sed 's/^\[TASK_BLOCKED: //;s/\]$//'
}
