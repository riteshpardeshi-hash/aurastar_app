import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'creator_challenges_service.dart' show pickField, pickInt;

class VideosService {
  final _client = ApiClient();

  // Ids the user has deleted this session. `GET /profile/videos` keeps
  // returning a video after `DELETE /videos/{id}` soft-deletes it, and the
  // server-side marker it sets has proven unreliable to detect (it was a
  // top-level `status: "inactive"` as of 2026-08-05; a deleted video was
  // observed still listed with no such marker on 2026-08-27). Tracking the
  // ids here makes a delete stick in the grid regardless of what the list
  // endpoint returns. Session-scoped: a real relaunch re-fetches, by which
  // point the backend should have dropped it.
  static final Set<String> _locallyDeleted = {};

  @visibleForTesting
  static void resetLocallyDeletedForTest() => _locallyDeleted.clear();

  /// True if [video] — a raw `/profile/videos` list item — is one the user
  /// deleted this session, or one the backend has flagged as soft-deleted.
  static bool isDeletedVideo(Map<String, dynamic> video) {
    final id = video['videoId'] as String? ??
        video['_id'] as String? ??
        video['id'] as String? ??
        '';
    if (id.isNotEmpty && _locallyDeleted.contains(id)) return true;
    if (video['isDeleted'] == true) return true;
    if (video['deletedAt'] != null) return true;
    final status = video['status'];
    return status == 'inactive' || status == 'deleted';
  }

  // DELETE /videos/{id} soft-deletes the video (ownership-checked
  // server-side). Any Aura-point reversal this triggers is computed and
  // applied by the backend — the client does not attempt to guess or
  // display a deduction amount.
  Future<void> deleteVideo(String videoId) async {
    final res = await _client.delete('/videos/$videoId', auth: true);
    final ok = res['status'] == 'success';
    // A "video not found" response means it's already gone server-side (e.g.
    // a second delete on a still-listed soft-deleted video) — that's a
    // satisfied delete, not an error to show the user.
    final alreadyGone = !ok &&
        (res['message'] as String? ?? '')
            .toLowerCase()
            .contains('not found');
    if (ok || alreadyGone) {
      _locallyDeleted.add(videoId);
      return;
    }
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
