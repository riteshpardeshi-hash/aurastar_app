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
    return 'No internet connection. Please check your network and try again.';
  }
  return raw.replaceFirst('Exception: ', '');
}
