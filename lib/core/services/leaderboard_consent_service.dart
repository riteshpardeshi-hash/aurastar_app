import 'package:flutter/material.dart';

import '../../shared/widgets/leaderboard_consent_dialog.dart';
import 'auth_api_service.dart';

/// The signed-in user's public-leaderboard consent (Apple 5.1.2 — backend ADR 129).
///
/// The backend is the source of truth (`leaderboardConsent.status` on GET /profile):
/// 'granted' → shown on public leaderboards; 'declined' or null → hidden. Every account
/// starts at null — including ones from before consent existed, which the backend also
/// reports as null — and is asked here once after sign-in (MainShell); Settings has a toggle.
///
/// A profile with no `leaderboardConsent` key at all (an older backend) is "unknown" and
/// never prompts.
class LeaderboardConsentService {
  LeaderboardConsentService._();
  static final instance = LeaderboardConsentService._();

  /// 'granted' | 'declined' | null. Null also while [known] is false.
  final ValueNotifier<String?> status = ValueNotifier<String?>(null);

  /// Whether [status] came from the backend this session.
  bool known = false;

  bool _asking = false;

  /// Read the consent off a GET /profile `user` map (MyAccountScreen and others already
  /// load it, so this costs no extra request).
  void updateFromProfile(Map<String, dynamic>? user) {
    final consent = user?['leaderboardConsent'];
    if (consent is! Map) return;
    known = true;
    status.value = consent['status'] as String?;
  }

  /// Persist the user's choice and reflect it locally. Throws on failure — the caller
  /// shows the error and leaves the old value in place.
  Future<void> setGranted(bool granted) async {
    final stored = await AuthApiService().setLeaderboardConsent(granted);
    known = true;
    status.value = stored;
  }

  /// Ask once if the backend says this account has never answered. Safe to call from
  /// anywhere a BuildContext is available; concurrent calls share one dialog.
  Future<void> askIfNeeded(BuildContext context) async {
    if (_asking) return;
    _asking = true;
    try {
      if (!known) updateFromProfile(await AuthApiService().getProfile());
      if (!known || status.value != null || !context.mounted) return;
      final agreed = await showLeaderboardConsentDialog(context);
      try {
        await setGranted(agreed);
      } catch (_) {
        // Couldn't save — leave it unanswered so the next launch asks again.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Couldn't save your leaderboard choice. We'll ask again later.",
              ),
            ),
          );
        }
      }
    } finally {
      _asking = false;
    }
  }

  /// Forget the cached value (sign-out / account switch).
  void reset() {
    known = false;
    status.value = null;
  }
}
