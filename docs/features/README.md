# Feature docs

Standing reference for how a client-side feature works *now* — mirrors the
backend repo's `docs/features/`. Where an [ADR](../decisions/) captures a
single decision and the reasoning behind it at a point in time, a feature doc
is the living "how does this actually work" page you read before touching the
area.

Not every feature needs one. Write a feature doc when:

- The feature spans several screens/services and there is no single file that
  explains the whole thing.
- It implements a contract with the backend (event shapes, thresholds,
  dedup rules) that a reader needs stated in one place.
- Behaviour is non-obvious from the code and easy to break by "cleaning up"
  (throttles, session keys, fire-and-forget error handling).

Keep it short and keep it current. If a feature doc and the code disagree, the
code wins and the doc is a bug — fix it in the same PR as the behaviour
change, the way the backend repo does.

## Index

| Doc | What it covers |
| --- | --- |
| [engagement-reporting.md](engagement-reporting.md) | How the client reports challenge impressions, views (watch progress) and shares, and the definitions it holds up its end of. |
