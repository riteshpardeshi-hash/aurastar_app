# 032 — Leaderboard consent, recorded Terms acceptance, support email

Status: Accepted

## Problem

Apple rejected build 1.0 (62). Three items were still missing in the app after the
Terms checkbox gate on `PhoneAuthScreen`:

- **5.1.2:** every player's name and score went onto public leaderboards without being
  asked, with no way to opt out.
- **1.2:** the ticked "I agree" box was never recorded anywhere, and the unused
  `AuthChoiceScreen` sheet still had passive "By continuing…" wording.
- **1.2:** no support contact. The Help sheet named `support@aura.app`, which doesn't exist.

## Investigation

The backend now stores `leaderboardConsent.status` (`granted | declined | null`) and
`termsAcceptedAt/termsVersion` (backend ADR 129). Only `granted` appears on any public
board. Accounts from before ADR 129 are reported as `null` too: the product decision
(2026-10-14) is that nobody is shown publicly until they agree. The hosted Privacy
Policy's contact is `info@onadsgroup.com`.

## Options considered

1. **Treat the sign-in Terms tick as leaderboard consent.** One tap fewer, but Apple asks
   for consent to this specific use, and it couldn't be withdrawn without leaving the app.
2. **Separate Agree / Not now prompt + Settings toggle.** One extra dialog, once per account.

## Decision

Option 2.

- `LeaderboardConsentService` caches the backend's answer (from GET /profile, which
  `MyAccountScreen` already loads). `MainShell` calls `askIfNeeded` after its first frame.
  It shows `LeaderboardConsentDialog` only when the backend explicitly says `status: null`.
  A profile with no `leaderboardConsent` key (an older backend) never prompts. The cache is
  reset on every sign-in and sign-out, so a second account on the same phone is asked
  separately.
- Settings → **Show me on leaderboards** (`LeaderboardConsentTile`) writes
  `PUT /profile/leaderboard-consent`.
- Each successful sign-in (phone, Google, Apple) calls `POST /profile/terms-acceptance`
  with `LegalLinks.termsVersion`. All of them sit behind the required checkbox, which is
  `LegalConsentText` in checkbox mode on both sign-in screens. It's best effort: a failure
  never blocks sign-in.
- Settings → **Contact Support** opens a mail to `LegalLinks.supportEmail`
  (`info@onadsgroup.com`), and the Help sheet names the same address.

## Consequences

- Public boards start empty for everyone after the backend deploy, and refill as people
  open the updated app and agree. Users on an older build stay hidden until they update.
- Bump `LegalLinks.termsVersion` whenever the hosted Terms change. Re-prompting existing
  users for new Terms is not built yet.
