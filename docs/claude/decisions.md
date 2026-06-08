# Decision Log

Total decisions: 014

Append-only audit log. Each entry has an anchor for precise retrieval.

---

<!-- DECISION:001 | domains: project, architecture -->
## DECISION:001 — Distribution as standalone repo with init.sh

- Files updated: architecture.md, stack.md
- Why: Distribution model mirrors spec-kit — vibekit is cloned once, then `init.sh` scaffolds it into target projects. No global install, no package manager. Simpler to maintain and update.
- Considered but rejected: npm package (adds Node.js dep, versioning complexity); shell installer via curl (harder to customize); direct copy-paste (no single source of truth for updates)

---

<!-- DECISION:002 | domains: stack, conventions -->
## DECISION:002 — Stack-aware verify_build() populated by /plan

- Files updated: templates/.claude/skills/plan/SKILL.md, sandbox/ragtest/.claude/skills/plan/SKILL.md
- Why: ragtest pilot shipped broken code because verify_build() was a return-0 stub
- Considered but rejected: enforcing a single universal verify command (too restrictive); skipping verify entirely (removes Ralph's failure protection)

---

<!-- DECISION:003 | domains: architecture -->
## DECISION:003 — manifest.json replaces static routing table

- Files updated: templates/docs/claude/manifest.json (new), templates/CLAUDE.md, templates/.claude/skills/plan/SKILL.md, templates/.claude/skills/knowledge-graph-sync/SKILL.md, init.sh
- Why: The static routing table doesn't scale past ~10 domain files and must be manually maintained. The manifest lets Claude self-select the right files at session open.
- Considered but rejected: keyword-based routing (too imprecise); fuzzy vector search (infrastructure overkill for a markdown index)

---

<!-- DECISION:004 | domains: architecture, conventions -->
## DECISION:004 — Checkpoint QC mid-spec

- Files updated: scripts/ralph.sh
- Why: ragtest pilot's QC loop only fired after all tasks were marked complete. By then, T002–T006 had run against a broken SDK assumption and QC had to unwind the damage retroactively. Mid-spec QC catches drift while the delta is still small.
- How it works: `CHECKPOINT_QC_EVERY` env var (default 3) fires a QC round after every N completed tasks, provided ≥2 unchecked tasks remain. Tagged `[CKPT-N]` in logs. A checkpoint emitting `[QC_COMPLETE]` means "no gaps here, continue"; it does not end the run. Value `0` disables checkpoint QC (original behavior).
- Considered but rejected: trigger on every task (too expensive, most tasks don't need review); trigger only on tasks touching requirements.txt or stack.md (too narrow — misses cross-file pattern drift)

---

<!-- DECISION:005 | domains: architecture, conventions -->
## DECISION:005 — Active/archive split for tasks.md and brief.md; non-blocking sync hook

- Files updated: scripts/ralph.sh, scripts/sync-agent.sh, scripts/qc-prompt.md, scripts/ralph-prompt.md, scripts/archive-completed-tasks.sh (new), templates/.claude/skills/plan/SKILL.md, docs/claude/{architecture,conventions}.md
- Why: 32KB tasks.md and 15KB brief.md were bloating chat context every /plan and QC pass; sync-agent.sh blocked Claude Code's auto-compact (chat reached 62% with no compaction).
- Considered but rejected: in-place truncation of completed task bodies (loses detail); auto-trim brief on every fix task (over-aggressive); synchronous hook with timeout only (still blocks compaction up to the timeout).

---

<!-- DECISION:006 | domains: architecture, conventions -->
## DECISION:006 — Dogfooding fixes: rate-limit detection, QC restart, monitoring approach

- Files updated: scripts/ralph.sh (x3), scripts/qc-prompt.md
- Why: Three runtime bugs discovered during vibekit's own spec-001 run; fixed inline (single-file, no-iteration edits) rather than queued through Ralph since each was a 1–3 line change blocking the run.

  **False-positive rate limit detection** (`is_rate_limited_output`): Previously scanned the full Claude output for "rate limit", causing a multi-hour false wait when the QC agent read `ralph.log` (which contains actual "RATE LIMITED" log lines). Fix: only check the last 20 lines — real API errors appear at the tail of output.

  **Preflight null task_id exit**: When restarted fresh with `task_id=null` after a completed spec, ralph.sh exited immediately ("No task assigned") without running QC. Fix: if `last_sentinel` contains `[TASK_COMPLETE: ...]`, fall through to the main loop so QC runs. Both paths now write to `$LOG_FILE` so the monitor catches them.

  **qc-prompt.md brief lookup**: Hardcoded `brief.md` caused QC to silently skip on projects that use a different filename (vibekit uses `knowledge-graph-brief.md`). Fix: try `brief.md` → `BRIEF_FILE` from `vibekit.config.sh` → `knowledge-graph-brief.md`.

- Considered but rejected: queuing each as a Ralph task (adds overhead for single-line fixes; the session policy exception for single-file-no-iteration edits exists exactly for this case).

---

<!-- DECISION:007 | domains: conventions, architecture -->
## DECISION:007 — Rename /plan slash command to /vibeplan

- Files updated: templates/.claude/skills/vibeplan/SKILL.md (renamed from plan/), sandbox/ragtest/.claude/skills/vibeplan/SKILL.md (renamed), init.sh, templates/CLAUDE.md, CLAUDE.md, README.md, knowledge-graph-brief.md, docs/claude/architecture.md, docs/claude/conventions.md, docs/claude/manifest.json
- Why: `/plan` collides with Claude Code's native `/plan` command, causing ambiguity at invocation. Renaming to `/vibeplan` makes vibekit's planning skill unambiguously distinct.
- Considered but rejected: namespace prefix like `/vk:plan` (not supported by Claude Code skill trigger format); keeping `/plan` and accepting the collision (too confusing in practice).

---

<!-- DECISION:008 | domains: architecture, conventions -->
## DECISION:008 — Design files as ambient context + active audit pass

- Files updated: specs/004-design-file-audit/{spec.md,tasks.md} (new), state/sync.json, vibekit.config.sh; subsequent ralph tasks edit docs/claude/{architecture.md,manifest.json}, templates/.claude/skills/vibeplan/SKILL.md, scripts/qc-prompt.md, CHANGELOG.md.
- Why: Briefs alone leave gaps on UX and data flow. A `<brief-dir>/design/` directory of markdown files (layouts, data models, API contracts, glossaries) gives `/vibeplan` enough material to interrogate the project before any tasks are written. The audit runs open-endedly — its goal is to surface every concern (coverage gaps, missing sections, cross-screen inconsistencies, brief contradictions, scope creep), not just a fixed checklist. `/vibeplan` identifies; the user decides. Caught issues during the briefing stage are far cheaper than caught issues mid-Ralph.
- Considered but rejected: per-brief `applies_to:` frontmatter scoping (premature for v1 — ambient is simpler and matches the master `brief.md` pattern); QC reading design files (subjective "design adherence" flags would generate false-positive QC tasks; verify stays driven by task `Verify:` commands); image-only mockups (PNG/Figma — cannot be diffed or reasoned over); a separate `docs/claude/design.md` domain file (the convention is a one-paragraph addition to `architecture.md`, not its own domain).

---

<!-- DECISION:009 | domains: architecture, conventions -->
## DECISION:009 — Complexity-based per-task model routing for Ralph

- Files updated: specs/007-complexity-model-routing/{spec.md,tasks.md} (new), docs/briefs/007-complexity-model-routing.md (new), state/sync.json, vibekit.config.sh; subsequent ralph tasks edit scripts/{ralph.sh,sync-helpers.sh,qc-prompt.md}, templates/{vibekit.config.sh,.claude/skills/vibeplan/SKILL.md}, CLAUDE.md, docs/claude/{architecture.md,conventions.md,manifest.json}.
- Why: Ralph ran every task and both QC stages on one static `$MODEL`, so trivial tasks burned the same per-token cost as hard ones. `/vibeplan` (on Opus) tags each task with a complexity tier; Ralph maps tier→model (`simple`/`medium`/`complex` → Haiku/Sonnet/Opus) and escalates one tier on build-failure retry. Both QC stages are pinned to `MODEL_QC` (Opus) since review is where strong judgment pays off. The win is cost/quota efficiency, not token-count reduction. The decisive risk — mis-tagging a hard task as `simple`, which would waste full tokens on failed-then-rolled-back attempts — is covered by the escalation safety net.
- How it works: tier travels in each `## T###` body as a `Tier:` line (alongside `Relevant:`) and is written to `state/sync.json` as `ralph.tier` by the same next-task parser that writes `task_title`/`relevant_files`. Pure helpers `tier_to_model()`/`escalate_tier()` live in `sync-helpers.sh`. `MODEL_AUTO="false"` or a `--model` CLI flag forces the single-model behavior; neither overrides QC.
- Considered but rejected: a runtime LLM complexity classifier (adds a round-trip per task and its own rate-limit exposure; the Opus planner already has full context to judge); a pure bash keyword heuristic (crude vs. planner judgment); storing the model id per task instead of a tier name (loses one-line re-point); 2-tier mappings (3 tiers give the widest cost range and a clean one-step escalation path).

---

<!-- DECISION:010 | domains: conventions, architecture -->
## DECISION:010 — Dogfooding fixes: rate-limit detection + /dev/tty guard (spec 007 fallout)

- Files updated: scripts/ralph.sh
- Why: Two latent bugs surfaced during spec 007's autonomous run. (1) `is_rate_limited_output` did not recognize the Claude CLI message "You've hit your session limit · resets <time>" — none of its patterns matched "session limit" — so when the limit hit mid–final-QC, ralph treated the empty QC output as a `QC_STALL` and exited 1 instead of waiting for reset. (2) `notify_exit` rang the terminal bell via `printf '\a' > /dev/tty`; when ralph runs detached (nohup, no controlling terminal) bash's redirection-open failure ("/dev/tty: No such device or address") leaked to the log — `2>/dev/null` on the simple command does not suppress bash's redirect-setup error, and `[ -w /dev/tty ]` is not a valid guard (the device node is writable by mode even when `open()` fails with ENXIO).
- Fixes: added a "session limit" pattern to `is_rate_limited_output`; wrapped the bell in a brace group `{ printf '\a' > /dev/tty; } 2>/dev/null || true` so the redirect-open error is captured while the bell still rings whenever a controlling terminal exists. Verified with a detached-session (`setsid`, stdout/stderr→file) reproduction.
- Fixed inline (single-file, no-iteration edits) per the session-policy exception, following the DECISION:006 precedent for ralph.sh runtime fixes.
- Considered but rejected: routing through `/vibeplan` → Ralph (overhead for two one-liners, and fixing the rate-limit detector via an autonomous run that itself depends on that detector is circular); `[ -t 1 ]` gate for the bell (skips the bell on any stdout redirect even when a controlling tty exists).

---

<!-- DECISION:011 | domains: architecture, conventions -->
## DECISION:011 — Gitignore runtime state instead of committing it (resolves the T011 gap)

- Files updated: specs/008-state-commit-hygiene/{spec.md,tasks.md} (new), docs/briefs/008-state-commit-hygiene.md (new), state/sync.json, vibekit.config.sh; subsequent ralph tasks edit templates/.gitignore, init.sh, scripts/ralph.sh, docs/claude/{architecture.md,conventions.md,manifest.json}, CLAUDE.md.
- Why: reviewing phramewerks showed `templates/.gitignore` (scaffolded by `init.sh`) omits `state/`, so scaffolded projects tracked runtime state (including `ralph.pid`) and fired ~33 misleading "Ralph post-complete fallback commit: T### (Claude did not commit)" commits — most just swept state churn that `ralph.sh` writes *after* the agent's own commit. vibekit's own `.gitignore` already ignores `state/`; the template diverged.
- Decision: gitignore volatile state (match vibekit's own `.gitignore`) rather than commit it. This **supersedes** the previously documented T011 plan to add explicit state-file commits — with `state/` ignored there is no residue to commit. Also harden `safety_commit` to (a) report accurately by comparing HEAD to `PRE_SHA` (the agent usually did commit) and (b) never sweep pre-existing working-tree changes (snapshot the dirty set as `PRE_DIRTY` at iteration start). `init.sh` additionally repairs existing projects by appending `state/` to an existing `.gitignore` that lacks it.
- Considered but rejected: T011's "explicitly commit state files" approach (keeps churn in git history and still commits `ralph.pid`; gitignore is simpler and matches vibekit's own setup); scoping the agent's own `git add -A` in `ralph-prompt.md` (a clean per-task tree makes it necessary; the fallback is where the unscoped sweep actually bit). Out of scope: migrating phramewerks (firewall — done in a phramewerks session).

---

<!-- DECISION:012 | domains: architecture, conventions -->
## DECISION:012 — Single-instance concurrency guard (pid-liveness + untrack-on-adopt)

- Files updated: specs/009-ralph-concurrency-and-state-untrack/{spec.md,tasks.md} (new), docs/briefs/009-ralph-concurrency-and-state-untrack.md (new), state/sync.json, vibekit.config.sh; subsequent ralph tasks edit scripts/ralph.sh, init.sh, docs/claude/{conventions.md,manifest.json}, CLAUDE.md.
- Why: Two concurrent `ralph.sh` instances can corrupt `state/sync.json` by reading/writing task state simultaneously. The pid-liveness mechanism (same pattern `/vibe_resume` uses) is portable across platforms — not `flock`, which fails on Windows/Git Bash. Additionally, `init.sh` must untrack already-committed `state/` files from the index on adopt; `.gitignore` entries do not retroactively untrack committed files, so `git rm -r --cached state/` is necessary when vibekit is added to existing projects that may have accidentally committed state artifacts.
- How it works: Ralph writes `$$` to `state/ralph.pid` at startup. Before running, it reads the file and tests liveness using `kill -0 <pid>` (test signal, no process killed). If a live process is detected, it refuses to run unless `--force` or `RALPH_FORCE=1` overrides. An EXIT trap (`_ralph_exit_cleanup`) releases the pid file by comparing the stored pid against the exiting process's `$$` — only deleting if owned by the current instance, preventing a newer Ralph (spawned with `--force` before the old one exited) from losing its pid marker.
- Considered but rejected: `flock` for portability (not available on Windows/Git Bash); `mkdir` atomicity (less portable than pid + kill); higher-level tooling like a lock service (adds runtime dependency). The lightweight pid + liveness pattern is mature, portable, and aligns with `/vibe_resume`'s detection logic.

---

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

---

<!-- DECISION:014 | domains: architecture, conventions -->
## DECISION:014 — Timeout-vs-ratelimit disambiguation, distinct exit code, and supervisor wrapper

Builds on DECISION:013 (hang recovery) and DECISION:010 (rate-limit detection).

- **Timeout-vs-ratelimit fix**: `ralph.sh` previously classified a claude `timeout` exit
  (124/137) as a rate-limit event when the output contained rate-limit text — the timeout
  check ran *after* the rate-limit text scan. Re-ordered so timeout exit codes are tested
  first; rate-limit text scan only runs when the exit code is not a timeout code.
- **Distinct rate-limit exit code**: `ralph.sh` now exits with `RALPH_EXIT_RATE_LIMIT=75`
  (`EX_TEMPFAIL`) when a rate-limit is detected and the run must be deferred (rather than
  mixing it into exit 0 or 1). This makes the exit condition machine-readable for wrappers.
  Exit code 75 is gated exclusively to the confirmed rate-limit path — stalls, verify-
  failures, and blocks all continue to use exit 1 so real failures still require human review.
- **Supervisor wrapper** (`scripts/ralph-supervisor.sh`): relaunches `ralph.sh` automatically
  on exit 75. All other exit codes pass through unchanged: 0 = spec complete, 1 = failure,
  130 = interrupted. `--max-relaunch N` caps the loop (default 100). `systemd` handles
  reboot survival; the supervisor does not need `Restart=always` — the rate-limit window
  clears within hours, not days.
- **ralph-prompt.md no-background hardening**: strengthened the no-background-commands rule
  with explicit examples (`tail -f`, `watch`, `npm run dev`, `python -m http.server`) and
  explained the hang/stall consequence so agents understand the "why" and avoid equivalent
  commands not on the list.
- Considered but rejected: a blanket `Restart=always` in systemd (masks real failures);
  using exit 1 for rate-limit and having the supervisor scan stderr (fragile text matching
  in supervisor adds a second detection layer that can drift from ralph's own detection).
