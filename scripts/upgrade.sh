#!/usr/bin/env bash
# upgrade.sh — Sync framework files from this vibekit repo into a scaffolded project.
#
# Usage: bash scripts/upgrade.sh <target-project-dir>
#
# Copies runtime scripts and skill templates. Does NOT touch CLAUDE.md,
# docs/claude/, state/, vibekit.config.sh, .gitignore, or .claude/settings.json.
# Review changes with `git diff` in the target before committing.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIBEKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: bash scripts/upgrade.sh <target-project-dir>"
    exit 1
fi

# Resolve to absolute path if the directory exists
if [[ -d "$TARGET" ]]; then
    TARGET="$(cd "$TARGET" && pwd)"
fi

if [[ ! -f "$TARGET/vibekit.config.sh" ]]; then
    echo "Error: $TARGET does not appear to be a vibekit project (vibekit.config.sh not found)." >&2
    exit 1
fi

ADDED=0
UPDATED=0
IDENTICAL=0

copy_file() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ ! -f "$dst" ]]; then
        cp "$src" "$dst"
        echo "  added:     $dst"
        ADDED=$((ADDED + 1))
    elif cmp -s "$src" "$dst"; then
        echo "  identical: $dst"
        IDENTICAL=$((IDENTICAL + 1))
    else
        cp "$src" "$dst"
        echo "  updated:   $dst"
        UPDATED=$((UPDATED + 1))
    fi
}

echo ""
echo "============================================"
echo "  vibekit upgrade"
echo "============================================"
echo "  Source:  $VIBEKIT_ROOT"
echo "  Target:  $TARGET"
echo "============================================"
echo ""

# Copy scripts/
for f in ralph.sh sync-helpers.sh monitor.sh ralph-prompt.md qc-prompt.md sync-agent.sh; do
    copy_file "$VIBEKIT_ROOT/scripts/$f" "$TARGET/scripts/$f"
done

# Copy .claude/skills/ subdirectories
for skill_dir in plan knowledge-graph-sync knowledge-graph-bootstrap; do
    src_skill="$VIBEKIT_ROOT/templates/.claude/skills/$skill_dir"
    if [[ -d "$src_skill" ]]; then
        while IFS= read -r -d '' src_file; do
            rel="${src_file#"$src_skill"/}"
            copy_file "$src_file" "$TARGET/.claude/skills/$skill_dir/$rel"
        done < <(find "$src_skill" -type f -print0)
    fi
done

echo ""
echo "============================================"
echo "  Updated:   $UPDATED files"
echo "  Added:     $ADDED files"
echo "  Identical: $IDENTICAL files"
echo "============================================"
echo ""
