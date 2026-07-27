/// Sums the `amount` of every transaction whose `createdAt` falls within
/// the current UTC calendar day.
///
/// Uses UTC rather than device-local time: the backend has no per-user
/// timezone concept anywhere in its schema (no timezone field on the user,
/// no mention anywhere in the API spec) and `createdAt` is always
/// ISO-8601 UTC, so UTC is the one day boundary that can't disagree with
/// whatever the backend itself uses elsewhere (e.g. streak resets) — using
/// the device's local midnight instead would silently shift which
/// transactions count as "today" by the device's UTC offset.
int sumTodayTransactions(
  List<Map<String, dynamic>> transactions, {
  DateTime? now,
}) {
  final nowUtc = (now ?? DateTime.now()).toUtc();
  final todayStart = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
  return transactions.fold<int>(0, (acc, tx) {
    final createdAt =
        DateTime.tryParse(tx['createdAt']?.toString() ?? '')?.toUtc();
    if (createdAt == null || createdAt.isBefore(todayStart)) return acc;
    return acc + ((tx['amount'] as num?)?.toInt() ?? 0);
  });
}
