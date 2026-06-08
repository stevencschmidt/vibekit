#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

if [[ ! -f "$PROJECT_ROOT/vibekit.config.sh" ]]; then
  echo "Error: vibekit.config.sh not found at $PROJECT_ROOT" >&2
  exit 1
fi

SLUG="$(basename "$PROJECT_ROOT")"

UNIT_DIR="$HOME/.config/systemd/user"
UNIT_FILE="$UNIT_DIR/vibekit-ralph@.service"

UNIT_CONTENT="[Unit]
Description=Vibekit ralph for %i
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$PROJECT_ROOT
ExecStart=/bin/bash $PROJECT_ROOT/scripts/ralph-supervisor.sh
# Restart=no is intentional: reboot survival only; the supervisor handles rate-limit
# auto-resume (exit 75/EX_TEMPFAIL), while systemd handles reboot survival. Stalls
# and real failures (exit 1) stop the service and require human review. See DECISION:014.
Restart=no
StandardOutput=append:$PROJECT_ROOT/state/ralph.log
StandardError=inherit

[Install]
WantedBy=default.target"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "=== DRY RUN: would write to $UNIT_FILE ==="
  echo ""
  echo "$UNIT_CONTENT"
  echo ""
else
  mkdir -p "$UNIT_DIR"
  printf '%s\n' "$UNIT_CONTENT" > "$UNIT_FILE"
  echo "Unit written to: $UNIT_FILE"
fi

echo ""
echo "To enable reboot survival, run these commands ONCE:"
echo ""
echo "  sudo loginctl enable-linger $USER"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now vibekit-ralph@${SLUG}.service"
echo ""
echo "Where <slug> = ${SLUG}"
echo ""
echo "Notes:"
echo "- linger lets your user services run without an active login (required for boot-time start)"
echo "- Restart=no means stalls and failures stop the service — reboots restart it"
echo "- To stop: systemctl --user stop vibekit-ralph@${SLUG}.service"
echo "- Logs: journalctl --user -u vibekit-ralph@${SLUG}.service -f"
