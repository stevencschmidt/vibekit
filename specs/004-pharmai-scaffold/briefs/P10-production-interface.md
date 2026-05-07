# Pharma Content AI — P10: Production Asset Interface & Workflow

## Overview

After MLR approval, the marketer initiates a production "build": the system
injects tracking codes (from P11) into the MLR-approved HTML and produces a
final downloadable artifact. This React view shows the production queue, build
status, and download links. It is gated: only approved drafts can enter the
production workflow.

**Note on scope:** The original "final asset builder" (HTML email templates,
weasyprint PDF generation, multi-channel rendering) is **out of scope** for this
project. The production output here is simply the MLR-approved content_html with
tracking codes injected — provided as a clean downloadable HTML file. Any
channel-specific styling/templating is the receiving system's responsibility.

## Backend — Production Workflow Endpoints

```
POST /api/approved-versions/{id}/production-request
  Body: { channel: str, audience: str, additional_params: dict }
  → creates production_jobs row, calls P11 to generate tracking codes,
    injects them into approved content_html, writes assets/{job_id}/output.html,
    returns { job_id, status: "complete", result_url }

GET  /api/production-jobs                 # list (marketer sees own; admin sees all)
GET  /api/production-jobs/{id}            # job status + result_url + tracking codes
GET  /api/production-jobs/{id}/download   # returns the HTML asset (auth-gated)
```

## PostgreSQL Schema Additions

- `production_jobs`: id (uuid), approved_version_id (FK), requested_by (FK users),
  channel, audience, tracking_codes_json, status (enum: pending/complete/error),
  result_url, error_msg, created_at, completed_at

## Production Job Flow

1. Validate `approved_version_id` exists in `approved_versions` (from P08)
2. Call P11 (`generate_tracking_codes`) with conversation tracking_intent + channel
3. Inject tracking codes into content_html:
   - Replace `{{TRACKING_PIXEL}}` placeholder if present (else: skip silently)
   - Append UTM params to all `<a href>` tags (parse with BeautifulSoup)
   - Insert `data-campaign-id` attribute on the root container
4. Save to `assets/{job_id}/output.html`
5. Mark job complete; result_url = `/api/production-jobs/{id}/download`

## Frontend — Production View

```
/production                              # requires marketer or admin role
  ApprovedPiecesList                     # approved pieces ready for production
  ProductionQueue                        # in-progress and recent jobs
  ProductionRequestModal                 # form: channel, audience, additional_params
  JobStatusCard                          # download button when complete; validation
                                         # status (from P12) + Validate button
```

## Static Asset Serving

FastAPI `StaticFiles` mount at `/assets` is NOT used (not auth-gated). Instead,
`GET /api/production-jobs/{id}/download` reads the file and returns it via
`FileResponse`, with auth middleware applied. Validation gate (P12): if
`validation_status != "passed"`, the download endpoint returns 403 unless the
caller is admin.

## Dependencies

Depends on: P08 (approved versions exist), P11 (tracking codes available), P07 (React app)

## Known Constraints

- Output is always plain HTML — no email-specific inlining, no PDF
- Only one active production job per approved version at a time
- Tracking code insertion uses BeautifulSoup; preserves original HTML structure
- All production jobs are auditable: every download is logged to `admin_audit`

## Out of Scope

- Email-template-specific rendering (no Gmail/Outlook compat layer)
- PDF generation
- Distribution to external marketing platforms
- Multi-channel asset variants from a single approved piece
