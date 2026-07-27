import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/creator_challenges_service.dart';

// Regression coverage: pickString (used across notifications_service.dart
// and several creator screens to read fields from Swagger-undocumented,
// best-guess responses) used to delegate to pickField, which only checks
// "present and non-null" — so a present-but-empty string candidate (e.g. a
// notification with body: '') was returned as-is, never falling through to
// a later, populated candidate like title. A notification with a real title
// but an empty body rendered as a blank row.
void main() {
  group('pickString', () {
    test('falls through a present-but-empty candidate to a later populated one', () {
      expect(
        pickString({'body': '', 'title': 'Real title'}, ['body', 'title']),
        'Real title',
      );
    });

    test('returns the first non-empty candidate found', () {
      expect(
        pickString({'message': 'Hi', 'body': '', 'title': 'Ignored'},
            ['message', 'body', 'text', 'title']),
        'Hi',
      );
    });

    test('falls back when every candidate is missing or empty', () {
      expect(
        pickString({'body': ''}, ['message', 'body', 'text', 'title'],
            fallback: 'default'),
        'default',
      );
    });

    test('a missing map key is skipped same as an empty one', () {
      expect(
        pickString({'title': 'Only title'}, ['message', 'body', 'title']),
        'Only title',
      );
    });
  });
}
