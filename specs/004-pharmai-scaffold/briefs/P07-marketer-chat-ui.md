# Pharma Content AI — P07: Marketer Chat Interface

## Overview

React frontend for the marketer's primary workflow: chat with the AI to generate
promotional content. Left panel: conversation history list. Center: chat thread
with streaming responses. Right sidebar: dynamic insight panels showing sources
cited, compliance flag summary, and tracking intent captured. Login screen gates
access (JWT). Built with Vite + React + TypeScript. Served as static files by
Nginx in Docker.

## Tech Stack

- React 18 + TypeScript
- Vite (build tool)
- TailwindCSS (utility-first styling)
- Zustand (client state: auth token, active conversation)
- React Query (server state: conversations, messages)
- WebSocket (native browser API for streaming)

## Pages & Components

```
/login                         # email + password → JWT
/chat                          # main view (requires marketer or admin role)
  ConversationList (left)      # user's conversations, "New" button
  ChatThread (center)          # messages, input box, streaming token display
  InsightSidebar (right)       # Sources, ComplianceFlags, TrackingIntent panels
/chat/{convId}                 # deep link to a specific conversation
```

## WebSocket Client

Connects to `WS /ws/conversations/{convId}/stream`. On `token` events: append to
the current assistant message. On `tool_call` events: show "Searching [index]…"
indicator. On `draft_saved` events: refresh sidebar. On `done`: finalize message.

## Auth Flow

- POST `/auth/login` → store access token in memory, refresh token in httpOnly cookie
- Auto-refresh on 401 (axios/fetch interceptor)
- Logout clears memory token; cookie expires

## Sidebar Panels

- **Sources**: list of cited documents with rag_index badge, clickable to expand chunk
- **Compliance Flags**: count by severity; expandable to inline flags (data from P06)
- **Tracking Intent**: captured intent from conversation (from P05 tool call); editable

## Frontend Project Structure

```
frontend/
  package.json
  vite.config.ts
  tsconfig.json
  tailwind.config.js
  src/
    main.tsx
    App.tsx
    api/         # fetch wrappers for /api endpoints
    components/  # ChatThread, InsightSidebar, etc.
    pages/       # Login, Chat
    hooks/       # useConversation, useWebSocket
    store/       # Zustand stores
    types/       # TS types matching backend Pydantic schemas
```

## Docker

```
frontend/Dockerfile             # node build → nginx serve
docker-compose.yml              # add frontend service on port 3000
```

## Dependencies

Depends on: P05 (orchestrator WebSocket), P06 (compliance flags API), P00B (auth endpoints)

## Known Constraints

- Standalone `frontend/` directory with its own package.json (no monorepo)
- Mobile-responsive NOT required (enterprise desktop-only)
- No real-time collaboration (single user per conversation)
- No rich text editor in chat input — plain `<textarea>` only
- Frontend smoke test: Playwright spec covering login + send-message flow

## Out of Scope

- MLR review UI (P08)
- Admin dashboard (P09)
- Production asset / tracking UI (P10–P12)
