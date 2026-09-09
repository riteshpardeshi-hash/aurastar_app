# 010 — Tier badge falls back to the level when the backend `tier` string is missing

Status: Accepted

## Problem

An account showed **"Level 516"** next to the **"Rookie"** tier badge on the
creator dashboard and My Account. Rookie is the level-1 tier — the pairing is
obviously wrong to anyone looking at it.

## Investigation

The client does not compute the displayed tier from the level. Every surface
(`my_account_screen`, `dashboard`, `creator_profile_screen`, previously the
creator dashboard) resolves it through `auraTierForName(profile['tier'])`, which
matched the backend's `tier` enum string (`rookie | rising | viral | elite |
sigma` per `GET /profile` in the OpenAPI spec) and, on no match,
`orElse: () => auraTiers.first` — i.e. **Rookie** for any `null`, absent, or
unrecognized value.

`auraTierForLevel(level)` — a level→tier band table (1–4 Rookie, 5–9 Rising,
10–19 Viral, 20–29 Elite, 30+ Sigma) — already existed but was called nowhere
outside tests.

So the account's `/profile` response carried a large `level` but no usable
`tier` (most likely because the test account's `auraPoints` were written
directly without the backend recomputing `tier`/`level` together), and the
blind `auraTiers.first` fallback rendered Rookie. The backend level→tier
thresholds are not published in the OpenAPI spec — they live in backend code —
so the client band table is an approximation, not the authority.

## Options considered

1. **Leave it; treat as a backend data bug.** Correct in principle, but the
   client still renders a visibly inconsistent badge whenever the backend
   momentarily omits `tier`, which is exactly when a sensible fallback matters.
2. **Always compute the tier from the level, ignore the backend string.**
   Throws away the authoritative value and re-introduces the locally-guessed
   formula the codebase deliberately moved away from.
3. **Keep the backend string as the source of truth; fall back to
   `auraTierForLevel(level)` only when the string is unusable and the caller
   has a level.** Otherwise still Rookie.

## Decision

Option 3. `auraTierForName` takes an optional `{int? level}`:

- a `tier` string that matches the enum still wins (unchanged);
- otherwise, if `level` was passed, return `auraTierForLevel(level)`;
- otherwise, Rookie (unchanged default).

Call sites that have a level in scope pass it: `my_account_screen`'s
`_buildAuraPointsCard` and `dashboard`'s `_buildScaffold` (new `level` param,
threaded from the profile stream). `creator_profile_screen` is left name-only —
the public creator payload (`normaliseCreator`) carries no level and shows no
level number, so there is nothing to be inconsistent with.

The level-up detection in `dashboard` (`auraTierForName(_lastKnownTier)` /
`auraTierForName(tierName)` at the tier-change comparison) is **deliberately
left name-only**: that code compares the server's tier *strings* across fetches
to decide when to show the level-up modal, and it has no "previous level" to
pair with the previous string. Mixing a level-derived fallback in there could
fire a spurious modal when the backend drops `tier` between fetches.

## Consequences

- The badge now tracks the level number it sits next to, even when the backend
  omits `tier`. When the backend *does* send `tier`, nothing changes.
- The client band table (`auraTiers` `minLevel`s) is now load-bearing for this
  fallback. If it drifts from the real backend thresholds, a tier-string-less
  response can show a tier one band off. Acceptable: it is still far better than
  always-Rookie, and the backend string remains authoritative for the common
  path.
- `auraTierForLevel` is no longer dead code.

## Verification

`test/core/models/aura_tier_test.dart` — new `auraTierForName` cases: `null` +
level 516 → Sigma; unknown tier + level 12 → Viral; `null` + level 3 → Rookie;
a valid `'rising'` string still beats level 999; `null` + no level → Rookie
(unchanged). The Sigma/Viral cases fail against the pre-fix
`orElse: () => auraTiers.first` (they return Rookie).
