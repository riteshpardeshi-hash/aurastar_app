# 041 — One saved copy of the categories (CategoryStore)

Status: Accepted

## Problem

The create page showed "ClientConnection closed before full header was received, uri=…" in
place of the categories, with no way to retry. Five screens fetched the categories
separately, every time.

## Investigation

The backend restarted mid-request. The error text was garbled by `replaceFirst('Exception: ',
'')`, and "connection closed" wasn't recognised as a network error. Elsewhere a failed load
silently showed a made-up category list or an empty one. `GET /categories` is paginated (20 by
default) and returns presigned thumbnail URLs that expire.

## Options considered

1. **Retry in each screen** — five copies of the same fix.
2. **One store saved on the device** — chosen.

## Decision

`CategoryStore` keeps `{_id, name}` only (never the expiring URLs) in SharedPreferences,
returns it at once, refreshes it in the background after 6 hours, shares one request between
concurrent callers, fetches every page, and retries a dropped connection once. A create
request that fails with "Category not found" invalidates it and asks for another category.
Errors read "We couldn't load the categories. Check your connection and try again." with a
Try again button.

## Consequences

A category an admin adds can take up to 6 hours (or the next "not found") to appear.

## Verification

`test/core/services/category_store_test.dart`, the categories group in
`creator_challenge_draft_screen_test.dart`, `test/core/utils/error_message_test.dart`.
