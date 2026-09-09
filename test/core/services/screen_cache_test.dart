import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/screen_cache.dart';

void main() {
  setUp(ScreenCache.clear);

  test('read returns what was written', () {
    ScreenCache.write('k', [1, 2, 3]);
    expect(ScreenCache.read<List<int>>('k'), [1, 2, 3]);
  });

  test('a miss returns null', () {
    expect(ScreenCache.read<String>('nope'), isNull);
  });

  test('a type mismatch is a miss, not a throw', () {
    ScreenCache.write('k', 'a string');
    expect(ScreenCache.read<int>('k'), isNull);
  });

  test('write overwrites and refreshes recency', () {
    ScreenCache.write('k', 1);
    ScreenCache.write('k', 2);
    expect(ScreenCache.read<int>('k'), 2);
    expect(ScreenCache.entryCount, 1);
  });

  test('age reflects time since last write', () {
    expect(ScreenCache.age('k'), isNull);
    ScreenCache.write('k', 1);
    final age = ScreenCache.age('k');
    expect(age, isNotNull);
    expect(age!.inSeconds, lessThan(2));
  });

  test('invalidate drops a single key', () {
    ScreenCache.write('a', 1);
    ScreenCache.write('b', 2);
    ScreenCache.invalidate('a');
    expect(ScreenCache.read<int>('a'), isNull);
    expect(ScreenCache.read<int>('b'), 2);
  });

  test('invalidatePrefix drops every matching key', () {
    ScreenCache.write('creator.1', 1);
    ScreenCache.write('creator.2', 2);
    ScreenCache.write('profile.bundle', 3);
    ScreenCache.invalidatePrefix('creator.');
    expect(ScreenCache.read<int>('creator.1'), isNull);
    expect(ScreenCache.read<int>('creator.2'), isNull);
    expect(ScreenCache.read<int>('profile.bundle'), 3);
  });

  test('clear empties everything (used on logout)', () {
    ScreenCache.write('a', 1);
    ScreenCache.write('b', 2);
    ScreenCache.clear();
    expect(ScreenCache.entryCount, 0);
  });

  test('evicts the oldest entry once over the cap', () {
    for (var i = 0; i < 70; i++) {
      ScreenCache.write('k$i', i);
    }
    expect(ScreenCache.entryCount, lessThanOrEqualTo(64));
    // The first-written keys are gone; the most recent survive.
    expect(ScreenCache.read<int>('k0'), isNull);
    expect(ScreenCache.read<int>('k69'), 69);
  });

  test('re-writing a key keeps it from being evicted as stale', () {
    for (var i = 0; i < 40; i++) {
      ScreenCache.write('k$i', i);
    }
    ScreenCache.write('k0', 999); // touch the oldest
    for (var i = 40; i < 70; i++) {
      ScreenCache.write('k$i', i);
    }
    expect(ScreenCache.read<int>('k0'), 999,
        reason: 'k0 was re-written recently, so it should outlive k1..k5');
  });
}
