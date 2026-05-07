# Pharma Content AI — Project Briefs

These are 14 sequential project briefs that, fed to `/vibeplan` one at a time,
build out the full Pharma Content AI system. Each brief produces one
`specs/NNN-slug/` folder via `/vibeplan`, then Ralph executes the tasks.

## Workflow

For each brief in the order below:

1. Open Claude Code in this project root.
2. Run: `/vibeplan briefs/P00A-foundation-refactor.md` (substitute the brief filename).
3. Answer the 3-phase planning conversation. On confirmation, /vibeplan generates
   `specs/NNN-slug/spec.md` + `tasks.md`, updates `state/sync.json`, and updates
   `vibekit.config.sh` to point at the new spec.
4. Run: `bash scripts/ralph.sh` and let Ralph execute the tasks autonomously.
5. When Ralph completes, the next brief becomes the next /vibeplan input.

## Order (hard sequential dependencies)

```
P00A → P00B → P01 → P02 → P03 → P04 → P05 → P06
                                              ↓
                 P09 ← P08 ← P07 ← ─────────┘
                                              ↓
                           P11 ←── P05 (already done)
                           P10 ←── P08
                           P12 ←── P10 + P11
```

| # | File | Title |
|---|------|-------|
| 1 | P00A-foundation-refactor.md | Foundation: Modular FastAPI + PostgreSQL + Docker |
| 2 | P00B-authentication.md | Authentication & Role-Based Access Control |
| 3 | P01-metadata-schema.md | Comprehensive Metadata Schema Design |
| 4 | P02-ingestion-pipeline.md | Document Ingestion Pipeline & Metadata Tagging |
| 5 | P03-multi-index-rag.md | Multi-Index RAG Architecture (4 indexes) |
| 6 | P04-retrieval-router.md | Intelligent Retrieval Router |
| 7 | P05-conversation-orchestrator.md | Main Conversation Orchestrator |
| 8 | P06-compliance-agent.md | Compliance & Validation Agent |
| 9 | P07-marketer-chat-ui.md | Marketer Chat Interface (React) |
| 10 | P08-mlr-review-ui.md | MLR Review Interface (React) |
| 11 | P09-admin-dashboard.md | Admin / Content Ingestion Dashboard |
| 12 | P10-production-interface.md | Production Asset Interface & Workflow |
| 13 | P11-tracking-codes.md | Tracking Code Generator |
| 14 | P12-final-validation.md | Final Validation Agent |

## Notes

- The original "Final Asset Builder" project (HTML email templates, weasyprint PDF, etc.)
  is **out of scope**. P10 simplifies to: inject tracking codes into the MLR-approved
  HTML and provide a download link. No fancy template engine or PDF rendering.
- `rag-engine/` at the project root contains the working RAG pilot from sandbox/ragtest.
  Use it as algorithm reference (LightRAG + RAG-Anything pipeline, rate-limit handling)
  when implementing P02 onward. It is NOT directly mounted by the production app.
- Dev mode uses Claude OAuth via the `claude` CLI subprocess. Production uses
  `ANTHROPIC_API_KEY` with the Anthropic SDK. Both paths configured in P05.
