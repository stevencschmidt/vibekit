# Pharma Content AI — P04: Intelligent Retrieval Router

## Overview

Build a retrieval router that, given a query and optional metadata filters,
decides which RAG index(es) to search, executes hybrid retrieval (LightRAG
knowledge graph query), applies metadata post-filtering, and returns ranked
results with source attribution (document name, version, page estimate).
The router exposes a single API endpoint used by the orchestrator in P05 and
is also callable as a Python service (no HTTP) for in-process use.

## Retrieval Endpoint

```
POST /api/retrieval/query
  Body:
    query: str
    indexes: list[str] | null     # ["brand", "compliance"] etc — null = auto-route
    filters: dict                  # optional, e.g. {"therapy_area": "oncology"}
    mode: "local" | "global" | "hybrid"   # LightRAG query modes (default "hybrid")
    top_k: int = 10
  Response:
    results: [
      {
        chunk: str,
        source_doc: str,
        rag_index: str,
        metadata: dict,
        score: float,
      }
    ]
    indexes_queried: list[str]
    classifier_reason: str | null    # if auto-routed, why
```

## Auto-Routing Logic

When `indexes` is null, classify the query intent using simple keyword + regex
rules (NOT a Claude call — keep retrieval fast, sub-second):

- Mentions drug name, clinical data, label, indication → brand
- Mentions risk, FDA, warning, enforcement, violation → compliance
- Mentions market, customer, HCP, segmentation, insight → market
- Mentions competitor, positioning, share, rival → competitive
- Ambiguous or mixed → fall back to all four indexes

Auto-routing is overridable: callers can always specify `indexes` explicitly.

## Metadata Post-Filtering

After retrieval from LightRAG, filter results by `filters` dict:
- Match against `document_metadata.metadata_json` in PostgreSQL
- SQL query gets matching doc IDs, then filter retrieved chunks against that set
- Multiple filters AND together; array values OR within field

## Source Attribution

For each result chunk, join against `documents` + `document_versions` to return:
- filename, version (active_version), rag_index, upload_date
- relevant metadata fields (brand_name for brand index, etc.)

## Service Layer

`app/services/retrieval.py`: pure Python service, no HTTP. Orchestrator (P05) will
call it directly as a Python function, not via HTTP. The HTTP endpoint is a thin
wrapper over the service.

## Dependencies

Depends on: P03 (four indexes exist and have been populated)

## Known Constraints

- Retrieval must complete in <5s for single-index queries; <8s for all-index queries
- LightRAG query modes: default to "hybrid" for best recall
- Auth: endpoint requires `marketer` role minimum
- All retrievals MUST log to a query log table for audit (compliance need):
  `retrieval_log`: id, user_id, query, indexes_queried, top_chunk_ids, timestamp

## Out of Scope

- Compliance checking (P06 uses retrieval but adds analysis on top)
- Chat orchestration (P05)
- Any UI
