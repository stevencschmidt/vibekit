# Decision Log

Total decisions: 004

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
