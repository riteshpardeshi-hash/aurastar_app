/// Converts a caught error into a message safe to show a user — never the
/// raw Dart/`http` exception text (e.g. `ClientException with
/// SocketException: Connection failed (OS Error: Network is unreachable...`),
/// which leaks internals and reads as a crash.
/// True when [error] is one of the low-level exception types that fire
/// identically whether the device has no connection at all, or the device
/// is online and Aura's own backend (a single non-redundant host) is
/// briefly unreachable — there's no way to tell those two apart from the
/// exception alone, so both [humanizeError] and callers that pick an icon
/// (e.g. Dashboard's error screen) should treat them as "connectivity-ish"
/// rather than a backend-reported error.
bool isNetworkError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection failed') ||
      lower.contains('timeoutexception');
}

String humanizeError(Object error) {
  if (isNetworkError(error)) {
    // The old copy here ("No internet connection") asserted the first cause
    // as fact, which reads as a diagnosis the app can't actually make and
    // is misleading when it's really the second — the user's connection is
    // fine.
    return "Couldn't reach Aura's servers. Please check your connection and try again.";
  }
  return error.toString().replaceFirst('Exception: ', '');
}
