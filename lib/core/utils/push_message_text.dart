/// Builds the one-line text shown in the in-app snackbar for a push that
/// arrives while the app is foregrounded (the OS renders nothing of its own
/// in that case). Mirrors what the OS tray notification shows otherwise:
/// title and body joined, either one alone if it's the only part present,
/// and empty when neither is — a data-only message the caller then skips.
String foregroundPushText(String? title, String? body) {
  final t = title?.trim() ?? '';
  final b = body?.trim() ?? '';
  if (t.isEmpty) return b;
  if (b.isEmpty) return t;
  return '$t — $b';
}
