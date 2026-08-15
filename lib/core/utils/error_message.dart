/// Converts a caught error into a message safe to show a user — never the
/// raw Dart/`http` exception text (e.g. `ClientException with
/// SocketException: Connection failed (OS Error: Network is unreachable...`),
/// which leaks internals and reads as a crash.
String humanizeError(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection failed') ||
      lower.contains('timeoutexception')) {
    // These exact exception types fire identically whether the device has
    // no connection at all, or the device is online and Aura's own backend
    // (a single non-redundant host) is briefly unreachable — there's no way
    // to tell those apart from the exception alone. The old copy here
    // ("No internet connection") asserted the first cause as fact, which
    // reads as a diagnosis the app can't actually make and is misleading
    // when it's really the second — the user's connection is fine.
    return "Couldn't reach Aura's servers. Please check your connection and try again.";
  }
  return raw.replaceFirst('Exception: ', '');
}
