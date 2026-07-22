# Architecture Decision Records

This folder mirrors the backend's `docs/api/../decisions/` convention
(see the [backend engineering docs](http://144.91.79.237:5173/) — "ADRs" in
the nav). Each file documents one non-trivial decision made in the Flutter
client: the problem faced, the options considered, and why we picked what we
picked.

**When to write one.** Not every commit needs an ADR — a typo fix or a color
tweak doesn't. Write one when:
- The fix required understanding *why* something broke, not just patching
  the symptom (e.g. a race condition, a protocol mismatch, a lifecycle bug).
- You chose between two or more real approaches and future-you (or a
  teammate) would otherwise have to re-derive the reasoning from scratch.
- The decision affects more than one screen/service, or sets a pattern
  other code is expected to follow.

**Numbering**: sequential, three digits, never reused even if a decision is
later superseded (mark it `Superseded by NNN` in the status instead).

**Format**: copy `TEMPLATE.md`. Keep it short — a decision nobody will read
because it's three pages long isn't documented, it's buried.

## Index

| # | Title | Status |
|---|-------|--------|
| 001 | [Deduped concurrent token-refresh + global session-expiry redirect](001-auth-session-failure-handling.md) | Accepted |
