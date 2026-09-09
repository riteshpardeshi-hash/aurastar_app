import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'creator_challenges_service.dart' show pickField, pickInt;

class VideosService {
  final _client = ApiClient();

  // Ids the user has deleted. `GET /profile/videos` keeps returning a video
  // after `DELETE /videos/{id}` soft-deletes it, and the server-side marker
  // it sets has proven unreliable to detect (it was a top-level
  // `status: "inactive"` as of 2026-08-05; a deleted video was observed still
  // listed with no such marker on 2026-08-27). Tracking the ids here makes a
  // delete stick in the grid regardless of what the list endpoint returns.
  //
  // Persisted to SharedPreferences, not session-scoped: the backend never
  // drops the video from `/profile/videos` (see
  // docs/backend-issues/002-profile-videos-returns-soft-deleted-videos.md),
  // so an in-memory-only set let every deleted video reappear on the next
  // cold start. Callers must `await hydrate()` before filtering a list.
  static const _prefsKey = 'videos_service.locally_deleted_ids';
  // Bounds the persisted list. 500 deleted videos is far beyond any real
  // account; the cap just stops the key growing without limit.
  static const _maxPersistedIds = 500;

  static final Set<String> _locallyDeleted = {};
  static Future<void>? _hydration;

  // ── Deleted-video Aura offset ──────────────────────────────────────────
  // The backend does NOT reverse Aura points when a user deletes their own
  // video. Verified against openapi.yaml on 2026-09-04: `DELETE /videos/{id}`
  // is documented only as "Soft-deletes the video. Requires ownership." — no
  // point reversal — and `auraPoints` only ever falls via the admin-only
  // wallet reversal/adjustment endpoints. Product still wants the wallet to
  // drop by the deleted video's earned points, so we keep a local running
  // total of points from videos this user deleted and subtract it from every
  // displayed balance (see docs/backend-issues/003-*).
  //
  // The offset only ever changes here: `deleteVideo` adds a video's points
  // once (idempotent per video id). It is NOT auto-reconciled against the
  // server balance. An earlier version shrank it whenever the server balance
  // dropped, on the theory that a drop meant the backend had finally debited
  // the deleted video — but the balance also drops for wholly unrelated
  // reasons (the daily-valid-score-limit replacement writes a negative
  // ledger entry; reward redemptions; the several call sites reading two
  // different balance endpoints into one baseline), and every such false
  // positive permanently eroded the offset until the deleted video's Aura
  // silently reappeared a session or two later. Stability across logins
  // matters more than auto-clearing the offset the day issue 003 ships —
  // that ship date is already the trigger for deleting this whole block in a
  // client release (see ADR 008).
  static const _prefsAuraKey = 'videos_service.deleted_video_aura';
  // Retired key from the reconcile-against-baseline version; cleared on
  // hydrate so it doesn't linger in users' prefs.
  static const _prefsAuraBaselineKey =
      'videos_service.deleted_video_aura_baseline';

  static int _deletedVideoAura = 0;

  /// Total Aura points to subtract from a displayed balance to account for
  /// videos this user has deleted but the backend has not yet debited.
  static int get deletedVideoAuraOffset => _deletedVideoAura;

  /// [serverBalance] with the deleted-video offset applied, floored at 0.
  /// Pure and synchronous — safe to call from `build()`. Returns the raw
  /// value unchanged when there is no offset (the common case).
  static int adjustBalanceForDeletedVideos(int serverBalance) {
    if (_deletedVideoAura <= 0) return serverBalance;
    final adjusted = serverBalance - _deletedVideoAura;
    return adjusted < 0 ? 0 : adjusted;
  }

