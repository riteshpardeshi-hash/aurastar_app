import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../core/utils/legal_links.dart';

/// Apple 5.1.2 (backend ADR 129): ask before the user's username and score are shown on a
/// public leaderboard. Returns `true` (Agree), `false` (Not now) — never null, since the
/// dialog can't be dismissed without answering.
Future<bool> showLeaderboardConsentDialog(BuildContext context) async {
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const LeaderboardConsentDialog(),
  );
  return agreed ?? false;
}

class LeaderboardConsentDialog extends StatelessWidget {
  const LeaderboardConsentDialog({super.key});

  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('leaderboard-consent-dialog'),
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Show you on the leaderboard?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your username and score will be uploaded to our server and shown on a '
              'public global leaderboard. Do you agree?',
              style: TextStyle(color: Colors.white, height: 1.4),
            ),
            const SizedBox(height: 10),
            Text(
              'If you choose Not now, you can still play and earn Aura — you just won\'t '
              'appear on public leaderboards. You can change this any time in Settings.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('leaderboard-consent-privacy'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: _accent,
              ),
              onPressed: () => LegalLinks.open(LegalLinks.privacy),
              child: const Text('Read our Privacy Policy'),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('leaderboard-consent-not-now'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Not now',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            key: const Key('leaderboard-consent-agree'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Agree'),
          ),
        ],
      ),
    );
  }
}
