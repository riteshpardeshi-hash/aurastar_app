import 'package:flutter/material.dart';

/// Small pill overlaid on a video/challenge thumbnail showing its aura score.
/// Static placeholder — the backend doesn't expose a per-thumbnail aura
/// value yet, so every card shows the same [score] until that lands.
class AuraScoreBadge extends StatelessWidget {
  final int score;

  const AuraScoreBadge({super.key, this.score = 100});

  @override
  Widget build(BuildContext context) {
    return Row(
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
            // No background pill behind this anymore — a shadow keeps the
            // number legible over light thumbnails.
            shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
          ),
        ),
      ],
    );
  }
}
