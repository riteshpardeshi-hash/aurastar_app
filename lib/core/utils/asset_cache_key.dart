/// A stable cache key for a presigned S3 / CDN asset URL.
///
/// The backend re-signs `thumbnailUrl` / `videoUrl` on every read — a fresh
/// `?X-Amz-Signature=…&X-Amz-Date=…&X-Amz-Expires=…` on each response — so the
/// *same* stored object arrives as a different URL string every time. Keying
/// an image or file cache on the raw URL therefore misses on every re-sign
/// and re-downloads the asset (the "thumbnails reload on every screen" bug).
///
/// This drops the query and fragment, collapsing every signed variant of one
/// object to a single key (`scheme://authority/path`). Returns the input
/// unchanged if it doesn't parse as an absolute URL, so a bare key or a
/// data: URI is passed straight through.
String assetCacheKey(String url) {
  if (url.isEmpty) return url;
  final u = Uri.tryParse(url);
  if (u == null || !u.hasScheme || u.authority.isEmpty) return url;
  return '${u.scheme}://${u.authority}${u.path}';
}
