import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';

// Home's Brand Videos shows one brand at a time, so 5 videos don't all come from one brand.
void main() {
  Map<String, dynamic> c(String id, String brand) => {'id': id, 'creatorId': brand};

  test('takes each brand newest first, round by round', () {
    final newestFirst = [c('a1', 'A'), c('a2', 'A'), c('a3', 'A'), c('b1', 'B'), c('c1', 'C'), c('b2', 'B')];
    expect(brandVideosMix(newestFirst).map((x) => x['id']), ['a1', 'b1', 'c1', 'a2', 'b2']);
  });

  test('fewer videos than slots: all of them', () {
    expect(brandVideosMix([c('a1', 'A'), c('a2', 'A')]).map((x) => x['id']), ['a1', 'a2']);
    expect(brandVideosMix([]), isEmpty);
  });
}
