import 'package:flutter/material.dart';

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
  AuraTier(minLevel: 1,  name: 'Rookie', unlock: 'Generic coupons',          color: Color(0xFF9E9E9E)),
  AuraTier(minLevel: 5,  name: 'Rising', unlock: 'Fashion drops',            color: Color(0xFF4CAF50)),
  AuraTier(minLevel: 10, name: 'Viral',  unlock: 'Food & beverage perks',    color: Color(0xFF2196F3)),
  AuraTier(minLevel: 20, name: 'Elite',  unlock: 'Early-access coupons',     color: Color(0xFFFF9800)),
  AuraTier(minLevel: 30, name: 'Sigma',  unlock: 'Invite-only drops',        color: Color(0xFFE91E63)),
  AuraTier(minLevel: 50, name: 'Divine', unlock: 'Limited collabs/freebies', color: Color(0xFFFFD700)),
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
