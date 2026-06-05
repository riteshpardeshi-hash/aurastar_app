/// Transforms Firebase Storage URLs to CDN-compatible URLs.
/// Set [_cdnBase] to your CDN host once it's configured.
const _cdnBase = ''; // e.g. 'https://cdn.your-domain.com'

String toCdnUrl(String storageUrl) {
  if (_cdnBase.isEmpty || storageUrl.isEmpty) return storageUrl;
  return storageUrl.replaceFirst(
    'https://firebasestorage.googleapis.com',
    _cdnBase,
  );
}

/// Returns the 480p optimised variant URL if the backend generates one.
/// Expects backend to store path/original.mp4 alongside path/480p.mp4.
String toOptimizedVideoUrl(String videoUrl) {
  if (videoUrl.isEmpty) return videoUrl;
  // Uncomment when backend generates 480p variants:
  // return videoUrl.replaceFirst('/original.mp4', '/480p.mp4');
  return toCdnUrl(videoUrl);
}

String toThumbnailUrl(String videoUrl) {
  if (videoUrl.isEmpty) return videoUrl;
  // Uncomment when backend generates thumbnails:
  // return videoUrl.replaceFirst(RegExp(r'\.[^.]+$'), '_thumb.jpg');
  return videoUrl;
}
