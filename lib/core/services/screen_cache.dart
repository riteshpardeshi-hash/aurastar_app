import 'package:flutter/foundation.dart';

/// Process-lifetime, in-memory cache for screen-level payloads.
///
/// Top-level screens (Search, Leaderboard, Profile, …) are pushed fresh on
/// every bottom-nav tap and re-fetch in `initState`, so revisiting a tab
/// always flashed a full-screen spinner before its content came back. With
/// this, a screen writes its assembled data here on a successful load and
/// reads it back synchronously in `initState`: the second visit onward
/// renders the last-known content immediately and refreshes in the
/// background (stale-while-revalidate).
///
/// Deliberately **not** persisted — a cold start still loads fresh, which
/// avoids ever showing hours-old data as current and needing per-payload
/// serialization. Cleared wholesale on logout (see [ApiClient.clearSession]).
class ScreenCache {
  ScreenCache._();

  /// Caps memory: screens key by things like a creator id, so the set of
  /// keys is unbounded over a long session. Oldest-written entries are
  /// evicted first once this is exceeded.
  static const _maxEntries = 64;

  static final Map<String, _Entry> _entries = {};

  /// The cached value for [key], or null if nothing is cached (or the stored
  /// type doesn't match [T] — treated as a miss rather than throwing).
  static T? read<T>(String key) {
    final e = _entries[key];
    if (e == null) return null;
    final v = e.value;
    return v is T ? v : null;
  }

  /// How long ago [key] was last written, or null if it isn't cached. Use it
  /// to skip a redundant background refresh right after one already ran.
  static Duration? age(String key) {
    final e = _entries[key];
    return e == null ? null : DateTime.now().difference(e.writtenAt);
  }

  static void write<T>(String key, T value) {
    _entries.remove(key); // re-insert so iteration order tracks recency
    _entries[key] = _Entry(value, DateTime.now());
    if (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static void invalidate(String key) => _entries.remove(key);

  /// Drops every entry whose key starts with [prefix] — e.g. `'creator.'` to
  /// clear all cached creator pages at once.
  static void invalidatePrefix(String prefix) =>
      _entries.removeWhere((k, _) => k.startsWith(prefix));

  static void clear() => _entries.clear();

  @visibleForTesting
  static int get entryCount => _entries.length;
}

class _Entry {
  final Object? value;
  final DateTime writtenAt;
  _Entry(this.value, this.writtenAt);
}
