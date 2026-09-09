# 004 — Auto-read the login OTP from SMS (Message Central), drop the response echo

Status: Accepted

## Problem

The backend's OTP delivery changed. Per the OpenAPI spec
(`/auth/otp/request`, ADR 079/081 on the backend side):

- **The raw OTP is never returned in the response anymore**, in any
  environment. The success body is now
  `{ message, expiresAt, validitySeconds }`.
- The only real SMS channel is **Message Central's Verify API v3**
  (`otp.provider = messageCentral`); `console` is a dev/CI stub that just
  logs the code.
- `/auth/otp/request` now enforces a **resend cooldown**
  (`otp.resend_cooldown_seconds`, default 60s) and a sliding-window request
  cap, both returning `429` with a ready-to-display message
  ("Please wait 58 seconds before requesting another OTP.").

The client (`phone_auth_screen.dart`) was built around the old behavior:
`requestOtp()` returned the code from `data.otp` and the screen did
`_otpCtrl.text = otp`, so in practice the field filled itself with no SMS
involved. With the new backend that path is dead — `data.otp` is always
absent — and there is nothing to replace it: the user would have to read the
SMS and type six digits by hand. There was also no resend control at all, so
users who didn't get the SMS immediately had no in-app way forward, and a
retry would just hit a raw `429`.

## Investigation

- Live spec confirms the response shape and the `429` contract
  (`http://144.91.79.237:3786/docs/openapi.yaml`).
- Reading an SMS on-device is platform-specific:
  - **Android** has two no-permission Google Play services APIs — the **SMS
    Retriever API** (fully automatic, but the SMS body must end with an
    11-char hash identifying the app) and the **SMS User Consent API** (a
    one-tap "allow this app to read the message?" dialog, no hash).
  - **iOS** has no SMS-read API. The OS offers the code through the
    keyboard's QuickType bar when the field declares
    `AutofillHints.oneTimeCode`.
- `smart_auth` (3.2.0) wraps both Android APIs. The project toolchain
  already exceeds its requirements (AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14,
  Java 17), and neither API needs a manifest permission, so adoption is a
  pure `pubspec` add.
- The Retriever hash differs per signing key (debug vs. release) and has to
  be embedded by whoever composes the SMS — i.e. Message Central's template.
  We don't control that template from this repo.

## Options considered

1. **SMS Retriever API only** — fully seamless, no dialog. But it is inert
   until Message Central appends our app-signature hash to every OTP SMS.
   Until then, auto-fill silently does nothing and there is no fallback —
   the worst failure mode (looks shipped, isn't).
2. **SMS User Consent API only** — works the day it ships, no backend or
   Message Central coordination, no per-keystore hash management. Costs the
   user one extra tap on a system dialog per login.
3. **Both, in parallel** — start the Retriever and User Consent listeners
   together; first code wins, cancel the other. Same amount of client code
   as (2) via `smart_auth`. Ships working today on the Consent path, and
   upgrades itself to zero-tap the moment the Message Central template
   carries the hash — no app release needed.

## Decision

**Option 3.** `lib/core/services/sms_otp_autofill.dart` runs both listeners
and completes with the first 6-digit extraction (matcher pinned to
`\d{6}` — the spec guarantees exactly six digits — so it can't latch onto an
unrelated number in the message). `phone_auth_screen.dart`:

- `requestOtp()` now returns `({ int validitySeconds, DateTime? expiresAt })`
  and never looks for `data.otp`. The direct `_otpCtrl.text = otp` assignment
  is gone.
- After a successful send it starts `SmsOtpAutofill.waitForCode()`; a clean
  6-digit read fills the field **and auto-submits**, so the happy path needs
  zero taps (Retriever) or one (Consent).
- A 60s resend countdown ("Resend OTP in Ns" → tappable "Resend OTP") mirrors
  the backend cooldown so the button doesn't offer a resend the backend
  would `429`. A `429` that does happen shows its message verbatim
  (`humanizeError` passes non-network strings through unchanged).
- The OTP field declares `AutofillHints.oneTimeCode` (inside an
  `AutofillGroup`) for iOS QuickType; the phone field declares
  `telephoneNumberNational`.
- `SmsOtpAutofill` is injectable on `PhoneAuthScreen` for tests and is a
  no-op on non-Android platforms.

### App-signature hash (hand-off to the backend team)

For the Retriever path to actually fire, Message Central's OTP SMS template
must end with our 11-char hash, and the message must be ≤ 140 bytes, e.g.:

```
<#> Your Aura Arena code is 123456
FA+9qCX9VSu
```

There is one hash **per signing key**. To obtain them:

- Debug: run the app on a device and call
  `SmartAuth.instance.getAppSignature()` (temporary, log the result), or use
  Google's `AppSignatureHelper`.
- Release / Play App Signing: compute
  `Base64(SHA-256(SHA-256("<applicationId> <base64 DER cert>"))[0..8])` from
  the upload/signing cert, or read it once from a Play internal-testing
  build via the same `getAppSignature()` call.

Until those are in the template, logins work via the User Consent dialog
with no code change.

## Consequences

- New dependency: `smart_auth` (Android-only plugin, no permissions, no
  Gradle changes).
- Happy-path login is now one tap (Consent) and becomes zero-tap once the
  Message Central template carries the hash — no client release required for
  that upgrade.
- The `console` provider still returns no code to the client, matching prod;
  local/CI testing of the full flow needs the code from the server logs
  typed in manually (or the injected `SmsOtpAutofill` in widget tests).
- iOS depends entirely on QuickType — if the carrier/sender formatting
  defeats iOS's heuristic, the user types the code. No regression vs. today.
- `expiresAt` is parsed but not yet surfaced in the UI; a visible "code
  expires in N:NN" is possible follow-up.

## Verification

`flutter test test/features/auth/` — all green. New coverage:

- `phone_auth_screen_test.dart`
  - *"the OTP is never auto-filled from the request response"* — response
    includes `data.otp`; asserts the field stays empty. Fails against
    pre-fix code (it set `_otpCtrl.text = otp`).
  - *"a 429 resend cooldown surfaces the backend wait message"* — asserts
    the backend's "Please wait 58 seconds…" string reaches the snackbar.
  - *"resend is gated by a 60s countdown, then requests a new OTP"* —
    countdown shown, `Resend OTP` absent until 60s elapse, then a tap
    re-requests.
  - *"a code read from the SMS auto-submits without the user typing"* —
    injected `SmsOtpAutofill` yields `482910`; asserts `/auth/otp/verify`
    is called with that code and the field shows it, no typing.
- `auth_api_service_test.dart` — `requestOtp` parses
  `validitySeconds`/`expiresAt`, defaults `validitySeconds` to 180 when
  absent, and throws the backend message on `429`.

The Retriever-vs-Consent race and the on-device SMS read itself are not
unit-testable (they need Play services + a real SMS); covered by manual
device testing.
