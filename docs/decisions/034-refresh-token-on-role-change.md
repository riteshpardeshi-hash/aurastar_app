# 034 — Pick up a role change immediately (fresh tokens on promotion, refresh on role-refused 403)

Status: Accepted (2026-10-15) · Backend: ADR 132

## Problem

A user who became a creator kept getting "Access denied. Requires one of: creator" on every
creator screen (create challenge → categories, My challenges) for up to 15 minutes. Seen in
production on iOS on 2026-10-15.

## Investigation

The access token's `role` is fixed when it's issued (15-minute lifetime). Becoming a creator
changes the role in the database, not in the token. `ApiClient` refreshed only on **401**; a role
refusal is a **403**, so the app kept the stale "player" token until it expired.

## Options considered

1. Ask users to log out and back in — not acceptable.
2. Refresh on every 403 — would also refresh on unrelated 403s (blocked user, ownership checks).
3. **Store the fresh tokens the backend now returns on promotion, and refresh once on a 403 whose
   message is the role guard's "Requires one of"** — chosen.

## Decision

- `ApiClient._needsRefresh`: 401, or 403 containing "Requires one of" → one refresh (the refresh
  endpoint re-reads the role) and one retry, in every request method.
- `ApiClient.saveTokensFrom` stores `data.tokens` from `POST /creator/page` (backend ADR 132);
  `CreatorPageService.createPage` calls it before returning.

## Consequences

- Creator features work the moment someone becomes a creator — including when an admin promotes
  them (the 403 path) or on another device.
- Regression tests: `test/core/services/api_client_role_refresh_test.dart` (fail on the old
  client, pass now).
