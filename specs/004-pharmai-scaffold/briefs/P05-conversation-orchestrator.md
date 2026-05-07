# Pharma Content AI — P05: Conversation Orchestrator

## Overview

Build the multi-turn conversation agent that powers the marketer chat experience.
Uses Anthropic SDK (claude-sonnet-4-6) with tool use. The agent calls the
retrieval service (P04), asks about tracking intent early in the conversation,
generates content drafts with cited sources, and streams responses. Conversation
history is persisted in PostgreSQL. Supports dev (Claude OAuth via subprocess) and
production (ANTHROPIC_API_KEY) modes configured in .env.

## Conversation Model

PostgreSQL tables:
- `conversations`: id (uuid), user_id (FK), title, created_at, updated_at, status
- `messages`: id (uuid), conv_id (FK), role (enum: user/assistant/tool),
  content (text), metadata_json, created_at
- `content_drafts`: id (uuid), conv_id (FK), version (int), content_html (text),
  sources_json (jsonb), tracking_intent_json (jsonb), created_at

## Claude Tool Use

Tools available to the orchestrator:

1. `retrieve_brand_info(query, filters)` → calls retrieval service on brand index
2. `retrieve_compliance_risks(query)` → calls retrieval on compliance index
3. `retrieve_market_insights(query, filters)` → market index
4. `retrieve_competitive_intel(query, filters)` → competitive index
5. `save_tracking_intent(intent_description, measurement_goals)` → stores intent
   on the active conversation for P11 to consume

System prompt includes:
- Role: pharma content strategist with MLR compliance focus
- Instruction to ask about tracking intent by message 2–3 if not volunteered
- Citation format: `[Source: {filename}, {rag_index}]`
- Output format: when generating a draft, wrap content in `<draft>…</draft>` tags
  so the backend can extract and persist to content_drafts table

## Streaming WebSocket Endpoint

```
WS /ws/conversations/{conv_id}/stream
  Client → server: { message: str }
  Server → client (per event):
    { type: "token", text: str }
    { type: "tool_call", name: str, args: dict }
    { type: "tool_result", name: str, result: any }
    { type: "draft_saved", draft_id: str }
    { type: "done" }
```

## REST Endpoints

```
POST /api/conversations                   # create new conversation
GET  /api/conversations                   # list user's conversations
GET  /api/conversations/{id}/messages     # full history
POST /api/conversations/{id}/drafts       # save a content draft (server-internal)
GET  /api/conversations/{id}/drafts       # list drafts
```

## Dev vs Prod Claude Access

```python
# config.py
CLAUDE_MODE = os.getenv("CLAUDE_MODE", "api")    # "api" | "oauth"
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
```

- "oauth" mode: subprocess the local `claude` CLI with `--print` (single-shot per
  turn — no streaming). Used for dev to avoid API key cost.
- "api" mode: use `anthropic.AsyncAnthropic()` with streaming. Used in production.

## Model

`claude-sonnet-4-6` (production balance of quality + speed).

## Dependencies

Depends on: P04 (retrieval service), P00B (auth — conversations user-scoped)

## Known Constraints

- Token budget: 8K output max per turn (prevents runaway responses)
- Conversation history: send last 10 turns to Claude (trim older)
- Prompt caching: use `cache_control` on the system prompt for billing savings
- All tool calls must complete in <8s (retrieval SLA from P04)
- Conversations are user-scoped: only the owner + admin can read

## Out of Scope

- Chat UI (P07)
- Compliance checking (P06 — runs after draft generation, not inline)
- Tracking code generation (P11 — orchestrator just captures intent)
