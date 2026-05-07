# Pharma Content AI — P03: Multi-Index RAG Architecture

## Overview

Establish four separate LightRAG knowledge graph indexes — one per RAG type
(Brand, Compliance, Market Intelligence, Competitive Intelligence). Each index
lives in its own directory under `rag_sets/`. The indexing service routes
documents to the correct index based on the `rag_index` field set during upload
(from P02). An index manager provides health checks and per-index document counts.

## Directory Structure

```
rag_sets/
  brand/           # LightRAG WorkingDir for Brand/Product RAG
  compliance/      # Compliance/Violations RAG
  market/          # Market Intelligence RAG
  competitive/     # Competitive Intelligence RAG
```

## Index Manager Service

`app/services/index_manager.py`:
- `get_index(rag_index: str) -> LightRAG` — returns initialized LightRAG instance
- LightRAG instances initialized lazily and cached (module-level dict, thread-safe)
- Each index uses the same embedding model (text-embedding-004)
- Each index has its own working directory and storage files

## Config

`app/config.py` gains:
```python
RAG_INDEX_DIRS = {
    "brand":       "rag_sets/brand",
    "compliance":  "rag_sets/compliance",
    "market":      "rag_sets/market",
    "competitive": "rag_sets/competitive",
}
```

## Updated Indexing Service

`app/services/indexing.py` (from P02) calls `index_manager.get_index(rag_index)`
instead of using a set-specific directory. One document → one index, determined
by the `rag_index` field saved at upload time.

## Admin Endpoints

```
GET  /api/indexes/health             # status + doc count per index
POST /api/indexes/{name}/rebuild     # admin-only: re-index all docs in this index
GET  /api/indexes/{name}/documents   # paginated list of documents in this index
```

## Migration

Alembic: ensure `rag_index` enum column on `documents` table is populated for
existing rows (if any from P02 had a default value). Make the migration idempotent.

## Rebuild Job Tracking

The rebuild endpoint returns a `job_id`. `jobs` table tracks async rebuild status:
- id, type ("index_rebuild"), index_name, status, started_at, completed_at, error_msg

## Dependencies

Depends on: P02 (ingestion pipeline exists and must be rerouted to use the index manager)

## Known Constraints

- LightRAG working directories must NOT be shared between indexes (separate state)
- Embedding model must be consistent within an index (changing requires full re-index)
- Rebuild endpoint is async/background; returns job_id for polling, never blocks
- Initial load: index_manager loads each index lazily on first access — prevents
  startup cost; warm-up happens on first query

## Out of Scope

- Retrieval from indexes (P04)
- Compliance-specific logic (P06)
- Any UI
