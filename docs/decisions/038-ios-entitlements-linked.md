# 038 — The iOS build uses Runner.entitlements (push + universal links)

Status: Accepted (2026-10-16)

## Problem

`ios/Runner/Runner.entitlements` declared the associated domain `applinks:aura-app-efae1.web.app`,
but no build configuration pointed at it: `project.pbxproj` had no `CODE_SIGN_ENTITLEMENTS`. The
file also had no `aps-environment`. So every iOS build shipped without either entitlement:

- **Push:** without `aps-environment`, iOS gives the app no APNs token, so Firebase Messaging and
  the SNS iOS platform endpoint (backend ADR 042) can never deliver a notification on iPhone.
- **Universal links:** without associated domains, `https://aura-app-efae1.web.app/challenge/...`
  and `/ref/...` open Safari instead of the app.

Found in the 2026-10-16 App Store readiness review. It is not an App Review blocker.

## Decision

- `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` in the Runner target's Debug, Release
  and Profile configurations.
- `Runner.entitlements` gains `aps-environment = development`. Xcode's App Store export rewrites
  it to `production` from the distribution profile, which is the standard setup.

## Consequences

- **Before merging:** the App ID `com.onadsgroup.auraapp` (and `com.onadsgroup.auraapp.prototype`
  for the prototype workflow) must have **Push Notifications** and **Associated Domains** enabled
  in the Apple Developer portal. Codemagic's App Store profile is generated from the App ID's
  capabilities. Without them, signing fails with "Provisioning profile doesn't include the
  aps-environment entitlement".
- iOS push also needs an APNs key uploaded in the Firebase console.
- Universal links also need the hosted file to list the app. The repo's
  `public/.well-known/apple-app-site-association` is correct, but the live site served an empty
  one on 2026-10-16, so Firebase Hosting must be redeployed (`firebase deploy --only hosting`).
- Not verifiable on Linux: the first Codemagic build after merge is the check (open the IPA's
  entitlements with `codesign -d --entitlements :- Runner.app`).
