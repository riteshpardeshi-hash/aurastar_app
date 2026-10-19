import 'package:flutter/material.dart';

import '../../core/services/auth_api_service.dart';
import 'screens/create_challenge.dart';
import 'screens/creator_challenge_draft_screen.dart';

/// The one way into "create a challenge", used by every entry point (Creator
/// Activity → Create challenge, My Challenges → New, the creator home quick
/// action) so they all open the same screen: the page where the creator fills
/// in the challenge, watches the reference video, builds the scoring criteria
/// and submits for approval (backend ADR 137).
///
/// Brand and admin accounts get the record flow instead: the creator draft
/// endpoints (`/creator/challenges`) accept the creator role only, while brands
/// and admins create through `POST /challenges`.
///
/// Returns `true` when something was created, so a list can refresh.
Future<bool> openCreateChallenge(
  BuildContext context, {
  Future<String?> Function()? loadRole,
}) async {
  final role = await (loadRole ?? _loadRole)();
  if (!context.mounted) return false;
  final useRecordFlow = role == 'brand' || role == 'admin' || role == 'super_admin';
  final created = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => useRecordFlow ? const CreateChallenge() : const CreatorChallengeDraftScreen(),
    ),
  );
  return created == true;
}

Future<String?> _loadRole() async {
  final profile = await AuthApiService().getProfile();
  return profile?['role'] as String?;
}
