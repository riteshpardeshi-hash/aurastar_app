import 'package:flutter/material.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/widgets/challenge_leaderboard_row.dart';

// Pushed from ChallengeDetail's "See Leaderboard" button — only reachable
// once the viewer has taken this specific challenge (see _mySubmission gate
// in challenge_detail.dart). Reuses ChallengesService().fetchSubmissions(),
// same as leaderboard_screen.dart's per-challenge tab: GET
// /leaderboard/challenge/{id} is empirically broken server-side (returns an
// empty `responses` array for challenges with real scored submissions),
// while GET /challenges/{id}/submissions is already sorted by aiScore
// descending and doubles as the real per-challenge leaderboard.
class ChallengeLeaderboardScreen extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;

  const ChallengeLeaderboardScreen({
    super.key,
    required this.challengeId,
    required this.challengeTitle,
  });

  @override
  State<ChallengeLeaderboardScreen> createState() =>
      _ChallengeLeaderboardScreenState();
}

class _ChallengeLeaderboardScreenState
    extends State<ChallengeLeaderboardScreen> {
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _myId;
  // GET /challenges/{id}/submissions (used below) never joins a display
  // name for the submitter — see normaliseSubmissionEntry's doc comment —
  // so every row falls back to "Player N". For the viewer's own row we
  // don't need that guesswork: GET /profile already has their real name.
  String? _myUsername;

  @override
  void initState() {
    super.initState();
    ApiClient().userId.then((id) {
      if (mounted) setState(() => _myId = id);
    });
    AuthApiService().getProfile().then((profile) {
      if (!mounted || profile == null) return;
      final name = (profile['displayName'] as String?)?.trim();
      final username = (profile['username'] as String?)?.trim();
      final profileName = (profile['profileName'] as String?)?.trim();
      final resolved = (username?.isNotEmpty ?? false)
          ? username
          : (name?.isNotEmpty ?? false)
              ? name
              : profileName;
      if (resolved?.isNotEmpty ?? false) {
        setState(() => _myUsername = resolved);
      }
    });
    _load();
  }

  Future<void> _load() async {
    final raw =
        await ChallengesService().fetchSubmissions(widget.challengeId, limit: 50);
    if (!mounted) return;
    setState(() {
      _entries = raw.map(normaliseSubmissionEntry).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.challengeTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _entries.isEmpty
              ? RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: leaderboardEmptyState(
                          'No scores yet',
                          'Be the first to top this challenge!',
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      final isMe = e['id'] == _myId;
                      final rawUsername = e['username'] as String;
                      final rawName = e['name'] as String;
                      final username = (isMe && (_myUsername?.isNotEmpty ?? false))
                          ? _myUsername!
                          : rawUsername.isNotEmpty
                              ? rawUsername
                              : rawName.isNotEmpty
                                  ? rawName
                                  : 'Player ${i + 1}';
                      return ChallengeLeaderboardRow(
                        rank: i + 1,
                        username: username,
                        score: e['score'] as int,
                        stars: e['stars'] as int,
                        isCurrentUser: isMe,
                        onTap:
                            isMe ? null : () => showPrivateProfileNotice(context),
                      );
                    },
                  ),
                ),
    );
  }
}
