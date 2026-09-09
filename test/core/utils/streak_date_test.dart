import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/streak_date.dart';

// Regression coverage: dashboard.dart used to default lastStreakDate to
// "today" whenever currentStreak > 0, instead of reading the real
// lastActivityDate GET /profile/streak returns. That made the broken/at-risk
// streak banner states — and the at-risk streak snackbar with its "Play"
// action — structurally unreachable: lastStreakDate always compared equal
// to today's date, so the "haven't played today" checks could never be true.
void main() {
  test('reads the real lastActivityDate from the streak map', () {
    expect(
      deriveLastStreakDate({'currentStreak': 3, 'lastActivityDate': '2026-07-25'}),
      '2026-07-25',
    );
  });

  test('does not default to "today" just because a streak is active', () {
    // This is the crux of the bug: an active streak (currentStreak > 0)
    // whose last real activity was NOT today must not report today's date.
    final result = deriveLastStreakDate({
      'currentStreak': 5,
      'lastActivityDate': '2020-01-01',
    });
    expect(result, isNot(equals(_todayStr())));
    expect(result, '2020-01-01');
  });

  test('a null streak (no activity yet) yields an empty string', () {
    expect(deriveLastStreakDate(null), '');
  });

  test('a missing lastActivityDate field yields an empty string, not a crash', () {
    expect(deriveLastStreakDate({'currentStreak': 1}), '');
  });
}

String _todayStr() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
