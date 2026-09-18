# 021 — Challenge/submission reports must go through the REST backend, not Firestore

Status: Accepted

## Problem

A user reported two challenges from `ChallengeDetail`'s "Report challenge"
sheet. The app showed the normal "Report submitted. Thank you for your
feedback." success toast. Neither report ever appeared in the backend's
Trust & Safety → Moderation Queue (`GET /admin/moderation/queue`, rendered
by the admin panel's Moderation Queue page) — an admin checking that page
saw only AI-flag and creator-report rows, never a `challenge_report` row for
either reported challenge.

## Investigation

`_ReportSheetState._submit` (`lib/features/challenges/screens/
challenge_detail.dart`) wrote directly to Firestore:

```dart
await FirebaseFirestore.instance.collection('reports').add({
  'challengeId': widget.challengeId,
  ...
  'status': 'pending',
  'createdAt': FieldValue.serverTimestamp(),
});
```

This is a leftover from before the app moved off Firestore-as-backend (see
this repo's own `CLAUDE.md`: the client used to be Firebase-only; most
domains — auth, challenges, submissions — were migrated to the REST backend,
but this write path wasn't). The backend's moderation queue
(`moderation.service.js#listQueue`) only ever reads its own `ChallengeReport`
Mongo collection (created via `POST /api/v1/challenges/:id/report`, added by
backend ADR 086 / AURA-022). Nothing on the backend reads the Firestore
`reports` collection. So the write "succeeded" (Firestore accepted it, the
success toast fired) but the data landed somewhere no admin tooling ever
looks — confirmed by running the app against a local backend instance and
watching its request log: submitting a report through the sheet produced
zero HTTP requests to the backend at all.

`_SubmissionReportSheet` (reporting a submission, not a challenge) has the
same Firestore-write pattern, but was **not** touched here — the backend has
no REST endpoint for reporting a submission at all (only `challenge_report`
and admin-initiated `creator_report` exist as moderation-queue sources; see
backend ADR 097's Consequences section, which independently flags this same
gap from the backend side). Fixing that would mean adding a new backend
endpoint + model wiring, a separate, larger change — tracked as follow-up,
not fixed here.

## Options considered

1. **Write to both Firestore and the backend** — keeps whatever (if
   anything) currently reads the Firestore `reports` collection working.
   Rejected: nothing on the backend reads it, and grepping the whole
   `functions/` Cloud Functions tree and this repo turns up no other reader
   either — it's dead storage, not a second system of record. Writing to it
   would just be silent debt with no consumer.
2. **Call the REST endpoint only** — matches how every other write in this
   screen already works (`createSubmission`, `recordShare`, impressions all
   go through `ChallengesService`/`ApiClient` to the backend). Chosen.

## Decision

Added `ChallengesService.reportChallenge(challengeId, reasonCode,
{remarks})`, calling `POST /challenges/:id/report` (`auth: true`), and a
`challengeReportReasonCode()` helper mapping the sheet's five human-readable
reason labels to the backend's `CHALLENGE_REPORT_REASONS` enum
(`inappropriate|spam|dangerous|misleading|copyright|other`; the full label is
still sent through as `remarks` so admins see the exact wording). Rewired
`_ReportSheetState._submit` to call it instead of Firestore. Behavior on
screen is unchanged (same reasons, same success/failure toasts); only the
destination of the data changed.

## Consequences

- Challenge reports now actually reach `GET /admin/moderation/queue` as a
  `source: "challenge_report"` row, same as reports filed any other way.
- The `reports` Firestore collection is now fully dead code from the app's
  side (still written by `_SubmissionReportSheet`, not read anywhere) — left
  alone for now since fixing submission reporting requires a new backend
  endpoint this ADR doesn't add. Flagged as follow-up work, matching the gap
  backend ADR 097 already flagged independently.
- No backend change was needed — `POST /challenges/:id/report` already
  existed and already worked correctly when called (verified end-to-end
  against a local backend: the report appears in the queue and clears when
  an admin decides its case, per backend ADR 097).

## Verification

`test/core/services/challenges_service_test.dart` — added coverage for
`reportChallenge` (posts to the right path with the mapped reason, throws
the backend's message on a non-success response) and
`challengeReportReasonCode` (every UI label maps to its documented backend
enum value; an unrecognised label falls back to `'other'` rather than
sending an invalid enum value the backend would 422 on). `flutter analyze`
clean; both new test groups pass alongside the rest of the file (26/26).

`POST /challenges/:id/report` itself is exercised end-to-end by the
backend's own `tests/integration/moderation.test.js` (files a report,
confirms it surfaces in `GET /admin/moderation/queue` as a
`challenge_report` row, confirms deciding its case resolves it) — this
change only fixes which code path the client calls, not the endpoint's own
behavior, so that coverage already covers the server side of this. The
app was reinstalled against a local backend (`localhost:3000` via `adb
reverse`) with this fix for manual in-app confirmation (tap Report on a
challenge → check it shows up in the admin panel's Moderation Queue as a
`Challenge report` row).
