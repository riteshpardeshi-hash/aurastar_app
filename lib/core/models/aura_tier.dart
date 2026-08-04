import 'package:flutter/material.dart';

// Per-tier LevelReward catalog (fake brand names + made-up coupon codes,
// e.g. "Myntra — 10% Off — RISE10") was removed — it was entirely
// client-side placeholder data never backed by any API, real or otherwise.
// Actual earned rewards now come from GET /profile/rewards
// (AuthApiService.fetchRewards) and are shown in MyAccountScreen's rewards
// section — they aren't organized by level tier, so there's no per-tier
// reward list to attach here anymore.
class AuraTier {
  final int minLevel;
  final String name;
  final String unlock;
  final Color color;
  const AuraTier({
    required this.minLevel,
    required this.name,
    required this.unlock,
    required this.color,
  });
}

const List<AuraTier> auraTiers = [
  AuraTier(
    minLevel: 1,
    name: 'Rookie',
    unlock: 'Generic coupons',
    color: Color(0xFF9E9E9E),
  ),
  AuraTier(
    minLevel: 5,
    name: 'Rising',
    unlock: 'Fashion drops',
    color: Color(0xFF4CAF50),
  ),
  AuraTier(
    minLevel: 10,
    name: 'Viral',
    unlock: 'Food & beverage perks',
    color: Color(0xFF2196F3),
  ),
  AuraTier(
    minLevel: 20,
    name: 'Elite',
    unlock: 'Early-access coupons',
    color: Color(0xFFFF9800),
  ),
  AuraTier(
    minLevel: 30,
    name: 'Sigma',
    unlock: 'Invite-only drops',
    color: Color(0xFFE91E63),
  ),
];

AuraTier auraTierForLevel(int level) {
  AuraTier result = auraTiers.first;
  for (final t in auraTiers) {
    if (level >= t.minLevel) result = t;
  }
  return result;
}

AuraTier? nextAuraTier(int level) {
  for (final t in auraTiers) {
    if (t.minLevel > level) return t;
  }
  return null;
}

// Maps the backend's authoritative `tier` string (GET /profile's `tier`
// field: rookie/rising/viral/elite/sigma) to the matching AuraTier, instead
// of recomputing a tier from a locally-guessed level formula. Falls back to
// Rookie for an unrecognized or missing value.
AuraTier auraTierForName(String? tierName) {
  return auraTiers.firstWhere(
    (t) => t.name.toLowerCase() == (tierName ?? '').toLowerCase(),
    orElse: () => auraTiers.first,
  );
}
