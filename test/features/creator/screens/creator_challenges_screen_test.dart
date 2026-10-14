import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/creator/screens/creator_challenges_screen.dart';

void main() {
  // Regression: /creator/challenges/filters returns statuses as
  // {value, label} objects; toString() put "{value: draft, label: draft}" on
  // the filter chips.
  test('status filter objects are reduced to upper-case status strings', () {
    expect(
      parseStatusOptions([
        {'value': 'draft', 'label': 'draft'},
        {'value': 'pending_review', 'label': 'pending review'},
        'LIVE',
      ]),
      ['DRAFT', 'PENDING_REVIEW', 'LIVE'],
    );
  });
}
