/// Returns null if [uri] is a recognized deep link shape `_handleLink` in
/// main.dart knows how to route (`/challenge/{id}` or `/ref/{code}`).
/// Otherwise returns a short reason, used to show the user a visible error
/// instead of `_handleLink` silently doing nothing.
String? deepLinkValidationError(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length < 2) return 'unrecognized link';
  if (segments[0] == 'challenge') {
    return segments[1].isEmpty ? 'missing challenge id' : null;
  }
  if (segments[0] == 'ref') {
    return segments[1].trim().isEmpty ? 'missing referral code' : null;
  }
  return 'unrecognized link';
}
