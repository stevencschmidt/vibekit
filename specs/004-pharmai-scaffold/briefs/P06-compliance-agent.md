# Pharma Content AI — P06: Compliance & Validation Agent

## Overview

Build an agent that analyzes a content draft for compliance risk using the
Violations RAG. For each identified risk, it returns: the risky claim or
phrase, the matched FDA violation pattern, source links (which warning letter /
enforcement action), a risk score (low/medium/high), and suggested rewrites.
This runs as a background job triggered after draft generation; results are
stored in PostgreSQL and surfaced in the MLR review UI (P08).

## Compliance Check Flow

1. Input: `content_draft_id`
2. Retrieve draft content from `content_drafts` table (P05)
3. Extract all claims from the draft (Claude call: claude-haiku-4-5, structured output)
4. For each claim batch: `retrieve_compliance_risks(claim)` via P04 retrieval service
5. Score each claim against retrieved violation patterns (Claude call: claude-sonnet-4-6,
   structured JSON output)
6. Persist results to `compliance_flags` table
7. Update draft: set `compliance_checked = true` on the conversation row

## PostgreSQL Schema

- `compliance_flags`: id (uuid), draft_id (FK), claim_text, matched_pattern,
  violation_source_doc, violation_source_version, risk_level (enum: low/medium/high),
  suggested_rewrite, created_at
- `jobs`: id, type ("compliance_check"), status, draft_id, started_at, completed_at,
  error_msg

## API Endpoints

```
POST /api/drafts/{id}/compliance-check       # trigger async check; returns job_id
GET  /api/drafts/{id}/compliance-flags       # all flags for this draft
GET  /api/jobs/{job_id}                      # poll job status
```

## Background Job

FastAPI `BackgroundTasks` (or asyncio task). Job rows track status; on completion,
the draft is updated with the compliance_checked flag.

## Claude Calls

- Claim extraction: claude-haiku-4-5 (fast, cheap, structured JSON output)
- Risk scoring: claude-sonnet-4-6 (more nuanced reasoning, structured JSON)
- Use `cache_control` on the system prompts (called frequently)
- Each claim batch: max 8 claims per scoring call (token budget)

## Dependencies

Depends on: P05 (drafts exist), P04 (retrieval service for compliance index)

## Known Constraints

- Compliance check is async — never blocks content generation in P05
- If compliance index has no documents (empty corpus), return empty flags (not an error)
- Risk scoring must include source attribution (which document flagged this — used in P08)
- Suggested rewrites are advisory; MLR reviewer makes final call
- Token budget per claim batch: ≤8K input, ≤2K output

## Out of Scope

- MLR review UI (P08)
- Auto-rejection based on risk score (humans always decide)
- Regulatory submission (out of project scope entirely)
