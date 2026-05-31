import 'package:flutter/material.dart';

const String kChallengeBaseUrl = 'https://aura-app-efae1.web.app/challenge';

class AchievementCardView extends StatelessWidget {
  final String challengeTitle;
  final String challengeId;
  final int auraPoints;
  final String username;

  const AchievementCardView({
    super.key,
    required this.challengeTitle,
    required this.challengeId,
    required this.auraPoints,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 288,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A0018), Color(0xFF2A0B6B), Color(0xFF0A0018)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: const Color(0xFF9B4DCA), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B2CBF).withValues(alpha: 0.6),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/Aura Arena Mono.png', width: 20, height: 20),
              const SizedBox(width: 7),
              const Text(
                'AURA',
                style: TextStyle(
                  color: Color(0xFFD4A8FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.45)),
            ),
            child: const Text(
              '✦  CHALLENGE COMPLETED  ✦',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            challengeTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '+$auraPoints',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 60,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'AURA POINTS',
            style: TextStyle(
              color: Color(0xFFD4A8FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: const Color(0xFF9B4DCA).withValues(alpha: 0.35), height: 1),
          const SizedBox(height: 12),
          Text(
            '@$username',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Think you can beat me? 💪\nNow it\'s your turn!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_rounded, color: Color(0xFF9B4DCA), size: 13),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'aura.app/challenge/$challengeId',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9B4DCA),
                    fontSize: 10,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF9B4DCA),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
