import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/aura_tier.dart';

class LevelRewardsScreen extends StatelessWidget {
  const LevelRewardsScreen({super.key});

  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text(
          'Aura Levels',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: user == null
            ? null
            : FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snap) {
          int points = 0;
          if (snap.hasData && snap.data!.exists) {
            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            points = (data['totalRewards'] ?? 0) as int;
          }
          final currentLevel = (points ~/ 1300) + 1;
          final currentTier = auraTierForLevel(currentLevel);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _accent.withValues(alpha: 0.4),
                      currentTier.color.withValues(alpha: 0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: currentTier.color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                currentTier.color.withValues(alpha: 0.35),
                                currentTier.color.withValues(alpha: 0.08),
                              ],
                            ),
                            border: Border.all(color: currentTier.color.withValues(alpha: 0.70), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: currentTier.color.withValues(alpha: 0.35),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Level', style: TextStyle(color: Colors.white70, fontSize: 9)),
                            Text(
                              '$currentLevel',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              currentTier.name,
                              style: TextStyle(
                                color: currentTier.color,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your Status', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        Text(
                          currentTier.name,
                          style: TextStyle(
                            color: currentTier.color,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentTier.unlock,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'All Levels',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              ...auraTiers.map((tier) {
                final isUnlocked = currentLevel >= tier.minLevel;
                final isCurrent = currentTier.minLevel == tier.minLevel;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: isCurrent
                        ? tier.color.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.03),
                    border: Border.all(
                      color: isCurrent
                          ? tier.color.withValues(alpha: 0.6)
                          : isUnlocked
                              ? tier.color.withValues(alpha: 0.2)
                              : Colors.white12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Tier header ──────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isUnlocked
                                    ? tier.color.withValues(alpha: 0.18)
                                    : Colors.white.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: isUnlocked
                                      ? tier.color.withValues(alpha: 0.5)
                                      : Colors.white12,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  isUnlocked
                                      ? Icons.lock_open_rounded
                                      : Icons.lock_outline,
                                  color: isUnlocked ? tier.color : Colors.white24,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        tier.name,
                                        style: TextStyle(
                                          color: isUnlocked
                                              ? tier.color
                                              : Colors.white38,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (isCurrent) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color:
                                                tier.color.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Current',
                                            style: TextStyle(
                                                color: Colors.white, fontSize: 10),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tier.unlock,
                                    style: TextStyle(
                                      color: isUnlocked
                                          ? Colors.white60
                                          : Colors.white24,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Lv ${tier.minLevel}',
                              style: TextStyle(
                                color:
                                    isUnlocked ? Colors.white60 : Colors.white24,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ── Reward items ─────────────────────────────────────
                      if (tier.rewards.isNotEmpty) ...[
                        Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Column(
                            children: tier.rewards.map((r) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isUnlocked
                                            ? tier.color.withValues(alpha: 0.15)
                                            : Colors.white.withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(
                                        r.icon,
                                        color: isUnlocked
                                            ? tier.color
                                            : Colors.white24,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${r.brand} — ${r.title}',
                                            style: TextStyle(
                                              color: isUnlocked
                                                  ? Colors.white
                                                  : Colors.white30,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            r.description,
                                            style: TextStyle(
                                              color: isUnlocked
                                                  ? Colors.white.withValues(alpha: 0.45)
                                                  : Colors.white.withValues(alpha: 0.15),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isUnlocked
                                            ? tier.color.withValues(alpha: 0.18)
                                            : Colors.white.withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isUnlocked
                                              ? tier.color.withValues(alpha: 0.4)
                                              : Colors.white12,
                                        ),
                                      ),
                                      child: Text(
                                        isUnlocked ? r.code : '??????',
                                        style: TextStyle(
                                          color: isUnlocked
                                              ? tier.color
                                              : Colors.white24,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
