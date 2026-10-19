/// A creator challenge's scoring criteria — how every player's attempt is
/// scored. Mirrors `GET /creator/challenges/{id}/rubric` (backend ADR 137).
///
/// Every challenge is scored on two fixed categories (reference similarity,
/// framing) plus 6–8 challenge-specific ones the creator generates with AI,
/// regenerates and edits before submitting. The challenge-specific points must
/// add up to exactly [RubricRules.categoryPointsTotal] (85): with the fixed 10
/// and up to 5 bonus points that makes a score out of 100.
class CreatorRubric {
  final bool hasRubric;
  final bool editable;

  /// 'ai' (generated, untouched) or 'manual' (written / edited by the creator).
  final String? source;
  final String? referenceDescription;
  final List<RubricCategory> fixedCategories;
  final List<RubricCategory> categories;
  final List<RubricBonusRule> bonusRules;
  final RubricRules rules;

  /// The highest score these criteria allow, as the backend computed it.
  /// Always 100 for criteria built since ADR 137; older ones may differ.
  final int? reportedTotal;

  const CreatorRubric({
    required this.hasRubric,
    required this.editable,
    required this.source,
    required this.referenceDescription,
    required this.fixedCategories,
    required this.categories,
    required this.bonusRules,
    required this.rules,
    this.reportedTotal,
  });

  factory CreatorRubric.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) =>
        ((json[key] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
    return CreatorRubric(
      hasRubric: json['hasRubric'] == true,
      editable: json['editable'] == true,
      source: json['source'] as String?,
      referenceDescription: json['referenceDescription'] as String?,
      fixedCategories: list('fixedCategories').map(RubricCategory.fromJson).toList(),
      categories: list('categories').map(RubricCategory.fromJson).toList(),
      bonusRules: list('bonusRules').map(RubricBonusRule.fromJson).toList(),
      rules: RubricRules.fromJson(json['rules'] as Map<String, dynamic>? ?? const {}),
      reportedTotal: (json['totalPoints'] as num?)?.toInt(),
    );
  }

  int get fixedPoints => fixedCategories.fold(0, (s, c) => s + c.maxPoints);
  int get bonusPoints => bonusRules.fold(0, (s, b) => s + b.maxPoints);
  int get categoryPoints => categories.fold(0, (s, c) => s + c.maxPoints);

  /// The highest score these criteria allow: fixed + challenge categories + bonus.
  int get totalPoints => reportedTotal ?? (fixedPoints + categoryPoints + bonusPoints);

  /// False for older criteria whose points don't add up to 100; they must be
  /// edited or regenerated before the challenge can be submitted.
  bool get addsUp => !hasRubric || totalPoints == rules.totalPoints;

  /// What an edited category list would total, counting the fixed categories
  /// and the bonus the backend always fills up to [RubricRules.bonusMaxPoints].
  int totalWith(List<RubricCategory> edited) =>
      rules.fixedPoints + edited.fold<int>(0, (s, c) => s + c.maxPoints) + rules.bonusMaxPoints;

  /// The first problem with [edited], or null when it can be saved: the
  /// per-category rules, then the grand total of exactly 100.
  String? validateEdits(List<RubricCategory> edited) {
    final problem = rules.validate(edited);
    if (problem != null) return problem;
    final total = totalWith(edited);
    if (total != rules.totalPoints) {
      return 'These criteria would score out of $total instead of ${rules.totalPoints}.';
    }
    return null;
  }
}

class RubricCategory {
  /// Null for a category the creator just added.
  final String? key;
  final String name;
  final String? description;
  final int maxPoints;

  const RubricCategory({this.key, required this.name, this.description, required this.maxPoints});

  factory RubricCategory.fromJson(Map<String, dynamic> json) => RubricCategory(
        key: json['key'] as String?,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        maxPoints: (json['maxPoints'] as num?)?.toInt() ?? 0,
      );

  RubricCategory copyWith({String? name, String? description, int? maxPoints}) => RubricCategory(
        key: key,
        name: name ?? this.name,
        description: description ?? this.description,
        maxPoints: maxPoints ?? this.maxPoints,
      );

