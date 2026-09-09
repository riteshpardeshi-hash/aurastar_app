import 'package:flutter/material.dart';

// Per-tier LevelReward catalog (fake brand names + made-up coupon codes,
// e.g. "Myntra — 10% Off — RISE10") was removed — it was entirely
// client-side placeholder data never backed by any API, real or otherwise.
// Actual earned rewards now come from GET /profile/rewards
// (RewardsService.fetchRewards) and are shown on RewardsScreen — they aren't
// organized by level tier, so there's no per-tier reward list to attach here
// anymore.
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
// of recomputing a tier from a locally-guessed level formula.
//
// When the backend sends no usable tier (null, or a value outside the enum),
// fall back to [auraTierForLevel] if the caller passes the account's [level],
// so the badge stays consistent with the level number shown next to it —
// rather than blindly showing "Rookie" beside "Level 516". Only when no level
// is available either does it settle on Rookie. See ADR 010.
AuraTier auraTierForName(String? tierName, {int? level}) {
  final needle = (tierName ?? '').toLowerCase();
  for (final t in auraTiers) {
    if (t.name.toLowerCase() == needle) return t;
  }
  return level != null ? auraTierForLevel(level) : auraTiers.first;
}
