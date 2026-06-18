import 'package:flutter/material.dart';

class GameCardData {
  final String id;
  final String title;
  final String eyebrow;
  final String description;
  final Color accent;
  final bool available;
  final String category; // 'Aura Arcade' or 'Aura IQ'

  const GameCardData({
    required this.id,
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.accent,
    required this.available,
    required this.category,
  });
}

const kArcadeGames = [
  GameCardData(
    id: 'aura-flash-tap',
    title: 'Aura Flash Tap',
    eyebrow: 'REACTION',
    description: 'Wait for the aura. Tap the instant it flashes.',
    accent: Color(0xFF8C6CFF),
    available: true,
    category: 'Aura Arcade',
  ),
  GameCardData(
    id: 'catch-the-aura',
    title: 'Catch The Aura',
    eyebrow: 'PRECISION',
    description: 'Catch shifting aura orbs before they disappear.',
    accent: Color(0xFF48D7FF),
    available: true,
    category: 'Aura Arcade',
  ),
  GameCardData(
    id: 'swipe-direction-rush',
    title: 'Swipe Direction Rush',
    eyebrow: 'FOCUS',
    description: 'Read the signal and swipe in the correct direction.',
    accent: Color(0xFFFF62B7),
    available: true,
    category: 'Aura Arcade',
  ),
  GameCardData(
    id: 'pattern-rush',
    title: 'Pattern Rush',
    eyebrow: 'IQ',
    description: 'Spot the hidden rule. Pick the next number.',
    accent: Color(0xFFFFCE67),
    available: true,
    category: 'Aura IQ',
  ),
  GameCardData(
    id: 'blink-memory',
    title: 'Blink Memory',
    eyebrow: 'IQ',
    description: 'Memorise the lit cells. Recall them before time runs out.',
    accent: Color(0xFF36DCA2),
    available: true,
    category: 'Aura IQ',
  ),
  GameCardData(
    id: 'rule-breaker',
    title: 'Rule Breaker',
    eyebrow: 'IQ',
    description: 'Four numbers share a rule. One breaks it — find it fast.',
    accent: Color(0xFFFF6577),
    available: true,
    category: 'Aura IQ',
  ),
];

class GameCard extends StatelessWidget {
  final GameCardData game;
  final int bestScore;
  final bool completed;
  final VoidCallback onTap;

  const GameCard({
    super.key,
    required this.game,
    required this.bestScore,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: game.available ? onTap : null,
      child: Opacity(
        opacity: game.available ? 1.0 : 0.52,
        child: Container(
          constraints: const BoxConstraints(minHeight: 164),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: const Color(0xFF11172B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: game.accent),
          ),
          padding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -70,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: game.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        game.eyebrow,
                        style: TextStyle(
                          color: game.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                      Text(
                        completed
                            ? 'DONE TODAY'
                            : game.available
                                ? 'PLAY'
                                : 'SOON',
                        style: const TextStyle(
                          color: Color(0xFF9CA8C7),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    game.title,
                    style: const TextStyle(
                      color: Color(0xFFF7F8FF),
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ClashDisplay',
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.72,
                    child: Text(
                      game.description,
                      style: const TextStyle(
                        color: Color(0xFF9CA8C7),
                        fontSize: 14,
                        height: 1.43,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    bestScore > 0 ? 'BEST  $bestScore' : 'NO SCORE YET',
                    style: const TextStyle(
                      color: Color(0xFFF7F8FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
