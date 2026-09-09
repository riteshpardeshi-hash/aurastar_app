import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// Shared between leaderboard_screen.dart's per-challenge tab and
// challenge_leaderboard_screen.dart (the challenge-detail "See Leaderboard"
// entry point) — both rank GET /challenges/{id}/submissions entries the same
// way, so the row/empty-state/private-profile-notice widgets live here once
// instead of being duplicated across the two screens.

class ChallengeLeaderboardRow extends StatelessWidget {
  final int rank;
  final String username;
  final int score;
  final int stars;
  final bool isCurrentUser;
  final VoidCallback? onTap;

  static const _accent = Color(0xFF7B2CBF);

  const ChallengeLeaderboardRow({
    super.key,
    required this.rank,
    required this.username,
    required this.score,
    required this.stars,
    required this.isCurrentUser,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final medalColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFB8B8C8)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : null;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? _accent.withValues(alpha: 0.13)
            : const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? _accent.withValues(alpha: 0.50)
              : Colors.white.withValues(alpha: 0.07),
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Rank badge
          SizedBox(
            width: 38,
            child: rank <= 3
                ? Icon(Icons.emoji_events_rounded, color: medalColor, size: 24)
                : Text(
                    '$rank',
                    style: TextStyle(
                      color: isCurrentUser ? Colors.white : AppColors.textFaint,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
          ),
          // Avatar
          CircleAvatar(
            radius: 17,
            backgroundColor: _accent.withValues(alpha: 0.25),
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Username
          Expanded(
            child: Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
          ),
          // Stars
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.white38, size: 14),
              const SizedBox(width: 3),
              Text(
                _fmt(stars),
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // AI Score
          Text(
            '$score',
            style: TextStyle(
              color: medalColor ??
                  (isCurrentUser ? const Color(0xFFD4A8FF) : Colors.white),
              fontWeight: FontWeight.w900,
              fontSize: 20,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  color: Color(0xFFD4A8FF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

Widget leaderboardEmptyState(String title, String subtitle, {Widget? action}) =>
    Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_outlined,
              color: Colors.white24, size: 52),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 16,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 12,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    );

void showPrivateProfileNotice(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 16),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Player profiles are private — keep playing to climb the board!',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
}
