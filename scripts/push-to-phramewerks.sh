#!/usr/bin/env bash
# push-to-phramewerks.sh — Sync vibekit infrastructure files to phramewerks
#
# Mirrors the non-project-specific files that init.sh scaffolds.
# When adding new infrastructure files to init.sh, add them here too.
#
# NOT synced: vibekit.config.sh, CLAUDE.md, state/, docs/claude/, .claude/settings.json

set -e

VIBEKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHRAMEWERKS_DIR="/home/steven/phramewerks"

if [[ ! -d "$PHRAMEWERKS_DIR" ]]; then
  echo "Error: phramewerks not found at $PHRAMEWERKS_DIR"
  exit 1
fi

echo ""
echo "Syncing vibekit → phramewerks"
echo "  from: $VIBEKIT_DIR"
echo "  to:   $PHRAMEWERKS_DIR"
echo ""

count=0

copy_file() {
  local src="$1"
  local rel_dst="$2"
  local dst="$PHRAMEWERKS_DIR/$rel_dst"
  mkdir -p "$(dirname "$dst")"
  cp "$VIBEKIT_DIR/$src" "$dst"
  echo "  → $rel_dst"
  (( count++ )) || true
}

# scripts/ — mirrors init.sh section 2
copy_file "scripts/ralph.sh"        "scripts/ralph.sh"
copy_file "scripts/sync-helpers.sh" "scripts/sync-helpers.sh"
copy_file "scripts/monitor.sh"      "scripts/monitor.sh"
copy_file "scripts/ralph-prompt.md" "scripts/ralph-prompt.md"
copy_file "scripts/qc-prompt.md"    "scripts/qc-prompt.md"
copy_file "scripts/sync-agent.sh"   "scripts/sync-agent.sh"

chmod +x "$PHRAMEWERKS_DIR/scripts/ralph.sh"
chmod +x "$PHRAMEWERKS_DIR/scripts/sync-agent.sh"

# .claude/skills/ — mirrors init.sh section 3 (skills portion, from templates/)
copy_file "templates/.claude/skills/vibeplan/SKILL.md"             ".claude/skills/vibeplan/SKILL.md"
copy_file "templates/.claude/skills/knowledge-graph-sync/SKILL.md" ".claude/skills/knowledge-graph-sync/SKILL.md"
copy_file "templates/.claude/skills/vibe_resume/SKILL.md"          ".claude/skills/vibe_resume/SKILL.md"

echo ""
echo "$count files synced."
echo ""
