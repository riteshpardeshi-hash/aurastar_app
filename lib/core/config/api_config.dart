/// Backend API base URL.
///
/// Every shipped build talks to [production] and nothing else. There is no
/// in-app way to change it — the old Settings → Debug → API server picker was
/// removed (mobile ADR 036), and a URL an old build saved under
/// `api_base_url_override` is ignored.
///
/// Developers can still point a local build elsewhere at compile time (never
/// pass this for a build that goes to users):
///   flutter run --dart-define=API_BASE_URL=http://localhost:3000/api/v1
///
/// Local backend (`pnpm dev`, port 3000):
///   • Android emulator .............. http://10.0.2.2:3000/api/v1
///   • iOS simulator / desktop ....... http://localhost:3000/api/v1
///   • Physical device ............... `adb reverse tcp:3000 tcp:3000`, then
///       http://localhost:3000/api/v1
class ApiConfig {
  ApiConfig._();

  static const production = 'http://144.91.79.237:3786/api/v1';

  static const _compileTimeOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// The effective base URL: [production], unless a developer build passed
  /// `--dart-define=API_BASE_URL`.
  static String get baseUrl =>
      _compileTimeOverride.isNotEmpty ? _compileTimeOverride : production;

  // S3/CDN base URL — prepended to videoKey fields from home endpoints.
  // Set this to the bucket URL once provided by the backend team.
  static const mediaBaseUrl = '';
}
