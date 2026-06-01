# Archive: 010-ralph-agent-timeout

## T001 · ralph.sh: timeout-wrap all agent invocations + classify timeout as a stall
Depends on: —
Verify: `bash -n scripts/ralph.sh && grep -q 'timeout -k' scripts/ralph.sh && grep -q 'PIPESTATUS' scripts/ralph.sh && grep -q 'RALPH_TASK_TIMEOUT' scripts/ralph.sh` exits 0
Relevant: docs/claude/architecture.md, docs/claude/conventions.md
Tier: complex

**Problem.** `scripts/ralph.sh` runs the agent as `claude ... | tee "$_TMPOUT" || true`
with no timeout. If the agent hangs (e.g. it runs `tail -f`), `ralph.sh` blocks on that
pipe forever. All stall/rate-limit/build-fail recovery runs only *after* the agent
returns, so it never fires. Bound every agent invocation with `timeout` and make a
timeout recover like a stall.

There are **three** agent invocation sites in `scripts/ralph.sh`. Find each by searching
for `--dangerously-skip-permissions --print` (claude) and `amp --dangerously-allow-all`:

1. **Main task loop** — runs `$_TASK_PROMPT`, captures `OUTPUT` (the `claude ... | tee
   "$_TMPOUT"` block followed by `OUTPUT=$(cat "$_TMPOUT" ...)`).
2. **Final QC loop** — runs `$_QC_RUN_PROMPT`, captures `QC_OUTPUT`.
3. **Checkpoint QC** — runs `$_CKPT_RUN_PROMPT`, captures `CKPT_OUTPUT`.

### Step 1 — default the timeout knobs

Near the top config section (where `RATE_LIMIT_BUFFER` / `MAX_RATE_LIMIT_WAITS` are set),
add sane defaults so the script works with no config change:

```bash
: "${RALPH_TASK_TIMEOUT:=1800}"   # seconds before a hung agent session is killed (0 disables)
: "${RALPH_KILL_GRACE:=30}"       # grace period before timeout escalates to SIGKILL
```

`RALPH_TASK_TIMEOUT` may be set in `vibekit.config.sh` (sourced earlier) or the
environment; the `:=` only fills it when unset/empty. If it is `0`, the timeout is
disabled (do not wrap — see Step 4).

### Step 2 — a helper to build the timeout prefix

Add a small helper so all three sites stay consistent:

```bash
# Builds the `timeout -k <grace> <secs>` prefix as an array, or empty if disabled.
ralph_timeout_prefix() {
  if [[ "${RALPH_TASK_TIMEOUT:-1800}" -gt 0 ]] && command -v timeout >/dev/null 2>&1; then
    printf '%s\n' timeout "-k" "${RALPH_KILL_GRACE:-30}" "${RALPH_TASK_TIMEOUT:-1800}"
  fi
}
```

At each call site, read it into an array: `mapfile -t _TO < <(ralph_timeout_prefix)`
then invoke `"${_TO[@]}" claude ...`. When the array is empty the command runs unwrapped
(graceful fallback if `timeout` is unavailable, e.g. some minimal Windows shells).

### Step 3 — wrap each invocation and capture the real exit code through the pipe

For the **main task loop**, change:

```bash
claude --dangerously-skip-permissions --print --model "$_ITER_MODEL" "$_TASK_PROMPT" 2>&1 | tee "$_TMPOUT" || true
```

to capture the agent's exit via `${PIPESTATUS[0]}` (a bare `$?` returns `tee`'s status):

```bash
mapfile -t _TO < <(ralph_timeout_prefix)
"${_TO[@]}" claude --dangerously-skip-permissions --print --model "$_ITER_MODEL" "$_TASK_PROMPT" 2>&1 | tee "$_TMPOUT"
_AGENT_RC=${PIPESTATUS[0]}
```

(Keep the `amp` branch parallel: `"${_TO[@]}" sh -c '...'` is awkward for the
`echo | amp` pipeline — instead wrap as `echo "$_TASK_PROMPT" | "${_TO[@]}" amp
--dangerously-allow-all 2>&1 | tee "$_TMPOUT"; _AGENT_RC=${PIPESTATUS[1]}`. Pick the
correct `PIPESTATUS` index for whichever pipeline shape you use and add a brief comment.)

Do the same for the QC and checkpoint sites, capturing into `_QC_RC` / `_CKPT_RC`.

> Note: `set -e` is active. The pipeline previously ended in `|| true`; with
> `PIPESTATUS` capture you no longer need `|| true`, but ensure a non-zero agent exit
> does not abort the script — the assignment `_AGENT_RC=${PIPESTATUS[0]}` itself
> succeeds, so the pipeline's failure is absorbed. Verify `bash -n` and reason through
> `set -e`: if needed, keep a trailing `|| true` on the pipeline and still read
> `PIPESTATUS` on the very next line (PIPESTATUS survives the `|| true` because the
> `|| true` is part of the same compound command — to be safe, capture into a temp on
> the same logical line). Use whichever form you can confirm preserves the agent's code.

### Step 4 — handle the timeout exit code

`timeout` exits **124** when it fires the signal, and **137** (128+SIGKILL) when the
`-k` grace kill lands. Immediately after capturing `_AGENT_RC` in the **main task
loop**, before the rate-limit check:

