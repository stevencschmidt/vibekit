# Pharma Content AI — P12: Final Validation Agent

## Overview

Before a production asset can be downloaded for deployment, an AI validation
agent compares the final asset (from P10 — approved HTML with tracking codes
injected) against the MLR-approved content (from P08). It confirms: all approved
claims are present and unmodified, no new claims were introduced during code
injection, tracking codes are correctly inserted, and no compliance-flagged
phrases appear. Returns a pass/fail verdict with a detailed diff report. Only
assets with a PASS verdict get a download-enabled state.

## Validation Flow

1. Input: `production_job_id`
2. Load approved content_html from `approved_versions` (P08)
3. Load final asset HTML from `assets/{job_id}/output.html` (P10)
4. Claude analysis (claude-sonnet-4-6, structured JSON output):
   - Extract all claims from approved content
   - Extract all claims from final asset (stripping injected tracking elements)
   - Compare: any claims modified? any new claims added? any approved claims missing?
5. Tracking code presence check (deterministic):
   - Verify all expected UTM params from `production_jobs.tracking_codes_json`
     appear in final HTML
   - Verify campaign_id attribute is present on root container
6. Compliance re-check: run extracted claim list through P06 compliance service
7. Generate verdict: `{ passed: bool, issues: [...], claim_diff: {...} }`
8. Persist to `validation_reports` table
9. Update `production_jobs.validation_status` = "passed" | "failed"

## PostgreSQL Schema Additions

- `validation_reports`: id (uuid), job_id (FK), passed (bool), issues_json,
  claim_diff_json, validated_at, model_used (text), tokens_used (int)

## API Endpoints

```
POST /api/production-jobs/{id}/validate              # trigger validation (async)
GET  /api/production-jobs/{id}/validation-report     # get full report
```

## Download Gate

`GET /api/production-jobs/{id}/download` returns:
- 403 if `validation_status != "passed"` AND caller is not admin
- The HTML asset (200 + Content-Disposition: attachment) if passed or if admin

## Frontend — Validation Status

In P10's JobStatusCard:
- After "complete" status, show "Validate" button
- After validation: show **PASSED** (green badge, Download enabled) or
  **FAILED** (red badge, expandable issues list, Download disabled for non-admins)
- Re-validation allowed after fixing issues (button shown when failed)

## Claude Cost Notes

- Use `cache_control` on system prompt (validation runs frequently)
- Claim extraction batched: max 8 claims per call
- Total tokens per validation: ~5K input + 2K output (cached system: ~500 fresh tokens)

## Dependencies

Depends on: P10 (final asset exists with tracking codes), P08 (approved versions),
P06 (compliance service for re-check)

## Known Constraints

- Validation is not fully deterministic — Claude may miss subtle wording changes.
  Verdict is advisory; legal/regulatory team makes final call.
- Re-validation allowed: marketer can re-request production + re-validate after fixing
- Validation report stored permanently (audit trail; required for compliance)
- Use prompt caching to keep cost manageable (validation runs frequently)

## Out of Scope

- Automated deployment to marketing platforms
- Regulatory submission
- Legal review workflow (separate from MLR)
- Binary diff (HTML source comparison only)
