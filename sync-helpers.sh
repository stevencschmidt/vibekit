#!/usr/bin/env bash
# scripts/sync-helpers.sh
# Shared JSON helpers for reading/writing sync.json and session-log.json.
# Source this file — do not execute it directly.
# Requires: SYNC_FILE and SESSION_LOG_FILE (set in vibekit.config.sh).
#
# Usage:
#   source scripts/sync-helpers.sh
#   value=$(sync_read "execution.phase")
#   sync_write "execution.current_task_status" "in_progress"
#   session_log_append "ralph" 3 "2026-03-18T10:00:00Z" "2026-03-18T11:00:00Z" "TASK_COMPLETE" 45000 '["T001"]'

# ---------------------------------------------------------------------------
# sync_read <field_path>
#
# Read a single field from sync.json using dot-notation.
# Examples:
#   sync_read "execution.phase"       → "execution"
#   sync_read "architect.pending_decision"  → "false"
#   sync_read "ralph.acceptance_criteria"   → JSON array string
#
# Returns: plain string for string/number/bool/null, JSON for objects/arrays.
# Uses python3 (primary). Falls back to jq if python3 is unavailable.
# Exit codes: 0 = success, 1 = error (message written to stderr).
# ---------------------------------------------------------------------------
sync_read() {
    local field_path="$1"

    if [[ -z "$field_path" ]]; then
        echo "sync_read: field_path argument is required" >&2
        return 1
    fi

    if [[ -z "$SYNC_FILE" ]]; then
        echo "sync_read: SYNC_FILE is not set — source vibekit.config.sh first" >&2
        return 1
    fi

    if [[ ! -f "$SYNC_FILE" ]]; then
        echo "sync_read: sync.json not found: $SYNC_FILE" >&2
        return 1
    fi

    # Resolve python3 interpreter: prefer python3, fall back to python (if Python 3)
    local _py=""
    if python3 -c "import sys; sys.exit(0)" 2>/dev/null; then
        _py="python3"
    elif python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
        _py="python"
    fi

    if [[ -n "$_py" ]]; then
        "$_py" - "$SYNC_FILE" "$field_path" <<'PYEOF'
import sys, json

sync_file = sys.argv[1]
field_path = sys.argv[2]

try:
    with open(sync_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"sync_read: failed to parse {sync_file}: {e}", file=sys.stderr)
    sys.exit(1)

keys = field_path.split('.')
value = data
for key in keys:
    if not isinstance(value, dict) or key not in value:
        print(f"sync_read: key '{key}' not found in path '{field_path}'", file=sys.stderr)
        sys.exit(1)
    value = value[key]

if value is None:
    print("null")
elif isinstance(value, bool):
    print(str(value).lower())
elif isinstance(value, (int, float)):
    print(value)
elif isinstance(value, str):
    print(value)
else:
    # Lists and dicts: return as JSON
    print(json.dumps(value))
PYEOF
    elif command -v jq >/dev/null 2>&1; then
        # jq fallback when no Python 3 interpreter is available
        local jq_path=".${field_path}"
        jq -r "${jq_path} // \"null\"" "$SYNC_FILE"
    else
        echo "sync_read: no Python 3 interpreter found and jq is not available" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# sync_write <field_path> <value>
#
# Write a single field in sync.json using dot-notation.
# Value type is inferred: JSON-parseable values (true, false, null, numbers,
# arrays, objects) are written as their native JSON types; everything else is
# written as a string.
# Examples:
#   sync_write "execution.current_task_status" "in_progress"
#   sync_write "architect.pending_decision" "true"
#   sync_write "execution.version" "2"
#   sync_write "ralph.last_sentinel" "null"
#   sync_write "ralph.acceptance_criteria" '["criterion 1","criterion 2"]'
#
# Writes atomically via a temp file + rename to avoid corrupt state on crash.
# Uses python3 (primary). Falls back to jq if python3 is unavailable.
# Exit codes: 0 = success, 1 = error (message written to stderr).
# ---------------------------------------------------------------------------
sync_write() {
    local field_path="$1"
    local value="$2"

    if [[ -z "$field_path" ]]; then
        echo "sync_write: field_path argument is required" >&2
        return 1
    fi

    if [[ -z "$SYNC_FILE" ]]; then
        echo "sync_write: SYNC_FILE is not set — source vibekit.config.sh first" >&2
        return 1
    fi

    if [[ ! -f "$SYNC_FILE" ]]; then
        echo "sync_write: sync.json not found: $SYNC_FILE" >&2
        return 1
    fi

    # Resolve python3 interpreter: prefer python3, fall back to python (if Python 3)
    local _py=""
    if python3 -c "import sys; sys.exit(0)" 2>/dev/null; then
        _py="python3"
    elif python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
        _py="python"
    fi

    if [[ -n "$_py" ]]; then
        "$_py" - "$SYNC_FILE" "$field_path" "$value" <<'PYEOF'
import sys, json, os, tempfile

sync_file  = sys.argv[1]
field_path = sys.argv[2]
raw_value  = sys.argv[3]

# Type inference: try JSON parse first (handles bool, null, numbers, arrays,
# objects); fall back to treating value as a plain string.
try:
    value = json.loads(raw_value)
except (json.JSONDecodeError, ValueError):
    value = raw_value

try:
    with open(sync_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"sync_write: failed to parse {sync_file}: {e}", file=sys.stderr)
    sys.exit(1)

keys = field_path.split('.')
obj  = data
for key in keys[:-1]:
    if not isinstance(obj, dict) or key not in obj:
        print(f"sync_write: key '{key}' not found in path '{field_path}'", file=sys.stderr)
        sys.exit(1)
    obj = obj[key]

last_key = keys[-1]
if not isinstance(obj, dict):
    print(f"sync_write: cannot set '{last_key}' — parent is not an object", file=sys.stderr)
    sys.exit(1)

obj[last_key] = value

# Atomic write: temp file in same directory → rename
sync_dir = os.path.dirname(os.path.abspath(sync_file))
tmp_path = None
try:
    fd, tmp_path = tempfile.mkstemp(dir=sync_dir, suffix='.tmp')
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    os.replace(tmp_path, sync_file)
except Exception as e:
    print(f"sync_write: failed to write {sync_file}: {e}", file=sys.stderr)
    if tmp_path and os.path.exists(tmp_path):
        os.unlink(tmp_path)
    sys.exit(1)
PYEOF
    elif command -v jq >/dev/null 2>&1; then
        # jq fallback: --argjson treats value as native JSON; fall back to --arg (string)
        local jq_path=".${field_path}"
        local tmp_file="${SYNC_FILE}.tmp"
        if jq --argjson v "$value" "${jq_path} = \$v" "$SYNC_FILE" > "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$SYNC_FILE"
        else
            jq --arg v "$value" "${jq_path} = \$v" "$SYNC_FILE" > "$tmp_file" \
                && mv "$tmp_file" "$SYNC_FILE"
        fi
    else
        echo "sync_write: no Python 3 interpreter found and jq is not available" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# session_log_append <layer> <session> <started> <ended> <exit_reason> <estimated_tokens> <tasks_completed>
#
# Append a session record to state/session-log.json per data-model.md entity #6.
# Arguments:
#   layer             — architect | supervisor | ralph
#   session           — integer session number
#   started           — ISO-8601 start timestamp
#   ended             — ISO-8601 end timestamp
#   exit_reason       — TASK_COMPLETE | TASK_BLOCKED | SESSION_HANDOFF | ERROR
#   estimated_tokens  — integer token count estimate
#   tasks_completed   — JSON array string, e.g. '["T001","T002"]'
#
# Example:
#   session_log_append "ralph" 3 "2026-03-18T10:00:00Z" "2026-03-18T11:00:00Z" "TASK_COMPLETE" 45000 '["T001"]'
#
# Writes atomically via a temp file + rename.
# Uses python3 (primary). Falls back to jq if python3 is unavailable.
# Exit codes: 0 = success, 1 = error (message written to stderr).
# ---------------------------------------------------------------------------
session_log_append() {
    local layer="$1"
    local session="$2"
    local started="$3"
    local ended="$4"
    local exit_reason="$5"
    local estimated_tokens="$6"
    local tasks_completed="$7"

    if [[ -z "$layer" || -z "$session" || -z "$started" || -z "$ended" || -z "$exit_reason" ]]; then
        echo "session_log_append: required arguments: layer session started ended exit_reason [estimated_tokens] [tasks_completed]" >&2
        return 1
    fi

    if [[ -z "$SESSION_LOG_FILE" ]]; then
        echo "session_log_append: SESSION_LOG_FILE is not set — source vibekit.config.sh first" >&2
        return 1
    fi

    if [[ ! -f "$SESSION_LOG_FILE" ]]; then
        echo "session_log_append: session-log.json not found: $SESSION_LOG_FILE" >&2
        return 1
    fi

    # Default optional args
    estimated_tokens="${estimated_tokens:-0}"
    tasks_completed="${tasks_completed:-[]}"

    # Resolve python3 interpreter: prefer python3, fall back to python (if Python 3)
    local _py=""
    if python3 -c "import sys; sys.exit(0)" 2>/dev/null; then
        _py="python3"
    elif python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
        _py="python"
    fi

    if [[ -n "$_py" ]]; then
        "$_py" - "$SESSION_LOG_FILE" "$layer" "$session" "$started" "$ended" \
                 "$exit_reason" "$estimated_tokens" "$tasks_completed" <<'PYEOF'
import sys, json, os, tempfile

log_file       = sys.argv[1]
layer          = sys.argv[2]
session        = sys.argv[3]
started        = sys.argv[4]
ended          = sys.argv[5]
exit_reason    = sys.argv[6]
raw_tokens     = sys.argv[7]
raw_tasks      = sys.argv[8]

# Parse numeric fields
try:
    session_num = int(session)
except ValueError:
    print(f"session_log_append: session must be an integer, got: {session}", file=sys.stderr)
    sys.exit(1)

try:
    tokens = int(raw_tokens)
except ValueError:
    print(f"session_log_append: estimated_tokens must be an integer, got: {raw_tokens}", file=sys.stderr)
    sys.exit(1)

# Parse tasks_completed JSON array
try:
    tasks = json.loads(raw_tasks)
    if not isinstance(tasks, list):
        raise ValueError("not a list")
except (json.JSONDecodeError, ValueError) as e:
    print(f"session_log_append: tasks_completed must be a JSON array, got: {raw_tasks} ({e})", file=sys.stderr)
    sys.exit(1)

# Load existing log
try:
    with open(log_file, 'r') as f:
        log = json.load(f)
    if not isinstance(log, list):
        print(f"session_log_append: {log_file} is not a JSON array", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f"session_log_append: failed to parse {log_file}: {e}", file=sys.stderr)
    sys.exit(1)

# Build new record
record = {
    "layer":             layer,
    "session":           session_num,
    "started":           started,
    "ended":             ended,
    "exit_reason":       exit_reason,
    "estimated_tokens":  tokens,
    "tasks_completed":   tasks,
}
log.append(record)

# Atomic write: temp file in same directory → rename
log_dir = os.path.dirname(os.path.abspath(log_file))
tmp_path = None
try:
    fd, tmp_path = tempfile.mkstemp(dir=log_dir, suffix='.tmp')
    with os.fdopen(fd, 'w') as f:
        json.dump(log, f, indent=2)
        f.write('\n')
    os.replace(tmp_path, log_file)
except Exception as e:
    print(f"session_log_append: failed to write {log_file}: {e}", file=sys.stderr)
    if tmp_path and os.path.exists(tmp_path):
        os.unlink(tmp_path)
    sys.exit(1)
PYEOF
    elif command -v jq >/dev/null 2>&1; then
        # jq fallback: parse tasks_completed as JSON, fall back to empty array on error
        local tasks_json
        tasks_json=$(echo "$tasks_completed" | jq '.' 2>/dev/null) || tasks_json="[]"
        local record
        record=$(jq -n \
            --arg     layer            "$layer" \
            --argjson session          "$session" \
            --arg     started          "$started" \
            --arg     ended            "$ended" \
            --arg     exit_reason      "$exit_reason" \
            --argjson estimated_tokens "$estimated_tokens" \
            --argjson tasks_completed  "$tasks_json" \
            '{layer: $layer, session: $session, started: $started, ended: $ended,
              exit_reason: $exit_reason, estimated_tokens: $estimated_tokens,
              tasks_completed: $tasks_completed}')
        local tmp_file="${SESSION_LOG_FILE}.tmp"
        jq --argjson rec "$record" '. + [$rec]' "$SESSION_LOG_FILE" > "$tmp_file" \
            && mv "$tmp_file" "$SESSION_LOG_FILE"
    else
        echo "session_log_append: no Python 3 interpreter found and jq is not available" >&2
        return 1
    fi
}
