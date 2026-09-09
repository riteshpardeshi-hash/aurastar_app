import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/wallet_today_total.dart';

// Regression coverage: the wallet's "+X today" badge used to compute "today"
// from the device's LOCAL midnight, while createdAt timestamps are always
// ISO-8601 UTC and the backend has no per-user timezone concept anywhere in
// its schema. For an IST user (UTC+5:30 — the app hardcodes countryCode:
// '+91' throughout phone auth, so this is the primary audience), local
// midnight is 5.5 hours behind UTC midnight, so a transaction that landed in
// that 5.5-hour window was inconsistently counted depending on which
// boundary you asked. Fixed by always using UTC.
void main() {
  test('a transaction from earlier today (UTC) counts toward the total', () {
    final now = DateTime.utc(2026, 7, 27, 10, 0, 0);
    final total = sumTodayTransactions([
      {'amount': 50, 'createdAt': '2026-07-27T02:00:00.000Z'},
    ], now: now);
    expect(total, 50);
  });

  test('a transaction from yesterday (UTC) does not count', () {
    final now = DateTime.utc(2026, 7, 27, 10, 0, 0);
    final total = sumTodayTransactions([
      {'amount': 50, 'createdAt': '2026-07-26T23:59:59.000Z'},
    ], now: now);
    expect(total, 0);
  });

  test(
      'a transaction just after UTC midnight counts as today even though it '
      "is still 'yesterday' in IST (UTC+5:30) local time", () {
    // 00:30 UTC on 2026-07-27 is 06:00 IST on 2026-07-27 — same calendar day
    // either way, so this case alone wouldn't distinguish the two boundaries.
    // The real disagreement is the next test.
    final now = DateTime.utc(2026, 7, 27, 12, 0, 0);
    final total = sumTodayTransactions([
      {'amount': 30, 'createdAt': '2026-07-27T00:30:00.000Z'},
    ], now: now);
    expect(total, 30);
  });

  test('a transaction at 20:00 UTC on the previous day is excluded, even '
      "though it is already 'today' (01:30) in IST local time — UTC is the "
      'one boundary that matches createdAt\'s own timezone', () {
    // 2026-07-26T20:00:00Z is 2026-07-27 01:30 IST — under a local-midnight
    // rule for an IST device this would wrongly count as "today".
    final now = DateTime.utc(2026, 7, 27, 10, 0, 0);
    final total = sumTodayTransactions([
      {'amount': 999, 'createdAt': '2026-07-26T20:00:00.000Z'},
    ], now: now);
    expect(total, 0,
        reason: 'must use the UTC calendar day, not any device-local one');
  });

  test('missing or unparsable createdAt is skipped, not a crash', () {
    final now = DateTime.utc(2026, 7, 27, 10, 0, 0);
    final total = sumTodayTransactions([
      {'amount': 10},
      {'amount': 20, 'createdAt': 'not-a-date'},
    ], now: now);
    expect(total, 0);
  });
}
