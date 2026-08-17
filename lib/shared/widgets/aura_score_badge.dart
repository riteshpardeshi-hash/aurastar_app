import 'package:flutter/material.dart';

/// Small pill overlaid on a video/challenge thumbnail showing its aura score.
/// Static placeholder — the backend doesn't expose a per-thumbnail aura
/// value yet, so every card shows the same [score] until that lands.
class AuraScoreBadge extends StatelessWidget {
  final int score;

  const AuraScoreBadge({super.key, this.score = 100});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/homescreen/separate elements/coin icon.png',
            height: 11,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 3),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
        ],
      ),
    );
  }
}
