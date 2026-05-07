# Pharma Content AI — P00B: Authentication & RBAC

## Overview

Add JWT-based authentication and role-based access control to the FastAPI app.
Three roles: `marketer` (creates content), `mlr_reviewer` (reviews and approves),
`admin` (manages users and documents). All existing endpoints gain auth middleware.
A seed script creates the first admin user.

## Auth Stack

- JWT (python-jose[cryptography]): access tokens (15min) + refresh tokens (7d)
- Passwords: bcrypt hashing (passlib)
- No external OAuth provider — email/password only. (Claude OAuth, in P05, is for LLM
  access, not for user authentication.)

## New Endpoints

```
POST /auth/register         # admin-only: create new user
POST /auth/login            # returns access + refresh tokens
POST /auth/refresh          # exchange refresh token for new access token
GET  /auth/me               # current user info
DELETE /auth/users/{id}     # admin-only: deactivate user
```

## PostgreSQL Schema Additions

- `users`: id (uuid), email (unique), hashed_password, role (enum: marketer/mlr_reviewer/admin),
  is_active (bool), created_at

## Middleware

- `get_current_user` dependency: validates JWT, returns user
- `require_role(*roles)` dependency factory: raises 403 if user role not in list
- Apply to existing document/set endpoints from P00A: require `marketer` or higher
- Admin-only: user management endpoints

## Seed Script

```bash
python scripts/seed_admin.py --email admin@example.com --password changeme
```

The script connects via DATABASE_URL from .env, creates an admin user with the
given credentials, exits.

## Dependencies

- Depends on: P00A (PostgreSQL + modular FastAPI structure)
- New packages: python-jose[cryptography], passlib[bcrypt]

## Setup

```bash
alembic upgrade head           # adds users table
python scripts/seed_admin.py
```

## Known Constraints

- Tokens stored client-side only (no server-side session store this phase)
- Role cannot be changed via API — admin must update DB directly (workflow for now)
- All pytest integration tests must pass with auth headers attached
- New tests required: test_auth.py covering register/login/refresh/me/role-gating

## Out of Scope

- SSO / SAML / LDAP (enterprise integration — future)
- Password reset email flow
- Multi-tenancy (single org deployment)
- Frontend login UI (P07)
