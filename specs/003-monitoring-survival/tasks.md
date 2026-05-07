# Tasks: 003-monitoring-survival

- [x] T021 · Custom statusline script for in-terminal ralph progress
- [x] T022 · Tighten Claude polling pattern in conventions doc
- [x] T023 · Audit + harden ralph.sh rate-limit detection
- [x] T024 · Add notify_exit helper + status file + libnotify integration
- [x] T025 · systemd --user unit installer for reboot survival

---

## T025 · systemd --user unit installer for reboot survival
Depends on: T024
Verify: `bash -n scripts/install-service.sh && test -x scripts/install-service.sh && bash scripts/install-service.sh --dry-run 2>&1 | grep -q "loginctl enable-linger"`
Relevant: docs/claude/conventions.md, README.md

**Problem:** Once ralph is launched via `nohup`, it survives terminal close — but not host reboot. For long-running specs (multi-day, crossing rate-limit windows), a reboot loses progress. The user must manually re-launch ralph after every restart. systemd --user with linger enabled solves this: the service auto-starts at boot independent of login state.

**What to do:**

Create a new executable file `scripts/install-service.sh`:

1. **Usage and dry-run flag:**
   - `bash scripts/install-service.sh` — generate the unit, print enable instructions
   - `bash scripts/install-service.sh --dry-run` — print what would be generated and the enable instructions, but do not write any files

2. **Project detection:** Compute `PROJECT_ROOT` via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`. Validate `vibekit.config.sh` exists at `PROJECT_ROOT`. If not, print an error and exit 1.

3. **Compute slug:** `SLUG="$(basename "$PROJECT_ROOT")"` — used as the systemd template instance.

4. **Generate the unit file** at `~/.config/systemd/user/vibekit-ralph@.service` (template unit, instance via `%i`). Skip the write in `--dry-run` mode.

   Unit content:
   ```
   [Unit]
   Description=Vibekit ralph for %i
   After=network-online.target

   [Service]
   Type=simple
   WorkingDirectory=PROJECT_ROOT_PLACEHOLDER
   ExecStart=/bin/bash PROJECT_ROOT_PLACEHOLDER/scripts/ralph.sh
   Restart=no
   StandardOutput=append:PROJECT_ROOT_PLACEHOLDER/state/ralph.log
   StandardError=inherit

   [Install]
   WantedBy=default.target
   ```
   Substitute `PROJECT_ROOT_PLACEHOLDER` with the absolute path of `PROJECT_ROOT` before writing. (Don't use `%h` — paths can vary; absolute is safer.)

5. **`Restart=no` is intentional.** Document it in a comment line in the unit and in the script's stdout output. We want reboot survival, not auto-restart on real failures (which would loop forever on a stall).

6. **Print user instructions** (always, regardless of `--dry-run`):
   ```
   Unit written to: ~/.config/systemd/user/vibekit-ralph@.service
   
   To enable reboot survival, run these commands ONCE:
   
     sudo loginctl enable-linger $USER
     systemctl --user daemon-reload
     systemctl --user enable --now vibekit-ralph@<slug>.service
   
   Where <slug> = ${SLUG}
   
   Notes:
   - linger lets your user services run without an active login (required for boot-time start)
   - Restart=no means stalls and failures stop the service — reboots restart it
   - To stop: systemctl --user stop vibekit-ralph@${SLUG}.service
   - Logs: journalctl --user -u vibekit-ralph@${SLUG}.service -f
   ```

7. **README addendum** — add a new section "Reboot Survival":
   > Long-running specs may need to survive host reboots. Vibekit ships a systemd --user unit installer:
   >
   > ```
   > bash scripts/install-service.sh
   > ```
   >
   > Then follow the printed instructions to enable linger and start the service. After that, ralph will auto-resume from `state/sync.json` on every boot. `Restart=no` means stalls and failures still require human review — this is reboot survival, not auto-recovery from real failures.

8. Standard bash conventions — `set -e`, SCRIPT_DIR/PROJECT_ROOT pattern, `chmod +x` after creation.

The verify command checks bash syntax, executability, and that `--dry-run` mode prints the `loginctl enable-linger` instruction (proving the script ran end-to-end without writing files).

Commit with `[ralph] T025 complete — systemd --user installer for reboot survival`.

---
