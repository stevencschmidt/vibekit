# Pharma Content AI — P11: Tracking Code Generator

## Overview

Convert the marketer's stated tracking intent (captured in the conversation by P05)
into concrete tracking parameters: UTM codes, campaign IDs, and any custom
tracking attributes defined by the organization. Parameters are stored against the
production job and applied to the asset by P10. A simple rule-based generator with
a configurable mapping table — no AI needed for this step.

## Tracking Parameter Types

- UTM: utm_source, utm_medium, utm_campaign, utm_content, utm_term
- Custom: campaign_id (org-internal slug), asset_id (generated UUID), channel_code
- Format-specific: email open pixel URL template (channel = "email"),
  click-through URL template

## Config-Driven Mapping

`tracking_config.json` (admin-editable, loaded at startup, refreshable via endpoint):
```json
{
  "campaign_prefix": "PHX",
  "channels": {
    "email":          { "utm_medium": "email",   "channel_code": "EM" },
    "digital_banner": { "utm_medium": "display", "channel_code": "DB" },
    "detail_aid":     { "utm_medium": "sales",   "channel_code": "DA" }
  },
  "tracking_pixel_base_url": "https://tracking.example.com/pixel",
  "click_redirect_base_url": "https://tracking.example.com/r"
}
```

## Generation Logic

1. Input: tracking_intent (text from conversation), channel, brand_name,
   campaign_date, conv_id
2. Parse intent for measurable goals (open rate, clicks, conversion) — keyword match
3. Construct UTM params from channel mapping + brand slug + date slug
4. Generate campaign_id: `{prefix}-{brand_slug}-{YYYYMM}-{asset_uuid[:6]}`
5. Return structured JSON + a human-readable summary string

## Endpoints

```
POST /api/tracking/generate
  Body: { conv_id, channel, brand_name, campaign_date }
  Response: { tracking_codes: {...}, summary: str }

GET  /api/tracking/config              # current config (admin)
PUT  /api/tracking/config              # update config (admin)
POST /api/tracking/config/reload       # admin: reload from disk without restart
```

## Service Layer

`app/services/tracking.py`: pure Python. Called directly by P10's production-request
endpoint; the HTTP endpoint exists for ad-hoc testing and admin tooling.

## Storage

Generated codes are stored on the `production_jobs.tracking_codes_json` column
(P10). Also linked back to the originating conversation:
`conversations.tracking_codes_json` (latest set), so the chat sidebar (P07) can
display "tracking codes ready" status.

## Dependencies

Depends on: P05 (tracking intent captured in conversation), P10 (called during
production job)

## Known Constraints

- No integration with external marketing platforms (Salesforce, Veeva) this phase
- Config changes via PUT take effect after `POST /api/tracking/config/reload`
- Tracking codes generated once per production job; not regenerated on re-run
- Campaign IDs must be stable for a given (conv_id, channel, date) tuple — re-running
  must produce the same ID (use deterministic UUID derivation)

## Out of Scope

- Analytics reporting / dashboard (downstream system)
- A/B test parameter generation
- Integration with external marketing automation
