import 'package:shared_preferences/shared_preferences.dart';

/// Backend API base URL.
///
/// Resolution order (first non-empty wins):
///   1. `--dart-define=API_BASE_URL=...` — compile-time override, e.g.
///        flutter run --dart-define=API_BASE_URL=http://192.168.1.5:3000/api/v1
///   2. a runtime override saved from **Settings → Debug → API server**
///      (persisted in SharedPreferences; loaded once by [load] in `main()`).
///   3. [production].
///
/// Local backend (`pnpm dev`, port 3000):
///   • Android emulator .............. http://10.0.2.2:3000/api/v1
///   • iOS simulator / desktop ....... http://localhost:3000/api/v1
///   • Physical device (same wifi) ... `http://<machine-LAN-IP>:3000/api/v1`
///       …or run `adb reverse tcp:3000 tcp:3000` once, then use
///       http://localhost:3000/api/v1 on the device too.
class ApiConfig {
  ApiConfig._();

  static const production = 'http://144.91.79.237:3786/api/v1';

  /// Handy presets for the Settings → Debug picker.
  static const localAndroidEmulator = 'http://10.0.2.2:3000/api/v1';
  static const localLoopback = 'http://localhost:3000/api/v1';

  static const _prefsKey = 'api_base_url_override';
  static const _compileTimeOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String _runtimeOverride = '';

  /// The effective base URL. Safe to read before [load] — falls back to the
  /// compile-time value or [production] until the saved override loads.
  static String get baseUrl {
    if (_compileTimeOverride.isNotEmpty) return _compileTimeOverride;
    if (_runtimeOverride.isNotEmpty) return _runtimeOverride;
    return production;
  }

  /// True when a `--dart-define` fixed the URL — the in-app picker can't
  /// override it and should say so.
  static bool get isCompileTimePinned => _compileTimeOverride.isNotEmpty;

  /// The saved runtime override, or '' if none.
  static String get runtimeOverride => _runtimeOverride;

  /// Call once early in `main()`.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _runtimeOverride = prefs.getString(_prefsKey) ?? '';
    } catch (_) {
      _runtimeOverride = '';
    }
  }

  /// Persist a runtime override (pass '' / null to clear and fall back to
  /// [production]). Takes effect immediately for new requests; existing
  /// sessions should re-login since tokens are per-backend.
  static Future<void> setRuntimeOverride(String? url) async {
    _runtimeOverride = (url ?? '').trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_runtimeOverride.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, _runtimeOverride);
      }
    } catch (_) {
      // best-effort — the in-memory value still applies for this session
    }
  }

  // S3/CDN base URL — prepended to videoKey fields from home endpoints.
  // Set this to the bucket URL once provided by the backend team.
  static const mediaBaseUrl = '';
}
