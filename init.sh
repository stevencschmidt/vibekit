#!/usr/bin/env bash
# init.sh — Scaffold vibekit into a target project
#
# Usage: ./init.sh <target-dir> [project-name]
#
# Creates the full vibekit project structure in <target-dir>:
#   scripts/        — runtime scripts (ralph, sync-helpers, monitor, ralph-prompt, qc-prompt, sync-agent)
#   state/          — sync.json, session-log.json, decisions.md
#   docs/claude/    — knowledge graph domain files
#   .claude/skills/ — plan and knowledge-graph-sync skills
#   .claude/        — settings.json
#   vibekit.config.sh
#   CLAUDE.md       — router template
#
# Deps: bash, python3 (or python), git

set -e

VIBEKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve Python interpreter (needed for PROJECT_NAME substitution and validation)
_INIT_PY=""
if python3 -c "import sys; sys.exit(0)" 2>/dev/null; then
    _INIT_PY="python3"
elif python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
    _INIT_PY="python"
fi

if [[ -z "$_INIT_PY" ]]; then
    echo "Error: python3 is required but not found. Install Python 3 and retry."
    exit 1
fi

# === Args ===
TARGET_DIR="${1:-}"
PROJECT_NAME="${2:-MyProject}"

if [[ -z "$TARGET_DIR" ]]; then
  echo "Usage: ./init.sh <target-dir> [project-name]"
  echo ""
  echo "Examples:"
  echo "  ./init.sh ~/my-project \"My Project\""
  echo "  ./init.sh . \"My Project\"   # scaffold into current directory"
  exit 1
fi

# Resolve to absolute path
TARGET_DIR="$(mkdir -p "$TARGET_DIR" && cd "$TARGET_DIR" && pwd)"

echo ""
echo "============================================"
echo "  vibekit init"
echo "============================================"
echo "  Target:       $TARGET_DIR"
echo "  Project name: $PROJECT_NAME"
echo "  vibekit:      $VIBEKIT_DIR"
echo "============================================"
echo ""

# === 1. Create directory structure ===
echo "Creating directory structure..."
mkdir -p "$TARGET_DIR/scripts"
mkdir -p "$TARGET_DIR/state"
mkdir -p "$TARGET_DIR/docs/claude"
mkdir -p "$TARGET_DIR/specs"
mkdir -p "$TARGET_DIR/skills"
mkdir -p "$TARGET_DIR/.claude/skills/vibeplan"
mkdir -p "$TARGET_DIR/.claude/skills/knowledge-graph-sync"

# === 2. Copy scripts/ verbatim ===
echo "Copying scripts..."
cp "$VIBEKIT_DIR/scripts/ralph.sh"         "$TARGET_DIR/scripts/ralph.sh"
cp "$VIBEKIT_DIR/scripts/sync-helpers.sh"  "$TARGET_DIR/scripts/sync-helpers.sh"
cp "$VIBEKIT_DIR/scripts/monitor.sh"       "$TARGET_DIR/scripts/monitor.sh"
cp "$VIBEKIT_DIR/scripts/ralph-prompt.md"  "$TARGET_DIR/scripts/ralph-prompt.md"
cp "$VIBEKIT_DIR/scripts/qc-prompt.md"     "$TARGET_DIR/scripts/qc-prompt.md"
cp "$VIBEKIT_DIR/scripts/sync-agent.sh"    "$TARGET_DIR/scripts/sync-agent.sh"
chmod +x "$TARGET_DIR/scripts/ralph.sh"
chmod +x "$TARGET_DIR/scripts/sync-agent.sh"

# === 3. Copy and substitute templates ===
echo "Copying templates..."

# vibekit.config.sh — substitute PROJECT_NAME (Python handles special characters safely)
$_INIT_PY -c "
import sys
src, dst, name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, 'r') as f: content = f.read()
with open(dst, 'w') as f: f.write(content.replace('PROJECT_NAME', name))
" "$VIBEKIT_DIR/templates/vibekit.config.sh" "$TARGET_DIR/vibekit.config.sh" "$PROJECT_NAME"

# CLAUDE.md — substitute PROJECT_NAME
$_INIT_PY -c "
import sys
src, dst, name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, 'r') as f: content = f.read()
with open(dst, 'w') as f: f.write(content.replace('PROJECT_NAME', name))
" "$VIBEKIT_DIR/templates/CLAUDE.md" "$TARGET_DIR/CLAUDE.md" "$PROJECT_NAME"

