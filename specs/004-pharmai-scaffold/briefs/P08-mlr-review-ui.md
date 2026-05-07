# Pharma Content AI — P08: MLR Review Interface

## Overview

A dedicated React view (same frontend app from P07) for MLR reviewers to see
a generated content piece alongside its rationale, source citations, and
compliance flags. Reviewers can add section-level comments, approve or reject
the piece, and iterate. Each approval action creates a new version. The final
approved version produces a clean HTML preview. Marketers see review status;
only `mlr_reviewer` role can approve/reject.

## Backend — MLR Review Endpoints

```
POST /api/drafts/{id}/share                # marketer shares for review
GET  /api/drafts/{id}/review               # draft + compliance flags + messages
POST /api/drafts/{id}/comments             # add a comment (mlr_reviewer)
GET  /api/drafts/{id}/comments             # list all comments
PATCH /api/comments/{id}                   # edit/resolve own comment
POST /api/drafts/{id}/approve              # creates approved_version record
POST /api/drafts/{id}/reject               # status → rejected; requires reason
GET  /api/drafts/{id}/approved-preview     # returns clean HTML (no edit chrome)
```

## PostgreSQL Schema Additions

- `draft_comments`: id (uuid), draft_id (FK), user_id (FK), section_anchor,
  comment_text, resolved (bool), created_at
- `approved_versions`: id (uuid), draft_id (FK), approved_by (FK users),
  approved_at, content_html (final approved content), rationale_summary

## Review Flow

1. Marketer shares draft (POST `/api/drafts/{id}/share` → review_record created)
2. MLR reviewer opens review URL, sees content + rationale + flags
3. Reviewer adds comments, requests changes
4. Marketer revises (new draft version in conversation), re-shares
5. Reviewer approves → `approved_versions` record created → unlocks production (P10)

## Frontend — Review Page

```
/review/{draftId}
  DraftPreview (left 60%)     # rendered HTML content with section anchors
  ReviewPanel (right 40%)     # ComplianceFlags, Comments thread, Approve/Reject
  SourcesDrawer (bottom)      # expandable: full source list with excerpts
```

## Clean HTML Preview

Server-side: render content_html with a minimal CSS reset wrapper, no React chrome,
returned as `text/html`. Same HTML used for browser-print PDF (no server-side PDF
library needed).

## Dependencies

Depends on: P06 (compliance flags), P07 (frontend app foundation)

## Known Constraints

- Comments are threaded per section anchor, not per character (no tracked changes)
- Approval is final for a version — approved version cannot be edited
- PDF is browser-print only (no weasyprint or similar)
- Email notifications NOT in scope (reviewers check the UI manually)

## Out of Scope

- Document redlining / diff view
- Email notifications
- External MLR system integration (Veeva Vault etc — future)
- Production asset workflow (P10)
