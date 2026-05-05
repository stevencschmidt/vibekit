#!/usr/bin/env bash
# archive-completed-tasks.sh — One-shot migration helper.
# Moves completed task bodies from tasks.md to tasks-archive.md.
# Idempotent: running twice is a no-op (no [x] task bodies remain in tasks.md to extract).
# Usage: bash scripts/archive-completed-tasks.sh [PROJECT_ROOT]
#   PROJECT_ROOT defaults to the parent of this script's directory (vibekit root).
#   Pass a different path to run against another vibekit-scaffolded project, e.g.:
#     bash scripts/archive-completed-tasks.sh /path/to/sandbox/ragtest

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Resolve Python
if command -v python3 >/dev/null 2>&1 && python3 -c "import sys; assert sys.version_info[0]==3" 2>/dev/null; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1 && python -c "import sys; assert sys.version_info[0]==3" 2>/dev/null; then
  PYTHON="python"
else
  echo "ERROR: python3 not found" >&2
  exit 1
fi

# shellcheck source=../vibekit.config.sh
source "$PROJECT_ROOT/vibekit.config.sh"

TASKS_FILE="${SPEC_TASKS_FILE:-}"

if [[ -z "$TASKS_FILE" || ! -f "$TASKS_FILE" ]]; then
  echo "SPEC_TASKS_FILE is unset or missing — nothing to do."
  exit 0
fi

echo "Archiving completed task bodies from: $TASKS_FILE"

"$PYTHON" - "$TASKS_FILE" <<'PYEOF'
import sys, re, os

path = sys.argv[1]

with open(path, 'r') as f:
    content = f.read()

completed = re.findall(r'^- \[x\] (T[0-9]+)', content, re.MULTILINE)

if not completed:
    print("No completed tasks found in checkbox list.")
    sys.exit(0)

print(f"Found {len(completed)} completed task(s): {', '.join(completed)}")

archive_path = os.path.join(os.path.dirname(path), 'tasks-archive.md')
slug = os.path.basename(os.path.dirname(path))
archived_count = 0

for tid in completed:
    m = re.search(r'^(## ' + re.escape(tid) + r'\b[^\n]*\n.*?)(?=^## T|\Z)',
                  content, re.MULTILINE | re.DOTALL)
    if not m:
        print(f"  {tid}: body not found in tasks.md (already archived or missing)")
        continue

    body = m.group(0)
    content = content[:m.start()] + content[m.end():]

    if not os.path.exists(archive_path):
        archive_content = '# Archive: ' + slug + '\n\n' + body
    else:
        with open(archive_path, 'r') as f:
            existing = f.read()
        archive_content = existing.rstrip('\n') + '\n\n' + body

    tmp = archive_path + '.tmp'
    with open(tmp, 'w') as f:
        f.write(archive_content)
    os.rename(tmp, archive_path)

    archived_count += 1
    print(f"  {tid}: archived")

tmp = path + '.tmp'
with open(tmp, 'w') as f:
    f.write(content)
os.rename(tmp, path)

print(f"Done. Archived {archived_count} task(s).")
PYEOF
