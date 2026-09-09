import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── Campaign end-date helpers ──────────────────────────────────────────────────

/// Returns a human-readable end-date label, e.g. "Ends today", "3 days left",
/// "Ends Jan 15". Returns empty string when [raw] is null or already expired.
String campaignEndLabel(dynamic raw) {
  if (raw == null) return '';
  try {
    final end = (raw as Timestamp).toDate();
    final diff = end.difference(DateTime.now());
    if (diff.isNegative) return '';
    if (diff.inHours < 24) return 'Ends today';
    if (diff.inDays == 1) return 'Ends tomorrow';
    if (diff.inDays <= 7) return '${diff.inDays} days left';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Ends ${months[end.month - 1]} ${end.day}';
  } catch (_) {
    return '';
  }
}

/// Urgency colour that matches the label: red ≤1 day, orange ≤3 days, else grey.
Color campaignEndColor(dynamic raw) {
  if (raw == null) return Colors.white54;
  try {
    final diff = (raw as Timestamp).toDate().difference(DateTime.now());
    if (diff.inDays <= 1) return Colors.redAccent;
    if (diff.inDays <= 3) return Colors.orange;
    return Colors.white54;
  } catch (_) {
    return Colors.white54;
  }
}

// ──────────────────────────────────────────────────────────────────────────────

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
