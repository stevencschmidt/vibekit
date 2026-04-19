# Decision Log

Total decisions: 001

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
