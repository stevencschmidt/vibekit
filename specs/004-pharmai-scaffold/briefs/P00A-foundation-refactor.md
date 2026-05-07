# Pharma Content AI — P00A: Foundation Refactor

## Overview

Evolve the ragtest proof-of-concept into a production-grade FastAPI application.
Refactor the single-file server.py into a modular Python package. Swap the JSON
registry for PostgreSQL with SQLAlchemy ORM and Alembic migrations. Add Docker
Compose for local development. All existing ragtest functionality (document upload,
indexing, status polling, LightRAG knowledge graph) must work after the refactor.

## Source Reference

`rag-engine/` at the project root contains the working ragtest pilot:
- `rag-engine/server.py` — single-file FastAPI server with full RAG pipeline
- `rag-engine/static/index.html` — vanilla JS frontend (will be replaced in P07)
- `rag-engine/requirements.txt` — Python dependencies
- `rag-engine/REFERENCE-CLAUDE.md`, `REFERENCE-brief.md` — original project docs

Use this code as algorithm reference for the LightRAG + RAG-Anything pipeline,
rate-limit handling, and document versioning logic. Do NOT import from rag-engine/
into the new app — port the logic into the new modular structure.

## Target Structure

```
app/
  __init__.py
  main.py              # FastAPI app factory, mounts routers
  config.py            # Settings via pydantic-settings (.env)
  database.py          # SQLAlchemy engine + session factory
  routers/
    __init__.py
    sets.py            # RAG set CRUD
    documents.py       # Upload, index, versions, delete
    health.py          # Health check endpoint
  services/
    __init__.py
    indexing.py        # LightRAG + RAG-Anything pipeline (ported from rag-engine)
    registry.py        # PostgreSQL-backed registry (replaces JSON)
  models/
    __init__.py
    orm.py             # SQLAlchemy ORM models
    schemas.py         # Pydantic request/response schemas
migrations/
  env.py               # Alembic env
  versions/            # Migration files
tests/
  test_health.py
  test_documents.py
  test_sets.py
.env.example           # GEMINI_API_KEY, DATABASE_URL placeholders
docker-compose.yml     # api + db services
Dockerfile             # FastAPI api service
requirements.txt
alembic.ini
```

## PostgreSQL Schema (initial)

- `rag_sets`: id (uuid), name, description, created_at, updated_at
- `documents`: id (uuid), set_id (FK), filename, active_version (int),
  status (enum: pending/indexing/indexed/error), created_at
- `document_versions`: id (uuid), doc_id (FK), version (int), file_path (text),
  uploaded_at, status, content_doc_id (text — LightRAG hash for deletion)

## LLM / RAG (unchanged from ragtest)

- Gemini embeddings: `models/text-embedding-004` (768-dim, free tier)
- Gemini LLM: `gemini-2.5-flash` (entity extraction, vision)
- LightRAG knowledge graph storage in `rag_sets/<set-id>/`
- RAG-Anything for multimodal parsing → fallback to PyPDF2/python-docx
- Exponential backoff on Gemini 429s preserved (port from rag-engine/server.py)

## Docker Compose

```yaml
services:
  db:
    image: postgres:16
    environment: { POSTGRES_DB: pharma_ai, POSTGRES_USER: pharma, POSTGRES_PASSWORD: dev }
    volumes: ["pgdata:/var/lib/postgresql/data"]
    ports: ["5432:5432"]
  api:
    build: .
    depends_on: [db]
    env_file: .env
    ports: ["7860:7860"]
    volumes: ["./rag_sets:/app/rag_sets", "./uploads:/app/uploads"]
volumes:
  pgdata:
```

## Dependencies

- Python 3.11+
- fastapi, uvicorn, sqlalchemy, alembic, psycopg2-binary, pydantic-settings
- lightrag-hku, rag-anything (from rag-engine/requirements.txt)
- python-multipart, aiofiles
- pytest, httpx (test deps)
- docker, docker-compose

## Setup

```bash
cp .env.example .env  # fill in GEMINI_API_KEY
docker-compose up -d db
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload --port 7860
```

## Known Constraints

- Remove the ragtest tmux/WebSocket Claude terminal — replaced by Anthropic SDK in P05
- All existing REST endpoints from rag-engine must have integration test coverage
- Alembic must handle migrations cleanly: `alembic upgrade head` from empty DB → working schema
- Rate limit handling (exponential backoff for Gemini 429s) must be preserved
- LightRAG storage layout (rag_sets/<set-id>/) preserved unchanged

## Out of Scope

- Authentication (P00B)
- Multiple RAG indexes beyond ragtest's single-index pattern (P03)
- React frontend (P07)
- Any new features beyond what ragtest already has
