import 'api_client.dart';
import 'creator_challenges_service.dart' show pickField, pickInt;

class VideosService {
  final _client = ApiClient();

  // DELETE /videos/{id} soft-deletes the video (ownership-checked
  // server-side). Any Aura-point reversal this triggers is computed and
  // applied by the backend — the client does not attempt to guess or
  // display a deduction amount.
  Future<void> deleteVideo(String videoId) async {
    final res = await _client.delete('/videos/$videoId', auth: true);
    if (res['status'] != 'success') {
      throw res['message'] as String? ?? 'Failed to delete video';
    }
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
