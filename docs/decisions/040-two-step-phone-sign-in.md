# 040 — Phone sign-in in two steps: number, then code

Status: Accepted

## Problem

A user typed a valid OTP but the button still said "Get OTP", and retrying said "Please wait
25 seconds before requesting another OTP".

## Investigation

Backend log: the first `POST /auth/otp/request` returned 200 (the SMS went out) but the app
never received the answer (the connection dropped) and timed out after 15 s, so it stayed on
the "Get OTP" step. The OTP box was always visible, so the code could be typed next to a
button that would only request another one; the retries hit the 60 s cooldown (429).

## Options considered

1. **Keep one screen, fix the flag** — still lets a code be typed before one is requested.
2. **Two steps** (as Swiggy/Zomato do) — chosen.

## Decision

`PhoneAuthScreen` has a mobile-number step and a verify step; the logic lives in
`PhoneAuthController` (unit-tested without UI). A cooldown 429 means a code was just sent, so
the app goes straight to code entry with the real countdown; a lost answer offers "Already got
a code? Enter it". Six code boxes (`OtpCodeInput`) back one real field, so paste and autofill
work, and the code auto-submits. Wrong / expired / too-many-attempts / network errors each
have their own message. The App Store review number 1234567890 stays valid.

## Consequences

The orb animation runs once (an endless animation would keep widget tests from settling).

## Verification

`test/features/auth/phone_auth_controller_test.dart`,
`test/features/auth/screens/phone_auth_screen_test.dart`.
