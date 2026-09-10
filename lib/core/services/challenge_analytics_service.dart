import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Best-effort client-side reporting of the challenge engagement signals the
/// backend builds its creator / brand analytics counters from.
///
/// The definitions this client holds up its end of (backend
/// [ADR 090](../../../docs — see backend repo); mobile ADR 012 → 018 → 019;
/// canonical: `docs/features/engagement-reporting.md`):
///
/// * **Impression** — the challenge video appeared on the user's screen, in
///   any feed. `POST /challenges/{id}/impression`. Fired **every time** a
///   sighting happens — there is no per-session de-dup here anymore; the
///   backend counts raw sightings (a scroll away and back is a new
///   impression). Also consumes a paid Campaign's impression pool when the
///   challenge is in an `ACTIVE` campaign (unchanged, backend-side).
/// * **View** — a play session in which ≥ 1s of the video was watched.
///   `POST /challenges/{id}/watch-progress` carrying a stable `sessionId`
///   per play. The backend records **one view per `sessionId`** once
///   `watchedDuration ≥ 1` (`SET NX`), so the same user replaying counts
///   again. This service just needs to (a) send a fresh `sessionId` per play
///   — see [endWatchSession] — and (b) get the first ping out as soon as 1s
///   is watched, so a short view still lands without waiting on the
///   dispose-time flush.
/// * **Share** — `POST /challenges/{id}/share`, bumps the lifetime + daily
///   `shares` counters (still a synchronous backend write — shares are not
///   buffered).
///
/// Views and impressions are absorbed into Redis backend-side and flushed to
/// Mongo ~every 60s, so the analytics screens lag real activity by up to a
/// minute — see `docs/features/engagement-reporting.md`.
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

  /// Per-challenge watch-progress bookkeeping, keyed by challenge id.
  final Map<String, _WatchState> _watch = <String, _WatchState>{};

  /// A `view` is ≥ 1s of watch time (backend ADR 090). The first
  /// watch-progress ping of a session is sent as soon as this much has been
  /// watched, bypassing the [_minGrowth] / [_minResendGap] throttle below —
  /// otherwise a genuine short view (scroll a reel, watch 2s, scroll on)
  /// would only ever reach the backend via the dispose-time `flush`.
  static const _firstPingThreshold = Duration(seconds: 1);

  /// At most one watch-progress request per challenge per this interval...
  static const _minResendGap = Duration(seconds: 5);

  /// ...and only once watched time has grown by at least this much since the
  /// last send. Together these keep a 15s clip to ~2-3 requests instead of
  /// one per player tick.
  static const _minGrowth = Duration(seconds: 3);

  /// Fire when the challenge's video appears on screen — a feed card scrolling
  /// into view, a reel becoming the active page, or the detail screen opening.
  ///
  /// **Not** de-duped: every sighting is an impression (backend ADR 090), so a
  /// card scrolled away and back, or a reel re-visited, counts each time. The
  /// caller decides what "on screen" means (e.g. [ImpressionTracker] fires
  /// this once per ≥50%-visible pass); this method just forwards it.
  void recordImpression(String challengeId) {
    if (challengeId.isEmpty) return;
    unawaited(_safe(() => client.post(
          '/challenges/$challengeId/impression',
          const <String, dynamic>{},
          auth: true,
        )));
  }

  /// Report how far into a challenge's reference video the viewer has
  /// watched. Safe to call on every player tick — it throttles internally
  /// (see [_minResendGap] / [_minGrowth]). The **first** ping of a session is
  /// sent as soon as [_firstPingThreshold] (1s) is watched so a short view
  /// still registers; pass `flush: true` from the player's dispose() or
  /// on-complete handler to force the final position past the throttle.
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
    final firstPing = st.lastSentAt == null;
    final grownEnough = watched - st.lastSent >= _minGrowth;
    final gapElapsed =
        st.lastSentAt == null || now.difference(st.lastSentAt!) >= _minResendGap;
    // The first ping goes out the moment ≥1s has been watched (that is the
    // `view` threshold server-side); every later ping keeps the throttle.
    final firstPingReady = firstPing && watched >= _firstPingThreshold;
    if (!flush && !firstPingReady && !(grownEnough && gapElapsed)) return;

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
  /// dispose(). The next play of the same challenge mints a fresh `sessionId`,
  /// so it counts as a new `view` server-side (backend dedupes a view per
  /// `sessionId`, not per user — replays are real re-engagement).
  void endWatchSession(String challengeId) => _watch.remove(challengeId);

  /// Fire when the user shares a challenge from anywhere in the app.
  ///
  /// `POST /challenges/{id}/share` bumps the lifetime `CreatorChallengeStats.shares`
  /// counter and the per-day `CreatorDailyAnalytics.shares` bucket the trend
  /// charts read (synchronous backend write — shares are a deliberate user
  /// action, not scroll telemetry, so they are not Redis-buffered like views /
  /// impressions). Raw count, no per-user dedup.
  ///
  /// `platform`, when given, is sent as a `platform` body field. The backend
  /// currently ignores it (per-platform `CreatorShareAnalytics.platformDistribution`
  /// is a tracked backend follow-up); keep passing it so the client is done
  /// the moment that lands. See
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

  /// One id per play session. The backend keys both `watchCount` and the
  /// one-view-per-session dedup (`SET NX eng:seen:{sessionId}`) on it, so it
  /// must stay stable for the life of a single play and change on the next.
  final String sessionId =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${(_seq++).toRadixString(36)}';

  static int _seq = 0;
}