  /// The body `PUT /creator/challenges/{id}/rubric` expects per category.
  Map<String, dynamic> toJson() => {
        if (key != null) 'key': key,
        'name': name.trim(),
        if ((description ?? '').trim().isNotEmpty) 'description': description!.trim(),
        'maxPoints': maxPoints,
      };
}

class RubricBonusRule {
  final String description;
  final int maxPoints;

  const RubricBonusRule({required this.description, required this.maxPoints});

  factory RubricBonusRule.fromJson(Map<String, dynamic> json) => RubricBonusRule(
        description: json['description'] as String? ?? '',
        maxPoints: (json['maxPoints'] as num?)?.toInt() ?? 0,
      );
}

/// The limits the backend enforces on an edited category list. Defaults match
/// the backend's so the editor still works if `rules` is missing.
class RubricRules {
  final int minCategories;
  final int maxCategories;
  final int minPoints;
  final int maxPoints;
  final int categoryPointsTotal;
  final int fixedPoints;
  final int bonusMaxPoints;
  final int totalPoints;
  final int nameMaxLength;
  final int descriptionMaxLength;

  const RubricRules({
    this.minCategories = 6,
    this.maxCategories = 8,
    this.minPoints = 5,
    this.maxPoints = 30,
    this.categoryPointsTotal = 85,
    this.fixedPoints = 10,
    this.bonusMaxPoints = 5,
    this.totalPoints = 100,
    this.nameMaxLength = 60,
    this.descriptionMaxLength = 200,
  });

  factory RubricRules.fromJson(Map<String, dynamic> json) {
    int read(String key, int fallback) => (json[key] as num?)?.toInt() ?? fallback;
    const d = RubricRules();
    return RubricRules(
      minCategories: read('minCategories', d.minCategories),
      maxCategories: read('maxCategories', d.maxCategories),
      minPoints: read('minPoints', d.minPoints),
      maxPoints: read('maxPoints', d.maxPoints),
      categoryPointsTotal: read('categoryPointsTotal', d.categoryPointsTotal),
      bonusMaxPoints: read('bonusMaxPoints', d.bonusMaxPoints),
      totalPoints: read('totalPoints', d.totalPoints),
      nameMaxLength: read('nameMaxLength', d.nameMaxLength),
      descriptionMaxLength: read('descriptionMaxLength', d.descriptionMaxLength),
    );
  }

  /// First problem with [categories], in words the creator can act on, or
  /// null when the list can be saved. Same rules as the backend.
  String? validate(List<RubricCategory> categories) {
    if (categories.length < minCategories || categories.length > maxCategories) {
      return 'Keep $minCategories to $maxCategories categories.';
    }
    final seen = <String>{};
    for (final c in categories) {
      final name = c.name.trim();
      if (name.isEmpty) return 'Every category needs a name.';
      if (!seen.add(name.toLowerCase())) return 'Each category needs a different name.';
      if (c.maxPoints < minPoints || c.maxPoints > maxPoints) {
        return '"$name" needs between $minPoints and $maxPoints points.';
      }
    }
    final total = categories.fold<int>(0, (s, c) => s + c.maxPoints);
    if (total != categoryPointsTotal) {
      final diff = categoryPointsTotal - total;
      return diff > 0
          ? 'Add $diff more point${diff == 1 ? '' : 's'} (total must be $categoryPointsTotal).'
          : 'Remove ${-diff} point${diff == -1 ? '' : 's'} (total must be $categoryPointsTotal).';
    }
    return null;
  }

  /// [count] blank categories sharing the points as evenly as possible — the
  /// starting point when the creator writes criteria by hand.
  List<RubricCategory> blankCategories(int count) {
    final base = categoryPointsTotal ~/ count;
    var extra = categoryPointsTotal - base * count;
    return List.generate(
      count,
      (_) => RubricCategory(name: '', maxPoints: base + (extra-- > 0 ? 1 : 0)),
    );
  }
}
