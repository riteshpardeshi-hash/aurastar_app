import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import 'ai_ui.dart';

/// A small coloured status pill.
class AiStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const AiStatusBadge({super.key, required this.label, required this.color});

  /// What a generation is doing.
  factory AiStatusBadge.generation(AiGeneration g, {Key? key}) => AiStatusBadge(
    key: key,
    label: switch (g.status) {
      'RUNNING' => g.stage == AiStage.video ? 'Generating video' : 'Generating',
      'COMPLETED' => g.stage == AiStage.image ? 'Pick your images' : 'Ready',
      'CANCELLED' => 'Cancelled',
      _ => 'Failed — not charged',
    },
    color: switch (g.status) {
      'RUNNING' => const Color(0xFFD4A8FF),
      'COMPLETED' => g.stage == AiStage.image ? AiUi.warning : AiUi.success,
      _ => AiUi.danger,
    },
  );

  /// Where an AI judgement is.
  factory AiStatusBadge.evaluation(AiEvaluation e, {Key? key}) => AiStatusBadge(
    key: key,
    label: switch (e.status) {
      'COMPLETED' => 'Scored ${e.overallScore ?? '-'}',
      'FAILED' => 'Scoring failed — not charged',
      _ => 'Scoring',
    },
    color: switch (e.status) {
      'COMPLETED' => AiUi.success,
      'FAILED' => AiUi.danger,
      _ => const Color(0xFFD4A8FF),
    },
  );

  /// The creator's standing in a campaign.
  factory AiStatusBadge.participation(String status, {Key? key}) => AiStatusBadge(
    key: key,
    label: switch (status) {
      'INVITED' => "You're invited",
      'REQUESTED' => 'Waiting for the brand',
      'ACTIVE' => "You're in",
      'SUBMITTED' => 'Submitted',
      'WINNER' => 'Winner 🏆',
      'NOT_SELECTED' => 'Not selected',
      'REJECTED' => 'Not accepted',
      'REMOVED' => 'Removed',
      'WITHDRAWN' => 'You left',
      _ => status.toLowerCase(),
    },
    color: switch (status) {
      'ACTIVE' || 'SUBMITTED' => AiUi.success,
      'WINNER' => AiUi.warning,
      'INVITED' || 'REQUESTED' => const Color(0xFFD4A8FF),
      _ => Colors.white54,
    },
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