# state files
cp "$VIBEKIT_DIR/templates/state/sync.json"         "$TARGET_DIR/state/sync.json"
cp "$VIBEKIT_DIR/templates/state/session-log.json"  "$TARGET_DIR/state/session-log.json"
cp "$VIBEKIT_DIR/templates/state/decisions.md"      "$TARGET_DIR/state/decisions.md"

# docs/claude domain stubs (only if they don't exist — don't overwrite on re-init)
for f in decisions.md architecture.md conventions.md stack.md manifest.json; do
  if [[ ! -f "$TARGET_DIR/docs/claude/$f" ]]; then
    cp "$VIBEKIT_DIR/templates/docs/claude/$f" "$TARGET_DIR/docs/claude/$f"
    # Substitute PROJECT_NAME in decisions.md
    if [[ "$f" == "decisions.md" ]]; then
      $_INIT_PY -c "
import sys
path, name = sys.argv[1], sys.argv[2]
with open(path, 'r') as f: content = f.read()
with open(path, 'w') as f: f.write(content.replace('PROJECT_NAME', name))
" "$TARGET_DIR/docs/claude/$f" "$PROJECT_NAME"
    fi
  else
    echo "  Skipping docs/claude/$f (already exists)"
  fi
done

# .gitignore (only if one doesn't already exist)
if [[ ! -f "$TARGET_DIR/.gitignore" ]]; then
  cp "$VIBEKIT_DIR/templates/.gitignore" "$TARGET_DIR/.gitignore"
fi

# .claude/skills
cp "$VIBEKIT_DIR/templates/.claude/skills/vibeplan/SKILL.md" \
   "$TARGET_DIR/.claude/skills/vibeplan/SKILL.md"
cp "$VIBEKIT_DIR/templates/.claude/skills/knowledge-graph-sync/SKILL.md" \
   "$TARGET_DIR/.claude/skills/knowledge-graph-sync/SKILL.md"

# .claude/settings.json — merge if exists, write fresh if not
if [[ -f "$TARGET_DIR/.claude/settings.json" ]]; then
  echo "  .claude/settings.json already exists — checking hooks..."
  # Check if our hooks are present; warn if not
  if ! grep -q "sync-agent.sh" "$TARGET_DIR/.claude/settings.json" 2>/dev/null; then
    echo "  WARNING: .claude/settings.json exists but is missing sync-agent.sh hooks."
    echo "  Add the following to your settings.json manually:"
    echo '    "autoCompactThreshold": 0.5'
    echo '    PreCompact + SessionEnd hooks pointing to bash scripts/sync-agent.sh'
    echo "  Reference: $VIBEKIT_DIR/templates/.claude/settings.json"
  fi
else
  cp "$VIBEKIT_DIR/templates/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"
fi

# === 4. Git init if needed ===
if [[ ! -d "$TARGET_DIR/.git" ]]; then
  echo "Initializing git repository..."
  git -C "$TARGET_DIR" init -q
fi

# Ensure at least one commit exists for Ralph's rollback to work
if ! git -C "$TARGET_DIR" rev-parse HEAD &>/dev/null; then
  echo "Creating initial commit..."
  git -C "$TARGET_DIR" add -A
  # Use configured identity if available; fall back to placeholder so init
  # works on machines where git identity has not been set globally.
  _git_name=$(git config user.name 2>/dev/null || echo "vibekit")
  _git_email=$(git config user.email 2>/dev/null || echo "vibekit@localhost")
  git -C "$TARGET_DIR" \
    -c user.name="$_git_name" \
    -c user.email="$_git_email" \
    commit -q -m "initial commit — vibekit scaffold"
fi

# === 5. Print next steps ===
echo ""
echo "============================================"
echo "  vibekit initialized successfully"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Write brief.md in $TARGET_DIR"
echo "     One page describing what you want to build, constraints, and goals."
echo ""
echo "  2. Open Claude Code in $TARGET_DIR and run:"
echo "     /vibeplan brief.md"
echo ""
echo "     /vibeplan will guide you through scoping the project, then start"
echo "     building it automatically once you confirm the plan."
echo ""
echo "  Docs: $VIBEKIT_DIR/README.md"
echo ""
