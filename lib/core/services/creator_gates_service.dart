import 'api_client.dart';

/// The `/creator/gate-rules` + `/creator/challenges/{id}/gates*` "Creator Gates"
/// tag. A LIVE challenge unlocks a series of participant-count gates, each
/// crediting the creator Aura Points once enough players have submitted.
class CreatorGatesService {
  final _client = ApiClient();

  /// Static list of all gates + platform policy. Not challenge-specific.
  Future<Map<String, dynamic>?> fetchGateRules() async {
    try {
      final res = await _client.get('/creator/gate-rules');
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Current gate, progress percentage toward the next one, participant count.
  Future<Map<String, dynamic>?> fetchGateProgress(String challengeId) async {
    try {
      final res =
          await _client.get('/creator/challenges/$challengeId/gates', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// All unlocked gates + rewards earned so far, most recent first.
  Future<Map<String, dynamic>?> fetchGateHistory(String challengeId) async {
    try {
      final res = await _client.get(
          '/creator/challenges/$challengeId/gates/history', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Total Aura earned, completed/remaining gate counts.
  Future<Map<String, dynamic>?> fetchRewardSummary(String challengeId) async {
    try {
      final res = await _client.get(
          '/creator/challenges/$challengeId/rewards', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Public share URL + deep link for the creator's own LIVE challenge.
  Future<Map<String, dynamic>?> fetchShareLink(String challengeId) async {
    try {
      final res = await _client.get(
          '/creator/challenges/$challengeId/share-link', auth: true);
      if (res['status'] != 'success') return null;
      return res['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
