import 'package:flutter/material.dart';

class LevelReward {
  final String brand;
  final String title;
  final String code;
  final String description;
  final IconData icon;
  const LevelReward({
    required this.brand,
    required this.title,
    required this.code,
    required this.description,
    required this.icon,
  });
}

class AuraTier {
  final int minLevel;
  final String name;
  final String unlock;
  final Color color;
  final List<LevelReward> rewards;
  const AuraTier({
    required this.minLevel,
    required this.name,
    required this.unlock,
    required this.color,
    this.rewards = const [],
  });
}

const List<AuraTier> auraTiers = [
  AuraTier(
    minLevel: 1,
    name: 'Rookie',
    unlock: 'Generic coupons',
    color: Color(0xFF9E9E9E),
    rewards: [
      LevelReward(
        brand: 'AuraShop',
        title: '5% Off',
        code: 'ROOKIE5',
        description: 'On any purchase above ₹299',
        icon: Icons.local_offer_rounded,
      ),
    ],
  ),
  AuraTier(
    minLevel: 5,
    name: 'Rising',
    unlock: 'Fashion drops',
    color: Color(0xFF4CAF50),
    rewards: [
      LevelReward(
        brand: 'Myntra',
        title: '10% Off',
        code: 'RISE10',
        description: 'On fashion orders above ₹499',
        icon: Icons.checkroom_rounded,
      ),
      LevelReward(
        brand: 'Zomato',
        title: 'Free Delivery',
        code: 'RISEUP',
        description: 'On your next 3 orders',
        icon: Icons.delivery_dining_rounded,
      ),
    ],
  ),
  AuraTier(
    minLevel: 10,
    name: 'Viral',
    unlock: 'Food & beverage perks',
    color: Color(0xFF2196F3),
    rewards: [
      LevelReward(
        brand: 'Swiggy',
        title: '15% Off',
        code: 'VIRAL15',
        description: 'On food orders above ₹399',
        icon: Icons.fastfood_rounded,
      ),
      LevelReward(
        brand: 'Starbucks',
        title: 'Buy 1 Get 1',
        code: 'VIRAL2X',
        description: 'On any beverage, valid weekdays',
        icon: Icons.local_cafe_rounded,
      ),
    ],
  ),
  AuraTier(
    minLevel: 20,
    name: 'Elite',
    unlock: 'Early-access coupons',
    color: Color(0xFFFF9800),
    rewards: [
      LevelReward(
        brand: 'Nykaa',
        title: '20% Off',
        code: 'ELITE20',
        description: 'On beauty & skincare above ₹699',
        icon: Icons.face_retouching_natural_rounded,
      ),
      LevelReward(
        brand: 'Nike',
        title: 'Early Sale Access',
        code: 'ELITEPRE',
        description: '24-hour early access to seasonal sale',
        icon: Icons.timer_rounded,
      ),
      LevelReward(
        brand: 'BookMyShow',
        title: '₹150 Off',
        code: 'ELITESHOW',
        description: 'On movie tickets above ₹300',
        icon: Icons.theaters_rounded,
      ),
    ],
  ),
  AuraTier(
    minLevel: 30,
    name: 'Sigma',
    unlock: 'Invite-only drops',
    color: Color(0xFFE91E63),
    rewards: [
      LevelReward(
        brand: 'H&M',
        title: 'Exclusive Drop',
        code: 'SIGMA30',
        description: 'Invite-only limited collection access',
        icon: Icons.diamond_rounded,
      ),
      LevelReward(
        brand: 'boAt',
        title: 'Free Merch',
        code: 'SIGMAFREE',
        description: 'Free branded tote bag on next order',
        icon: Icons.card_giftcard_rounded,
      ),
      LevelReward(
        brand: 'Puma',
        title: '25% Off',
        code: 'SIGMARUN',
        description: 'On footwear & sportswear above ₹1999',
        icon: Icons.sports_rounded,
      ),
    ],
  ),
  AuraTier(
    minLevel: 50,
    name: 'Divine',
    unlock: 'Limited collabs/freebies',
    color: Color(0xFFFFD700),
    rewards: [
      LevelReward(
        brand: 'Aura x Collab',
        title: 'Limited Edition Kit',
        code: 'DIVINE50',
        description: 'Exclusive creator merch drop — limited stock',
        icon: Icons.auto_awesome_rounded,
      ),
      LevelReward(
        brand: 'Brand Ambassador',
        title: 'Trial Programme',
        code: 'DIVINEAMB',
        description: 'Apply for a paid brand ambassador trial',
        icon: Icons.workspace_premium_rounded,
      ),
      LevelReward(
        brand: 'Amazon',
        title: '₹500 Gift Card',
        code: 'DIVINEGIFT',
        description: 'Redeemable on any Amazon purchase',
        icon: Icons.redeem_rounded,
      ),
    ],
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
