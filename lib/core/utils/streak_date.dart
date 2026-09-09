/// Reads the real last-activity date `GET /profile/streak` returns
/// (`lastActivityDate`, e.g. "2026-06-25"), instead of assuming "today"
/// whenever a streak is active. That assumption made every
/// non-"just-qualified" streak state (broken, at-risk) structurally
/// unreachable regardless of real activity, since it always compared equal
/// to today's date.
String deriveLastStreakDate(Map<String, dynamic>? streak) =>
    (streak?['lastActivityDate'] as String?) ?? '';
