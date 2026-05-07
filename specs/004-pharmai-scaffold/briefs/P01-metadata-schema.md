# Pharma Content AI — P01: Metadata Schema

## Overview

Design and implement the metadata schema for all four RAG indexes. Define what
structured metadata fields each document type carries, how those fields map to
PostgreSQL columns, and how they will be used for retrieval filtering. This is a
schema-first project: the output is migrations, ORM models, and a metadata spec
document — not ingestion logic.

## The Four Document Types (one per RAG index)

**Brand/Product RAG** documents:
- product_label_name, ndc_code, therapy_area, brand_name
- document_subtype: [label, clinical_study, scientific_lit, approved_copy]
- mlr_approval_status: [approved, pending, archived]
- approval_date, expiry_date, indication

**Compliance/Violations RAG** documents:
- issuing_body: [FDA_OPDP, FDA_CDER]
- action_type: [warning_letter, untitled_letter, enforcement_action]
- issue_date, company_name, product_name
- violation_categories: array of tags (e.g. ["superiority_claim", "omission_of_risk"])

**Market Intelligence RAG** documents:
- study_type: [market_research, segmentation, hcp_research, patient_research]
- audience: [HCP, patient, payer, all]
- geography, study_date, vendor_name, therapy_area

**Competitive Intelligence RAG** documents:
- competitor_brand_name, competitor_company, therapy_area
- material_type: [journal_ad, dtc_ad, detail_aid, digital]
- capture_date, market_country

## PostgreSQL Schema Additions

- `document_metadata`: doc_id (FK), rag_index (enum: brand/compliance/market/competitive),
  metadata_json (JSONB — holds all type-specific fields above), created_at
- `violation_categories`: lookup table for compliance tags (id, slug, label)
- Add `rag_index` column to `documents` table (enum)

One Alembic migration covering all new tables and columns.

## Validation

Pydantic models for each document subtype — used at upload time (P02) to validate
metadata. Located in `app/models/metadata.py`. One model per rag_index:
`BrandMetadata`, `ComplianceMetadata`, `MarketMetadata`, `CompetitiveMetadata`.
Each declares required vs optional fields.

## Spec Document

`docs/metadata-spec.md`: human-readable reference for which fields are required vs
optional for each document subtype. Used by admins during ingestion (P09 dashboard
reads this for form rendering).

## Schema Endpoint (for frontend forms)

```
GET /api/metadata/schema/{rag_index}
```
FastAPI auto-generates JSON Schema from the Pydantic model for the given index.

## Dependencies

Depends on: P00A (PostgreSQL + modular FastAPI), P00B (auth)

## Known Constraints

- JSONB for flexible per-type fields; required fields enforced in Pydantic, not via DB constraints
- violation_categories must support multi-select (array stored in JSONB)
- Schema must be extensible: adding new fields should not require migration for existing docs
- All metadata models must round-trip through JSON Schema generation cleanly

## Out of Scope

- Ingestion pipeline that uses this metadata (P02)
- Admin UI for metadata entry (P09)
- Retrieval filtering using metadata (P04)