  /// Server leaderboards rank the current user by their *server* Aura total,
  /// which still counts points from videos they have deleted (the same gap
  /// [adjustBalanceForDeletedVideos] papers over on the wallet). Given
  /// [entries] — normalised leaderboard rows (`{'id', 'score', ...}`) already
  /// in server rank order — this returns a copy with the current user's row
  /// re-scored by the offset and moved down to the position that adjusted
  /// score earns, leaving every other row's server order untouched. No-op
  /// when there is no offset, no [currentUserId], or that user is not in the
  /// list (they're below the loaded page — the caller's own "your position"
  /// footer, itself offset-adjusted, covers that case).
  ///
  /// Pure and synchronous — safe to call from `build()`. Requires [hydrate]
  /// to have run for the offset to be non-zero.
  static List<Map<String, dynamic>> applyDeletedVideoOffsetToLeaderboard(
    List<Map<String, dynamic>> entries,
    String? currentUserId,
  ) {
    if (_deletedVideoAura <= 0 || currentUserId == null) return entries;
    final idx = entries.indexWhere((e) => e['id'] == currentUserId);
    if (idx < 0) return entries;

    final me = Map<String, dynamic>.from(entries[idx]);
    final adjusted = ((me['score'] as num?)?.toInt() ?? 0) - _deletedVideoAura;
    me['score'] = adjusted < 0 ? 0 : adjusted;

    final reordered = [...entries]..removeAt(idx);
    final myScore = me['score'] as int;
    // reordered is still in server (score-desc) order, so the first row that
    // now outranks the user marks where their row belongs.
    var insertAt = reordered
        .indexWhere((e) => ((e['score'] as num?)?.toInt() ?? 0) < myScore);
    if (insertAt < 0) insertAt = reordered.length;
    reordered.insert(insertAt, me);
    return reordered;
  }

  static Future<void> _persistAura() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsAuraKey, _deletedVideoAura);
    } catch (_) {
      // Best-effort — the in-memory value still covers the current session.
    }
  }

  /// Loads the persisted deleted-id set into memory. Idempotent, cheap, and
  /// safe to call concurrently — the first call does the read, later calls
  /// await the same future. Call (and await) this before filtering a
  /// `/profile/videos` list so a delete from an earlier launch still counts.
  static Future<void> hydrate() {
    return _hydration ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _locallyDeleted.addAll(prefs.getStringList(_prefsKey) ?? const []);
        _deletedVideoAura = prefs.getInt(_prefsAuraKey) ?? 0;
        if (prefs.containsKey(_prefsAuraBaselineKey)) {
          await prefs.remove(_prefsAuraBaselineKey);
        }
      } catch (_) {
        // Prefs unavailable (not expected post-bootstrap) — degrade to
        // session-only tracking rather than failing the grid load.
      }
    }();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Merge with what's already stored rather than overwriting: a delete
      // can happen before any caller has run hydrate() this launch (e.g.
      // straight from a video-detail screen), and the in-memory set would
      // then be missing ids persisted on an earlier launch.
      _locallyDeleted.addAll(prefs.getStringList(_prefsKey) ?? const []);
      // _locallyDeleted is a LinkedHashSet, so toList() is insertion order —
      // keep the most recent ids when trimming to the cap.
      var ids = _locallyDeleted.toList();
      if (ids.length > _maxPersistedIds) {
        ids = ids.sublist(ids.length - _maxPersistedIds);
      }
      _locallyDeleted
        ..clear()
        ..addAll(ids);
      await prefs.setStringList(_prefsKey, ids);
    } catch (_) {
      // Best-effort — the in-memory set still covers the current session.
    }
  }

  @visibleForTesting
  static void resetLocallyDeletedForTest() {
    _locallyDeleted.clear();
    _hydration = null;
    _deletedVideoAura = 0;
  }

  /// True if [video] — a raw `/profile/videos` list item — is one the user
  /// has deleted (this launch or a previous one, per the persisted set —
  /// call [hydrate] first), or one the backend has flagged as soft-deleted.
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
  // server-side). It does NOT reverse Aura points (see the "Deleted-video
  // Aura offset" block above), so [auraPoints] — the points this video
  // earned, or 0 if it earned none — is recorded locally and subtracted
  // from displayed balances until the backend debits it itself.
  Future<void> deleteVideo(String videoId, {int auraPoints = 0}) async {
    // Load any offset/ids persisted on an earlier launch before we mutate
    // them — this can be the first call this launch (delete straight from a
    // video-detail screen, before any grid ran hydrate()).
    await hydrate();
    final alreadyRecorded = _locallyDeleted.contains(videoId);

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
      await _persist();
      // Only count the points once per video — a re-delete of a still-listed
      // soft-deleted video must not stack the deduction again.
      if (auraPoints > 0 && !alreadyRecorded) {
        _deletedVideoAura += auraPoints;
        await _persistAura();
      }
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
