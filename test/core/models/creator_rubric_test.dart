import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/models/creator_rubric.dart';

// The editor's rules must match the backend's (utilities/rubric.js#applyRubricEdits,
// ADR 137) so the creator sees the problem before saving, not a 400 after.
void main() {
  const rules = RubricRules();
  List<RubricCategory> six() => [
        for (var i = 0; i < 6; i++) RubricCategory(name: 'Skill $i', maxPoints: i == 0 ? 15 : 14),
      ];

  test('a 6-category list totalling 85 is valid', () {
    expect(rules.validate(six()), isNull);
  });

  test('points must total exactly 85, with a message saying how far off', () {
    final under = six()..[0] = const RubricCategory(name: 'Skill 0', maxPoints: 10);
    expect(rules.validate(under), contains('Add 5 more points'));
    final over = six()..[0] = const RubricCategory(name: 'Skill 0', maxPoints: 16);
    expect(rules.validate(over), contains('Remove 1 point'));
  });

  test('rejects too few or too many categories', () {
    expect(rules.validate(six().sublist(0, 5)), contains('6 to 8'));
    expect(
      rules.validate([...six(), ...six().sublist(0, 3)]),
      contains('6 to 8'),
    );
  });

  test('rejects blank and duplicate names and out-of-range points', () {
    final blank = six()..[2] = const RubricCategory(name: '  ', maxPoints: 14);
    expect(rules.validate(blank), contains('needs a name'));
    final dup = six()..[2] = const RubricCategory(name: 'skill 1', maxPoints: 14);
    expect(rules.validate(dup), contains('different name'));
    final big = six()..[0] = const RubricCategory(name: 'Skill 0', maxPoints: 31);
    expect(rules.validate(big), contains('between 5 and 30'));
  });

  test('blank categories share the 85 points evenly', () {
    for (final n in [6, 7, 8]) {
      final blank = rules.blankCategories(n);
      expect(blank, hasLength(n));
      expect(blank.fold<int>(0, (s, c) => s + c.maxPoints), 85);
    }
  });

  test('parses the backend view and serialises edits back', () {
    final rubric = CreatorRubric.fromJson({
      'hasRubric': true,
      'editable': true,
      'source': 'ai',
      'fixedCategories': [
        {'key': 'reference_similarity', 'name': 'Reference', 'maxPoints': 5},
        {'key': 'framing_visibility', 'name': 'Framing', 'maxPoints': 5},
      ],
      'categories': [
        {'key': 'landing', 'name': 'Landing', 'description': 'Feet together', 'maxPoints': 20},
      ],
      'bonusRules': [
        {'description': 'Flair', 'maxPoints': 5},
      ],
      'rules': {'categoryPointsTotal': 85},
    });
    expect(rubric.hasRubric, isTrue);
    expect(rubric.fixedPoints, 10);
    expect(rubric.bonusPoints, 5);
    expect(rubric.categories.single.toJson(),
        {'key': 'landing', 'name': 'Landing', 'description': 'Feet together', 'maxPoints': 20});
    expect(const RubricCategory(name: ' New ', description: ' ', maxPoints: 5).toJson(),
        {'name': 'New', 'maxPoints': 5});
  });

  // Every set of criteria is scored out of exactly 100 (10 fixed + 85 yours + 5 bonus);
  // the app checks the same total the backend enforces (ADR 137).
  group('the 100-point total', () {
    CreatorRubric generated({int bonus = 5, int? reported, List<RubricCategory>? cats}) => CreatorRubric(
          hasRubric: true,
          editable: true,
          source: 'ai',
          referenceDescription: null,
          fixedCategories: const [
            RubricCategory(name: 'Reference', maxPoints: 5),
            RubricCategory(name: 'Framing', maxPoints: 5),
          ],
          categories: cats ?? six(),
          bonusRules: [if (bonus > 0) RubricBonusRule(description: 'Flair', maxPoints: bonus)],
          rules: const RubricRules(),
          reportedTotal: reported,
        );

    test('generated criteria total 100 and add up', () {
      final rubric = generated();
      expect(rubric.totalPoints, 100);
      expect(rubric.addsUp, isTrue);
    });

    test('the backend-reported total wins over the local sum', () {
      expect(generated(reported: 105).totalPoints, 105);
      expect(generated(reported: 105).addsUp, isFalse);
    });

    test('older criteria that total 105 do not add up', () {
      final old = generated(cats: [const RubricCategory(name: 'Everything', maxPoints: 90)]);
      expect(old.totalPoints, 100 - 85 + 90);
      expect(old.addsUp, isFalse);
    });

    test('criteria not generated yet count as fine (nothing to check)', () {
      const empty = CreatorRubric(
        hasRubric: false,
        editable: true,
        source: null,
        referenceDescription: null,
        fixedCategories: [],
        categories: [],
        bonusRules: [],
        rules: RubricRules(),
      );
      expect(empty.addsUp, isTrue);
    });

    test('an edited list is checked against the full 100, counting fixed and bonus points', () {
      final rubric = generated();
      expect(rubric.totalWith(six()), 100);
      expect(rubric.validateEdits(six()), isNull);

      final over = six()..[0] = const RubricCategory(name: 'Skill 0', maxPoints: 16);
      expect(rubric.totalWith(over), 101);
      expect(rubric.validateEdits(over), contains('Remove 1 point'));
    });

    test('the bonus is always counted at the full 5 (the backend tops it up)', () {
      expect(generated(bonus: 2).totalWith(six()), 100);
    });

    test('the rules default to the backend values when the response omits them', () {
      const rules = RubricRules();
      expect(rules.fixedPoints + rules.categoryPointsTotal + rules.bonusMaxPoints, rules.totalPoints);
      expect(rules.totalPoints, 100);
    });
  });
}
