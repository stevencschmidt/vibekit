# Pharma Content AI — P02: Ingestion Pipeline & Metadata Tagging

## Overview

Extend the document upload endpoint to accept and persist metadata tags for each
document type. The ingestion pipeline (LightRAG + RAG-Anything, ported from rag-engine
in P00A) is updated to inject metadata into the knowledge graph as entity attributes.
Background indexing tracks status in PostgreSQL. The upload API now requires
`rag_index` and a `metadata` JSON blob validated against the Pydantic models from P01.

## Updated Upload Endpoint

```
POST /api/sets/{set_id}/documents/upload
  Body (multipart):
    - file: the document
    - rag_index: brand | compliance | market | competitive
    - metadata: JSON string, validated against the P01 Pydantic model for that index
  Response: { doc_id, version, status: "pending" }
```

## Ingestion Flow

1. Validate `metadata` against the Pydantic model for the given `rag_index` (P01)
2. Persist new row to `documents` + `document_versions` + `document_metadata` (P01)
3. Kick off background task (FastAPI `BackgroundTasks` + a thread pool):
   - RAG-Anything parse → extracted text + image descriptions
   - Inject metadata as LightRAG entity attributes in the graph (one synthetic
     `__metadata__` node connected to all entities from this doc)
   - Update status: `pending` → `indexing` → `indexed` | `error`
4. Rate-limit handling: exponential backoff on Gemini 429s preserved from rag-engine
5. Concurrent-upload safety: registry write guarded by SQLAlchemy session +
   row-level lock (preserve the atomicity fix from ragtest T022)

## Metadata Injection into LightRAG

Each document's entities in LightRAG get extra attributes from `metadata_json`.
A `__metadata__` synthetic node is added connected to every entity from this doc;
its attributes carry rag_index, document_subtype, and indexable filter fields
(brand_name, therapy_area, etc.). This enables metadata-filtered retrieval in P04.

## Status Tracking

- PostgreSQL `document_versions.status` is the source of truth (replaces ragtest's
  JSON registry status field)
- Background task writes status updates atomically via SQLAlchemy session
- Polling endpoint returns current status from DB:
  `GET /api/sets/{set_id}/documents/{doc_id}` → includes status

## Auth

All endpoints require `admin` role (from P00B).

## Dependencies

Depends on: P01 (metadata schema), P00B (auth), P00A (modular FastAPI)

## Known Constraints

- Preserve the ragtest fallback chain: RAG-Anything → PyPDF2 → python-docx
- Preserve rate-limit handling (exponential backoff, retry caps from rag-engine/server.py)
- File versioning (active_version, versions array) preserved
- Background tasks must not block the HTTP response (return 200 with pending status)
- Index re-trigger endpoint (re-index a prior version) preserved from ragtest

## Out of Scope

- Multi-index routing logic (P03 — for now, single-index behavior preserved)
- Retrieval (P04)
- Admin upload UI (P09)
