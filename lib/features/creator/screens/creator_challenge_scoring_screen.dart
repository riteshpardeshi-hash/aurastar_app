import 'package:flutter/material.dart';
import '../../../core/services/creator_challenges_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/scoring_criteria_panel.dart';

/// The scoring criteria of a saved challenge on their own page, opened from the
/// challenge status screen (backend ADR 137). Creating or editing a challenge
/// shows the same [ScoringCriteriaPanel] inline instead.
///
/// Pops `true` when the criteria changed, so the caller can refresh.
class CreatorChallengeScoringScreen extends StatefulWidget {
  final String challengeId;

  /// Injectable for widget tests.
  final CreatorChallengesService? service;

  const CreatorChallengeScoringScreen({super.key, required this.challengeId, this.service});

  @override
  State<CreatorChallengeScoringScreen> createState() => _CreatorChallengeScoringScreenState();
}

class _CreatorChallengeScoringScreenState extends State<CreatorChallengeScoringScreen> {
  static const _bg = Color(0xFF080810);

  bool _busy = false;
  bool _changed = false;
  bool _loaded = false;
  bool _editable = true;

  @override
  Widget build(BuildContext context) {
    // Don't let a back swipe abandon a generate/save that is still running.
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : () => Navigator.pop(context, _changed),
          ),
          title: const Text('Scoring Criteria',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Text(
              !_editable
                  ? 'These are the criteria every player is scored on. They can\'t be changed while the challenge is in review or live.'
                  : 'Every player\'s attempt is scored out of 100 using these criteria. The admin reviews them with the rest of your challenge.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            ScoringCriteriaPanel(
              challengeId: widget.challengeId,
              service: widget.service,
              onBusyChanged: (busy) => setState(() => _busy = busy),
              onChanged: (rubric) => setState(() {
                if (_loaded) _changed = true;
                _loaded = true;
                _editable = rubric?.editable ?? true;
              }),
            ),
          ],
        ),
      ),
    );
  }
}
