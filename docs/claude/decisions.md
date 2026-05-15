# Decision Log

Total decisions: 007

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
