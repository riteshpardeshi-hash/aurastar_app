import 'package:video_player/video_player.dart';

/// A small, bounded cache of already-initialized [VideoPlayerController]s,
/// keyed by URL. List screens (home feed, a creator's video grid, ...) call
/// [prewarm] for the handful of videos a user is most likely to open next;
/// the screens that actually play them call [take] first and only build
/// their own controller if nothing was already warmed up in the background.
///
/// Deliberately app-wide and static rather than scoped to one screen: the
/// whole point is that the *list* screen (which knows what's about to be
/// tapped) and the *player* screen (which knows how to play it) are
/// different widgets:
///
///   Home feed screen ── prewarm(url) ──▶ [cache] ◀── take(url) ── ChallengeDetail
///   Creator video grid ── prewarm(url) ─▶ [cache] ◀── take(url) ── VideoPlayerWidget
class VideoPrewarmCache {
  VideoPrewarmCache._();

  // Small cap — each entry is a live, buffering VideoPlayerController, not
  // just a URL string, so this trades a bounded amount of memory/network
  // for perceived load time. Not meant to hold more than "the few videos
  // visible/likely-next" at once; callers should only prewarm a handful of
  // items (e.g. the first 2-3 in a list), not an entire page.
  static const _maxReady = 3;

  static final Map<String, VideoPlayerController> _ready = {};
  static final Map<String, Future<void>> _inFlight = {};

  /// Fire-and-forget: builds and initializes a controller for [url] in the
  /// background if one isn't already ready or in flight for it. Safe to
  /// call speculatively and more than once for the same URL.
  ///
  /// [mixWithOthers] must match whatever the eventual consumer needs it to
  /// be — it's applied once, during initialize(), and can't be changed
  /// later by whoever calls [take]. Get this wrong and the controller is
  /// still usable, just with the wrong audio-focus behavior for its actual
  /// destination screen.
  static void prewarm(String url, {bool mixWithOthers = false}) {
    if (url.isEmpty ||
        _ready.containsKey(url) ||
        _inFlight.containsKey(url)) {
      return;
    }
    _inFlight[url] = _build(url, mixWithOthers);
  }

  static Future<void> _build(String url, bool mixWithOthers) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: mixWithOthers),
    );
    try {
      await controller.initialize();
    } catch (_) {
      controller.dispose();
      _inFlight.remove(url);
      return;
    }
    _inFlight.remove(url);
    // A screen may have already been popped, or the entry evicted for
    // space, by the time this resolves — nothing to do with an orphaned
    // ready controller other than release it.
    _ready[url] = controller;
    _evictOverflow();
  }

  static void _evictOverflow() {
    // Map preserves insertion order, so the first key is the oldest entry
    // — a simple FIFO eviction without tracking access times separately.
    while (_ready.length > _maxReady) {
      _ready.remove(_ready.keys.first)?.dispose();
    }
  }

  /// Takes ownership of an already-initialized controller for [url] if one
  /// is ready, removing it from the cache — the caller now owns disposing
  /// it. Returns null (callers should build their own as usual) if nothing
  /// was prewarmed for this URL, or the prewarm hasn't finished yet.
  static VideoPlayerController? take(String url) => _ready.remove(url);
}