```bash
if [[ "${RALPH_TASK_TIMEOUT:-1800}" -gt 0 && ( "$_AGENT_RC" -eq 124 || "$_AGENT_RC" -eq 137 ) ]]; then
  echo "  ⏱ $TASK_ID exceeded ${RALPH_TASK_TIMEOUT}s — agent killed (treating as stall)"
  echo "[$ITERATION] TIMEOUT on $TASK_ID after ${RALPH_TASK_TIMEOUT}s (rc=$_AGENT_RC): $(date)" >> "$LOG_FILE"
  OUTPUT="[RALPH_TIMEOUT]"   # force no-sentinel → existing stall branch rolls back + counts the strike
fi
```

Overwriting `OUTPUT` with a marker that contains no sentinel makes the existing
sentinel-detection fall through to the stall `else` branch, which already rolls back to
`PRE_SHA`, increments `STALL_COUNT` for this task, and exits after 3 strikes. Do **not**
duplicate the rollback logic — reuse it. Make sure this block sits *before*
`is_rate_limited_output "$OUTPUT"` so a timeout isn't misread, and the marker must not
match any rate-limit phrase (it won't).

For the **final QC** and **checkpoint QC** sites, a timeout is a no-progress round.
After capturing `_QC_RC` / `_CKPT_RC`:
- Final QC: if timed out, log `[$ITERATION] TIMEOUT QC round=$QC_ROUND (rc=...)` and
  `continue` (the loop re-enters QC; `MAX_QC_ROUNDS` bounds repeats).
- Checkpoint QC: if timed out, log it, set `TASKS_SINCE_CHECKPOINT=0`, and fall through
  (checkpoint QC is best-effort; never block the run on it).

### Step 5 — verify

Run the `Verify:` command. Also manually confirm with a scratch test that the prefix
fires: `RALPH_TASK_TIMEOUT=1 timeout -k 30 1 sleep 5; echo $?` prints `124` (or `137`).
Do not commit a scratch test file.

Commit: `[ralph] T001 complete — ralph.sh timeout-bounds agent sessions + timeout→stall`

---

## T002 · ralph-prompt.md: forbid non-terminating / background commands
Depends on: T001
Verify: `grep -qi 'tail -f' scripts/ralph-prompt.md && grep -qi 'non-terminating' scripts/ralph-prompt.md` exits 0
Relevant: docs/claude/conventions.md
Tier: simple

Add a new bullet to the **## Execution Rules** section of `scripts/ralph-prompt.md`,
immediately after the existing "Do not run the full test suite speculatively" rule:

```markdown
- **Never run non-terminating, background, or follow commands.** Do not run `tail -f`,
  `watch`, `npm run dev`, `python -m http.server`, or any command that does not exit on
  its own. They cause the session to hang. The execution loop kills any agent session
  that exceeds `RALPH_TASK_TIMEOUT` and counts it as a stall, wasting an attempt. Run
  only commands that terminate on their own — the `Verify:` command and short, bounded
  shell commands.
```

If a synced copy of this prompt exists elsewhere in the repo (search for another
`ralph-prompt.md`; there is normally only `scripts/ralph-prompt.md`), apply the same
edit there. Do not touch phramewerks.

Commit: `[ralph] T002 complete — ralph-prompt forbids non-terminating commands`

---

## T003 · config default + DECISION:013 + docs note
Depends on: T002
Verify: `grep -q 'RALPH_TASK_TIMEOUT' templates/vibekit.config.sh && grep -q 'DECISION:013' docs/claude/decisions.md` exits 0
Relevant: docs/claude/conventions.md, docs/claude/decisions.md, CLAUDE.md
Tier: simple

Three small edits:

1. **`templates/vibekit.config.sh`** — add a documented, commented override line near
   the other tunables (e.g. after `MODEL_QC`):
   ```bash
   # RALPH_TASK_TIMEOUT=1800   # seconds before a hung agent session is killed; 0 disables. Default 1800 (set in ralph.sh).
   ```
   Add the same commented line to the repo-root `vibekit.config.sh` (the live one) so
   it is discoverable, but leave it commented (ralph.sh defaults it).

2. **`docs/claude/decisions.md`** — append:
   ```markdown
   <!-- DECISION:013 | domains: architecture, conventions -->
   ## DECISION:013 — Agent-session timeout (hang recovery)

   - ralph.sh now wraps every claude/amp invocation in `timeout -k 30 ${RALPH_TASK_TIMEOUT:-1800}`.
   - A timed-out agent (exit 124/137) is rolled back and counted as a stall, reusing the
     existing 3-strike machinery. The prompt forbids non-terminating commands (`tail -f`, etc.).
   - Why: a hung inner agent (observed: an agent ran `tail -f` on ralph's own log) blocked
     ralph.sh on the `claude | tee` pipe for 13+ hours. Recovery only ran after the agent
     returned, so nothing fired. Bounding the session makes every hang recoverable.
   - Considered but rejected: per-tool-call timeouts (not reachable from the loop); `flock`-style
     watchdog process (heavier, less portable than coreutils `timeout`).
   ```
   Then bump the counter in `CLAUDE.md` ("Total decisions: 012" → "Total decisions: 013").

3. **`docs/claude/conventions.md`** — add a short note under the concurrency/robustness
   material recording the hang-recovery convention: agent sessions are time-bounded by
   `RALPH_TASK_TIMEOUT` (default 1800s, `0` disables); a timeout is classified as a stall;
   the agent prompt forbids non-terminating commands. Cross-reference DECISION:013.

Commit: `[ralph] T003 complete — RALPH_TASK_TIMEOUT config + DECISION:013 + conventions note`
