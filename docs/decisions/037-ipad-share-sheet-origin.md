# 037 — Every share sheet is anchored for iPad; photo-library purpose strings

Status: Accepted (2026-10-16)

## Problem

App Review runs on an iPad (the 2026-10-07 rejection was on an iPad Air 11-inch). On iPadOS the
share sheet is a popover, and share_plus needs a non-empty `sharePositionOrigin` to anchor it.
Without one the sheet does not open, or the call throws. Only `challenge_detail.dart` passed it;
13 other `Share.share` / `Share.shareXFiles` calls did not: score cards, achievement cards,
referral link, creator challenge links, brand profile, video detail and the data export.

Separately, `Info.plist` had no `NSPhotoLibraryAddUsageDescription`. Choosing **Save Image** on a
shared score or achievement card writes to the photo library, and iOS ends an app that does that
without the string. The existing `NSPhotoLibraryUsageDescription` was vague ("may need access").

## Decision

- `lib/core/utils/share_origin.dart#shareOrigin(context)` returns the widget's on-screen rect, or
  a 1x1 rect in the middle of the screen when it has none. Every share call passes it as
  `sharePositionOrigin`. Async share handlers take it before their first `await`.
- `Info.plist`: added `NSPhotoLibraryAddUsageDescription`, and `NSPhotoLibraryUsageDescription`
  now names what it is for (profile photo, a creator's challenge video).

## Consequences

- New share calls must pass `sharePositionOrigin: shareOrigin(context)`. `grep -rn "Share.share"
  lib` should show it on every call.
- iPhone and Android ignore the origin, so nothing changes there.
- Verify on a physical iPad in TestFlight: every share button opens the sheet, and Save Image asks
  for photo access instead of closing the app.
- Regression test: `test/core/utils/share_origin_test.dart`.
