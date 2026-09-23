import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'creator_challenges_service.dart' show pickField, pickInt;

class VideosService {
  final _client = ApiClient();

  static const _maxPersistedIds = 500;
  static Future<void>? _hydration;

  // ── Front-camera Android mirror flag ───────────────────────────────────
  // ADR 026: on Android, a front-camera take is recorded un-mirrored (the
  // camera plugin's platform default), so the review screen right after
  // recording flips playback locally to match what the user saw framing
  // themselves. The uploaded file itself is deliberately left un-mirrored —
  // the feed/reels/AI scorer need the true orientation. But that means any
  // *other* screen that plays the user's own video back to them (My Videos,
  // the video detail screen) shows the same true-but-"backwards"-looking
  // file, with nothing in the `/profile/videos` response to say it needs the
  // same flip.
  //
  // There is no server field for this (see ADR 026's "Consequences": the
  // flag "rides on the local navigation/queue only... derived fresh each
  // recording"). So PreviewScreen records which video ids it mirrored,
  // keyed by the Video document id (the same `videoId` /profile/videos
  // returns), and every other own-video playback surface looks it up here.
  // Same device only — a reinstall or a second device won't have it.
  static const _prefsMirroredKey = 'videos_service.locally_mirrored_ids';
  static final Set<String> _locallyMirrored = {};

  /// Loads the persisted mirror-flag set into memory. Idempotent, cheap, and
  /// safe to call concurrently — the first call does the read, later calls
  /// await the same future.
  static Future<void> hydrate() {
    return _hydration ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _locallyMirrored
            .addAll(prefs.getStringList(_prefsMirroredKey) ?? const []);
      } catch (_) {
        // Prefs unavailable (not expected post-bootstrap) — degrade to
        // session-only tracking rather than failing the grid load.
      }
    }();
  }

  @visibleForTesting
  static void resetLocallyMirroredForTest() {
    _locallyMirrored.clear();
    _hydration = null;
  }

  /// Records that [videoId] (the Video document id `/profile/videos` and the
  /// presign step both use) needs its playback horizontally flipped on any
  /// own-video screen. Call once, right after a front-camera Android upload
  /// succeeds — see PreviewScreen._doUpload.
  static Future<void> markMirrored(String videoId) async {
    if (videoId.isEmpty) return;
    await hydrate();
    _locallyMirrored.add(videoId);
    try {
      final prefs = await SharedPreferences.getInstance();
      // Merge with what's already stored, same reasoning as _persist above.
      _locallyMirrored
          .addAll(prefs.getStringList(_prefsMirroredKey) ?? const []);
      var ids = _locallyMirrored.toList();
      if (ids.length > _maxPersistedIds) {
        ids = ids.sublist(ids.length - _maxPersistedIds);
      }
      _locallyMirrored
        ..clear()
        ..addAll(ids);
      await prefs.setStringList(_prefsMirroredKey, ids);
    } catch (_) {
      // Best-effort — the in-memory set still covers the current session.
    }
  }

  /// True if [video] — a raw `/profile/videos` list item — was recorded on
  /// the front camera on Android and needs its playback mirrored to match
  /// what the user saw while recording. See ADR 026 and [markMirrored].
  static bool isMirroredVideo(Map<String, dynamic> video) {
    final id = video['videoId'] as String? ??
        video['_id'] as String? ??
        video['id'] as String? ??
        '';
    return id.isNotEmpty && _locallyMirrored.contains(id);
  }

  // DELETE /videos/{id} soft-deletes the video (ownership-checked
  // server-side) and, server-side, reverses any Aura points it contributed
  // if it was its challenge's best-scoring submission (backend ADR —
  // video.service.js#deleteVideo; see
  // docs/backend-issues/003-video-delete-does-not-reverse-aura-points.md,
  // resolved). `GET /profile/videos` and every other video-listing endpoint
  // now excludes soft-deleted videos at the source too (see
  // docs/backend-issues/002-profile-videos-returns-soft-deleted-videos.md,
  // resolved), so this client no longer needs to track deleted ids or a
  // local Aura offset — the server response is the single source of truth
  // for both. A `404` on delete means the video is already gone
  // server-side (e.g. a second delete attempt) — treated as an
  // already-satisfied delete, not an error to show the user.
  Future<void> deleteVideo(String videoId) async {
    final res = await _client.delete('/videos/$videoId', auth: true);
    final ok = res['status'] == 'success';
    final alreadyGone = !ok &&
        (res['message'] as String? ?? '')
            .toLowerCase()
            .contains('not found');
    if (ok || alreadyGone) return;
    throw res['message'] as String? ?? 'Failed to delete video';
  }

  // GET /videos/{id} has no documented response schema in Swagger (generic
  // envelope only) — field names are best-guess candidates via pickField,
  // same convention used elsewhere in this codebase for undocumented
  // endpoints. Passing auth lets the backend personalize `liked` for the
  // caller if it supports that; the route itself requires no auth.
  Future<Map<String, dynamic>> fetchLikeState(String videoId) async {
    try {
      final res = await _client.get('/videos/$videoId', auth: true);
      if (res['status'] != 'success') return {'liked': false, 'likesCount': 0};
      final data = res['data'] as Map<String, dynamic>? ?? {};
      return {
        'liked': pickField(data, ['isLiked', 'liked', 'hasLiked']) == true,
        'likesCount': pickInt(data, ['likesCount', 'likeCount', 'likes']),
      };
    } catch (_) {
      return {'liked': false, 'likesCount': 0};
    }
  }

  // POST /videos/{id}/like toggles like state server-side. Its response
  // shape is undocumented too, so callers apply an optimistic local flip
  // rather than trusting a specific response field back.
  Future<void> toggleLike(String videoId) async {
    final res = await _client.post('/videos/$videoId/like', {}, auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to update like';
    }
  }
}
