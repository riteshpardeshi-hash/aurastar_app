# 036 — Shipped builds talk only to production (Settings → Debug → API server removed)

Status: Accepted (2026-10-15)

## Problem

Release builds showed a **Debug** group in Settings. It held:

- "API server": a free-text backend URL with local presets, saved in SharedPreferences and kept
  across app updates.
- "Preview: Video Rejected".

Any user could point the app at another server, or end up stuck on one, and a URL saved once kept
applying after every update. Builds that go live must only ever use the production API.

## Decision

- `ApiConfig.baseUrl` is `ApiConfig.production`. The only exception is a developer build compiled
  with `--dart-define=API_BASE_URL=…`, which no user can set.
- Removed:
  - the runtime override (`load`, `setRuntimeOverride`, `runtimeOverride`, the
    `api_base_url_override` pref and its read in `main()`);
  - the local presets;
  - `_ApiServerDialog`;
  - the "Preview: Video Rejected" tile.

  A URL saved by an older build is now ignored.
- The Debug group shows only in debug builds or with `--dart-define=CRASH_TEST=true`, and then
  holds only "Send test crash".

## Consequences

- Release builds can't be repointed. Local QA against another backend needs a debug build with
  `--dart-define=API_BASE_URL` (for example through `adb reverse`), which is what the 2026-10-15
  challenge-create QA used.
- Before shipping, check the APK: `strings lib/arm64-v8a/libapp.so | grep api/v1` should show only
  the production URL.
- The rejected-video popup lost its manual preview. Its behaviour is still covered by the
  submission popup tests.
- Regression test: `test/features/account/screens/settings_no_api_server_picker_test.dart` (fails
  on the old Settings screen).
