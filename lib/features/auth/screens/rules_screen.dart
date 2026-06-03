import 'package:flutter/material.dart';
import 'setup_screen.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  static const _rules = [
    (
      icon: Icons.auto_awesome_rounded,
      title: 'AuraSense is the judge',
      body:
          'Your performance is scored by AI. No human bias — only your execution matters.',
    ),
    (
      icon: Icons.checkroom_outlined,
      title: 'Only performance is scored',
      body:
          'Clothes, hair, location and appearance do not affect your score.',
    ),
    (
      icon: Icons.copy_all_outlined,
      title: 'Copy the challenge closely',
      body:
          'Match the timing, movement, and sound as accurately as possible.',
    ),
    (
      icon: Icons.shield_outlined,
      title: 'Fair play = more rewards',
      body:
          'Duplicate uploads, fake accounts and unsafe content will be flagged and penalised.',
    ),
    (
      icon: Icons.trending_up_rounded,
      title: 'Your best scores count',
      body:
          'Only your top scores each day contribute to leaderboards and Aura points.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Image.asset(
                  'assets/images/Aura arena.png',
                  width: 160,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'Rules First',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Read before you play.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: _rules
                      .map((r) => _RuleTile(
                            icon: r.icon,
                            title: r.title,
                            body: r.body,
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const SetupScreen()),
                ),
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.45),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'I Understand',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _RuleTile(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF7B2CBF), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
