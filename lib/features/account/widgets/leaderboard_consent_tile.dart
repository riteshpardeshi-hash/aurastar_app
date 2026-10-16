import 'package:flutter/material.dart';

import '../../../core/services/auth_api_service.dart';
import '../../../core/services/leaderboard_consent_service.dart';

/// Settings → "Show me on leaderboards" (Apple 5.1.2 — backend ADR 129). On = your
/// username and score appear on public leaderboards; off withdraws consent and removes
/// you from them immediately.
class LeaderboardConsentTile extends StatefulWidget {
  const LeaderboardConsentTile({super.key});

  @override
  State<LeaderboardConsentTile> createState() => _LeaderboardConsentTileState();
}

class _LeaderboardConsentTileState extends State<LeaderboardConsentTile> {
  final _consent = LeaderboardConsentService.instance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (!_consent.known) _load();
  }

  Future<void> _load() async {
    _consent.updateFromProfile(await AuthApiService().getProfile());
    if (mounted) setState(() {});
  }

  Future<void> _toggle(bool on) async {
    setState(() => _saving = true);
    try {
      await _consent.setGranted(on);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            on
                ? 'You\'ll appear on public leaderboards.'
                : 'You\'ve been removed from public leaderboards.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't update your leaderboard setting. Try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: _consent.status,
      builder: (context, status, _) {
        final on = status == 'granted';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Material(
            color: const Color(0xFF0E0E20),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              key: const Key('leaderboard-consent-switch'),
              secondary: const Icon(
                Icons.leaderboard_outlined,
                color: Colors.white,
                size: 22,
              ),
              title: const Text(
                'Show me on leaderboards',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              subtitle: const Text(
                'Your username and score appear on public leaderboards',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              value: on,
              activeTrackColor: const Color(0xFF7B2CBF),
              onChanged: (_saving || !_consent.known) ? null : _toggle,
            ),
          ),
        );
      },
    );
  }
}
