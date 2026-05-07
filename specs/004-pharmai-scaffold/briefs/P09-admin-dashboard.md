# Pharma Content AI — P09: Admin Dashboard

## Overview

React view (in the same frontend app as P07/P08) for admins to manage the four RAG
indexes: upload documents with metadata, monitor indexing status, view document lists
per index, delete or re-index documents, and manage users (create accounts, assign
roles). Requires `admin` role. Accessible at `/admin`.

## Frontend Pages

```
/admin                           # redirect to /admin/indexes
/admin/indexes                   # tabs: Brand | Compliance | Market | Competitive
  IndexTab:
    DocumentList                 # table: filename, status, uploaded, metadata summary
    UploadModal                  # file + rag_index + metadata form (per P01 schema)
    IndexHealth                  # document count, last indexed, error count
/admin/users                     # user list, create user modal, role badge, deactivate
```

## Metadata Upload Forms

Form rendered dynamically based on selected `rag_index`. Fields defined by P01
Pydantic schemas, rendered as form inputs. Validation client-side mirrors server
Pydantic models via the `/api/metadata/schema/{rag_index}` endpoint (already
exposed in P01).

## Polling for Indexing Status

React Query polls `GET /api/sets/{id}/documents` every 5s while any document is
in `indexing` status. Shows spinner + progress indicator next to each row.

## User Management

```
POST /admin/users/new           # create user (admin) — wraps POST /auth/register
PATCH /admin/users/{id}/role    # change role
DELETE /admin/users/{id}        # deactivate (soft delete via is_active flag)
```

## Dependencies

Depends on: P02 (ingestion endpoints), P03 (multi-index), P07 (React app exists),
P00B (user management endpoints)

## Known Constraints

- Bulk upload (multiple files at once) NOT in this phase
- No drag-and-drop — standard file input only
- Indexing can take minutes — UI must handle long async waits gracefully (polling +
  spinner; no blocking modal)
- All admin actions logged to an audit table:
  `admin_audit`: id, user_id, action, target_id, timestamp, details_json

## Out of Scope

- Analytics / reporting dashboards
- Document deduplication
- Automated ingestion pipelines (scheduled crawls — future)
- Configuration UI for tracking codes (P11 has its own admin endpoint)
