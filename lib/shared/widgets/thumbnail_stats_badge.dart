import 'package:flutter/material.dart';
import 'aura_score_badge.dart';

/// Bottom-of-thumbnail overlay for a challenge card: how many people have
/// entered (participants) on the left, and the Aura on offer on the right.
/// Sits on a soft bottom gradient so both stay legible over any thumbnail.
///
/// Meant to be dropped into a `Stack` as `Positioned(left/right/bottom: 0)`.
class ThumbnailStatsBadge extends StatelessWidget {
  final int participants;

  const ThumbnailStatsBadge({super.key, required this.participants});

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(7, 16, 7, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: Colors.white70, size: 13),
          const SizedBox(width: 3),
          Text(
            _fmt(participants),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'SpaceGrotesk',
              shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
            ),
          ),
          const Spacer(),
          const AuraScoreBadge(),
        ],
      ),
    );
  }
}
