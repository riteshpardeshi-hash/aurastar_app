import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/push_message_text.dart';

void main() {
  test('joins title and body with an em-dash', () {
    expect(
      foregroundPushText('Streak reminder', 'Play today to keep your streak'),
      'Streak reminder — Play today to keep your streak',
    );
  });

  test('title only', () {
    expect(foregroundPushText('Score ready', null), 'Score ready');
  });

  test('body only', () {
    expect(foregroundPushText(null, 'Your video was scored'), 'Your video was scored');
  });

  test('neither -> empty (data-only message, caller skips rendering)', () {
    expect(foregroundPushText(null, null), '');
    expect(foregroundPushText('', '   '), '');
  });

  test('trims surrounding whitespace', () {
    expect(foregroundPushText('  Hi  ', '  there  '), 'Hi — there');
  });
}
