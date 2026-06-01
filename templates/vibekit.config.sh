#!/usr/bin/env bash
# vibekit.config.sh — Project-specific configuration for Ralph
# This file is sourced by scripts/ralph.sh before execution.
# Edit this file to configure your project.

# === Tool & Model ===
TOOL="claude"           # claude | amp
MODEL="claude-sonnet-4-6"

# === Complexity-based model routing (spec 007) ===
MODEL_AUTO="true"                         # "false" → every task uses $MODEL (pre-007 behavior)
MODEL_SIMPLE="claude-haiku-4-5-20251001"  # tier: simple
MODEL_MEDIUM="claude-sonnet-4-6"          # tier: medium (also the untagged fallback)
MODEL_COMPLEX="claude-opus-4-7"           # tier: complex
MODEL_QC="claude-opus-4-7"                # both QC stages always use this

# === Timeout & Recovery ===
# RALPH_TASK_TIMEOUT=1800   # seconds before a hung agent session is killed; 0 disables. Default 1800 (set in ralph.sh).

# === File Paths ===
# PROJECT_ROOT is set by ralph.sh before sourcing this file.
SYNC_FILE="$PROJECT_ROOT/state/sync.json"
SESSION_LOG_FILE="$PROJECT_ROOT/state/session-log.json"
RALPH_PROMPT="$PROJECT_ROOT/scripts/ralph-prompt.md"
DECISIONS_FILE="$PROJECT_ROOT/state/decisions.md"
LOG_FILE="$PROJECT_ROOT/state/ralph.log"

# Path to the tasks.md for the current spec.
# Update this each time you start a new spec.
SPEC_TASKS_FILE="$PROJECT_ROOT/specs/001-slug/tasks.md"

# === Domain Skills ===
# List skill names to inject into Ralph's prompt via {{SKILLS_CONTEXT}}.
# Each name maps to skills/<name>/manifest.md under PROJECT_ROOT.
# Example: SKILLS=("typescript" "react")
SKILLS=()

# === Build Verification ===
# Called after each task completion. Return 0 = pass, non-zero = fail.
# Ralph rolls back and retries on failure.
# Example: npm test, cargo test, pytest, etc.
verify_build() {
  return 0
}
