# 014 — Cache thumbnails/videos on a stable (unsigned) URL key

Status: Accepted

## Problem

Bug report: "Thumbnails are loading very slowly on every screen." Not a
connection issue — the same thumbnails re-download and flash their shimmer
every time a screen is opened or scrolled back to, on a fast connection.

## Investigation

`Challenge.thumbnailUrl` (and `videoUrl`) are **presigned S3 URLs** —
`…/uuid.jpg?X-Amz-Algorithm=…&X-Amz-Date=…&X-Amz-Expires=3600&X-Amz-Signature=…`
— and the OpenAPI spec states they are *"always resolved on read"*: the
backend generates a **fresh signature on every response**. So the same
stored object arrives as a different URL string on every list fetch.

- `VideoThumbnailWidget`'s network path used `Image.network(thumbnailUrl)`.
  Flutter's `ImageCache` keys on `NetworkImage(url)` — the **full URL,
  query included**. A re-signed URL is a cache miss → full re-download,
  showing the `loadingBuilder` shimmer while it fetches. `Image.network`
  also has **no disk cache** — only decoded frames in memory (LRU, ~1000 /
  100 MB), so a cold start or a long scroll re-downloads everything anyway.
- The SWR screen cache (ADR 007) silently re-fetches each list in the
  background and swaps it in. Every card then gets a **new** `thumbnailUrl`
  string → `VideoThumbnailWidget.didUpdateWidget` sees `old != new` →
  `setState(_loading = true)` + reload. Result: **every visible thumbnail
  flashes to the shimmer and re-downloads on every screen revisit** — the
  reported symptom.
- `toThumbnailUrl` / `toCdnUrl` are pass-throughs (no CDN configured), so
  every fetch is raw, often cross-region, S3.
- `VideoCacheService` had the identical bug: `_fileFor` hashed the **full
  signed URL** into the cache filename, so a re-signed `videoUrl` mapped to
  a new file and re-downloaded the whole clip after every list refresh /
  relaunch. Its `_fileFor` extension check (`endsWith('.mov')`) also always
  missed because of the trailing query string.

## Options considered

1. **Strip the query only in `didUpdateWidget`** so a re-sign doesn't
   trigger a reload. Helps the flash, but the underlying image still isn't
   cached to disk and the first load per session is still N full S3
   fetches.
2. **Custom `ImageProvider` that keys on the unsigned URL** but fetches the
   signed one. Works, but hand-rolls disk caching, eviction, retry — a lot
   of surface for something `cached_network_image` already does well.
3. **`cached_network_image` with an explicit `cacheKey`.** It supports a
   `cacheKey` distinct from `imageUrl`: fetch with the live signed URL, key
   the mem+disk cache on the stable one. Persistent disk cache for free.

## Decision

New `core/utils/asset_cache_key.dart` → `assetCacheKey(url)`: returns
`scheme://authority/path` (query and fragment dropped), or the input
unchanged if it isn't an absolute URL. One helper, used everywhere a
presigned asset URL is cached.

- **`VideoThumbnailWidget`** (option 1 + 3):
  - `didUpdateWidget` compares `assetCacheKey(...)`, not raw strings — a
    re-signed URL for the same object is a no-op.
  - The `thumbnailUrl` branch renders
    `CachedNetworkImage(imageUrl: <signed>, cacheKey: assetCacheKey(<signed>))`
    — disk-cached, survives restarts and list re-fetches, and a re-sign is
    a cache hit.
  - The extracted-frame in-memory cache (`videoThumbnailCache`) and its
    in-flight map are keyed on `assetCacheKey` too, so the slow
    full-video-download path also dedupes across re-signs.
- **`VideoCacheService`**: `_inFlight` and the on-disk filename are keyed on
  `assetCacheKey(videoUrl)`; the file is still *downloaded* from the live
  signed URL. Extension is now read from `Uri.parse(url).path`.
- Added dependency: `cached_network_image: ^3.4.1` (pulls
  `flutter_cache_manager`).

## Consequences

- A thumbnail downloads **once per device**, then serves from disk across
  scrolls, screen revisits, SWR refreshes and app restarts. The shimmer
  only shows on genuine first load.
- One new dependency and its transitive deps (`flutter_cache_manager`,
  `sqflite`, `rxdart`, `octo_image`). Well-established, widely used.
- `assetCacheKey` assumes the path uniquely identifies the object and the
  query is *only* auth. True for S3 presigned GETs and the CDN URLs here;
  would be wrong for an endpoint that varied content by query param (none
  are cached this way).
- Still no CDN — `toCdnUrl` remains a pass-through. Disk caching makes that
  much less painful but a CDN is still the real fix for first-load latency
  and is a backend task.
- `VideoCacheService.markViewed` / `recentlyViewed` still store full URLs;
  they have no consumers and weren't touched.

## Verification

- `test/core/utils/asset_cache_key_test.dart` — two signatures → one key;
  different objects/hosts → different keys; non-URL passthrough.
- `test/core/services/video_cache_service_test.dart` — a re-signed URL for
  the same object reuses the on-disk file (one download, not two). Fails
  against the pre-fix full-URL key.
- `test/shared/widgets/video_thumbnail_widget_test.dart` — a re-signed
  `videoUrl` does not re-extract (extract path); a re-signed `thumbnailUrl`
  keeps a stable `CachedNetworkImage.cacheKey` while `imageUrl` updates
  (network path).
