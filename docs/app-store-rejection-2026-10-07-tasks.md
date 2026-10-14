# App Store rejection — Aura Arena 1.0 (62) — task list

Rejected 2026-10-07 (iPad Air 11-inch M3, iPadOS 27.0). Submission ID 8f1af578-cc8d-4344-9705-5a8f41843348.
Last updated 2026-10-09.

Legend: [x] done · [ ] pending · (BE) blocked on backend · (ASC) App Store Connect, done by account admin

## 5.1.2 — Leaderboard consent / privacy policy
- [x] Leaderboard disclosure line added to `LegalConsentText` (app, uncommitted)
- [x] Privacy Policy URL set in ASC: https://www.auraarenaplay.com/legal/privacy.html (ASC)
- [ ] Open the policy URL in a browser; confirm it loads and mentions leaderboard score sharing
- [x] Agree / Not now leaderboard consent prompt + Settings toggle; only consenting users on public boards (ADR 032, backend ADR 129)

## 5.1.2(i) — Tracking / App Tracking Transparency
- [x] Crash Data label edited: purposes = Analytics + App Functionality, linked to identity = Yes (app calls `setUserIdentifier`), used for tracking = No (ASC)
- [ ] Confirm the privacy label is **Published** and "Data Used to Track You" is gone from the preview (ASC)
- [ ] Add missing data types as linked, not tracking: Photos or Videos, Other User Content, User ID, Device ID / Product Interaction (Firebase Analytics) (ASC)
- [x] Confirm Firebase Analytics shares no data with ad networks or data brokers (2026-10-13: code settings checked; GA console checked on aura-arena-81e92: no product links, Google signals off, all data sharing settings off. Still open: merged-manifest check on a release build, and confirming iOS events reach GA)

## 3.1.1 — In-App Purchase (level-up vouchers)
- [ ] Reply to Apple in ASC: vouchers are free rewards earned by leveling up, not purchases (ASC)
- [ ] (BE) Fix affiliate links so "Shop now" doesn't look like a payment flow

## 2.1(a) — "Shop Now" error
- Root cause: `/r/:grantId` redirect lands on linksredirect.com with "You don't have any approved channel"; coupon card also shows a `localhost:3000` URL
- [~] Client work in progress, uncommitted: `coupons_sheet.dart`, `rewards_screen.dart`, new `open_coupon_link.dart` + test
- [ ] Hide catalog "Shop now" on iOS and/or harden `launchUrl` failure handling
- [ ] (BE) Approve the affiliate channel
- [ ] (BE) Fix the `localhost:3000` redirect base URL

## 1.2 — User-generated content
- [x] Explicit Terms checkbox gate on `PhoneAuthScreen`, with regression tests
- [x] Acceptance recorded on the backend after sign-in (`POST /profile/terms-acceptance`, ADR 032)
- [x] Blocks reach the team: a `block` row in the admin Moderation Queue (backend ADR 129)
- [x] Support email in Settings → Contact Support: info@onadsgroup.com (ADR 032)
- [x] Stale `auth_choice` link test fixed
- [x] Website Terms page has the "no tolerance for objectionable content" section
- [x] Backend request written: `docs/backend-issues/006-user-block-and-report-endpoints-missing.md`
- [x] (BE) Block and report endpoints (backend ADR 117)
- [x] Block / Report UI: flag content, block users, remove blocked content from the feed instantly
- [ ] Process to act on reports within 24 hours (remove content, eject user)
- [ ] Screen recording on a physical device: Terms before login, flag content, block user
- [ ] Add the recording to App Review Notes in ASC and reply to Apple

## 2.3.6 — Age rating
- [x] Parental Controls = No, Age Assurance = No (ASC)
- [x] "Social Media Disabled for Users Under 13" = No (Yes would force Age Assurance = Yes)
- [x] Saved (ASC)
- [ ] Verify "Unrestricted Web Access": set to No if the app has no in-app browser
- [ ] Reply to Apple that Parental Controls / Age Assurance were set to None

## Before resubmitting
- [ ] `flutter test test/shared/widgets/app_bottom_nav_test.dart test/features/shell/main_shell_test.dart` passes
- [ ] Live tap check of all four tabs from a drill-down screen (nav is touched by uncommitted changes)
- [ ] Commit the uncommitted changes
- [ ] Build and upload a new iOS build
- [ ] Resubmit with review notes covering ATT (not tracking), vouchers, and the block/report location
