import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Best-effort client-side reporting of the challenge engagement signals the
/// backend builds its creator / brand analytics counters from.
///
/// Why this exists: the `views` and `shares` figures on the creator
/// analytics screens (`creator_challenge_analytics_screen`,
/// `creator_challenge_status_screen`, `creator_insights_screen`) were
/// permanently 0 no matter how much real activity a challenge got, because
/// nothing in the app ever told the backend a view or a share had happened.
/// Per the live OpenAPI spec these counters are fed purely by events the
/// mobile client is expected to fire:
///
/// * `POST /challenges/{id}/impression` — "Fired by the mobile app when this
///   Challenge becomes visible inside the feed."
/// * `POST /challenges/{id}/watch-progress` — "Fired repeatedly by the
///   mobile app while a challenge's video is being watched."
///
/// See ADR 012 and `docs/backend-issues/004-challenge-view-share-counters-never-populate.md`.
///
/// Every method here is fire-and-forget: it never throws, never blocks the
/// caller, and silently no-ops on any network / parse failure. Analytics
/// reporting must never be able to break a screen.
class ChallengeAnalyticsService {
  ChallengeAnalyticsService._();

  static final ChallengeAnalyticsService instance =
      ChallengeAnalyticsService._();

  factory ChallengeAnalyticsService() => instance;

  @visibleForTesting
  ApiClient client = ApiClient();

  /// Challenge ids we've already sent a feed-impression for this app session.
  /// The reels feed re-emits "page changed" every time the user scrolls a
  /// card back into view, and grid feeds rebuild on every scroll — the
  /// feed-visibility impression is meant to count once per session per
  /// challenge, not once per scroll pass.
  final Set<String> _impressed = <String>{};

  /// Per-challenge watch-progress bookkeeping, keyed by challenge id.
  final Map<String, _WatchState> _watch = <String, _WatchState>{};

  /// At most one watch-progress request per challenge per this interval...
  static const _minResendGap = Duration(seconds: 5);

  /// ...and only once watched time has grown by at least this much since the
  /// last send. Together these keep a 15s clip to ~2-3 requests instead of
  /// one per player tick.
  static const _minGrowth = Duration(seconds: 3);

  /// Fire when a challenge scrolls into view in a feed, becomes the active
  /// reel, or its detail screen opens. Deduped per app session.
  void recordImpression(String challengeId) {
    if (challengeId.isEmpty) return;
    if (!_impressed.add(challengeId)) return;
    unawaited(_safe(() => client.post(
          '/challenges/$challengeId/impression',
          const <String, dynamic>{},
          auth: true,
        )));
  }

  /// Report how far into a challenge's reference video the viewer has
  /// watched. Safe to call on every player tick — it throttles internally
  /// (see [_minResendGap] / [_minGrowth]). Pass `flush: true` from the
  /// player's dispose() or on-complete handler to force the final position
  /// past the throttle so a short view still lands one row.
  void recordWatchProgress(
    String challengeId, {
    required Duration watched,
    Duration? total,
    bool flush = false,
  }) {
    if (challengeId.isEmpty || watched <= Duration.zero) return;

    final st = _watch.putIfAbsent(challengeId, _WatchState.new);
    if (watched <= st.lastSent && !flush) return;

    final now = DateTime.now();
    final grownEnough = watched - st.lastSent >= _minGrowth;
    final gapElapsed = st.lastSentAt == null ||
        now.difference(st.lastSentAt!) >= _minResendGap;
    if (!flush && !(grownEnough && gapElapsed)) return;

    st.lastSent = watched;
    st.lastSentAt = now;

    final body = <String, dynamic>{
      'watchedDuration': watched.inMilliseconds / 1000.0,
      if (total != null && total > Duration.zero)
        'videoDuration': total.inMilliseconds / 1000.0,
      'sessionId': st.sessionId,
    };
    unawaited(_safe(() => client.post(
          '/challenges/$challengeId/watch-progress',
          body,
          auth: true,
        )));
  }

  /// Drop the watch session for a challenge — call from the player's
  /// dispose(). A later view of the same challenge starts a fresh
  /// `sessionId`, which is what the backend keys one
  /// `ChallengeWatchAnalytics` row on.
  void endWatchSession(String challengeId) => _watch.remove(challengeId);

  /// Fire when the user shares a challenge from anywhere in the app.
  ///
  /// NOTE: `POST /challenges/{id}/share` is **not in the backend spec yet**.
  /// There is currently no share-event ingestion anywhere in the API, which
  /// is precisely why the creator analytics `shares` counter is always 0
  /// (the spec's own words: share-rate "Always 0 — no data source exists to
  /// compute this honestly"). This call is a deliberate no-op — it hits a
  /// 404 that [_safe] swallows — until the backend adds the endpoint. Wiring
  /// it at every share site now means the client side is finished the moment
  /// that endpoint lands. See
  /// `docs/backend-issues/004-challenge-view-share-counters-never-populate.md`.
  void recordShare(String challengeId, {String? platform}) {
    if (challengeId.isEmpty) return;
    unawaited(_safe(() => client.post(
          '/challenges/$challengeId/share',
          <String, dynamic>{if (platform != null) 'platform': platform},
          auth: true,
        )));
  }

  @visibleForTesting
  void resetForTest() {
    _impressed.clear();
    _watch.clear();
  }

  Future<void> _safe(Future<Object?> Function() send) async {
    try {
      await send();
    } catch (_) {
      // Best-effort telemetry — a failed report must never surface to the UI.
    }
  }
}

class _WatchState {
  Duration lastSent = Duration.zero;
  DateTime? lastSentAt;

  /// One id per (challenge, view) so the backend can upsert a single
  /// watch-analytics row per viewing session rather than per request.
  final String sessionId =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${(_seq++).toRadixString(36)}';

  static int _seq = 0;
}
