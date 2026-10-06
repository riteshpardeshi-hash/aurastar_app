import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';

String aiJobStatusLabel(AiJobStatus s) => switch (s) {
  AiJobStatus.generatingImages => 'Generating images',
  AiJobStatus.imagesReady => 'Pick your images',
  AiJobStatus.generatingVideo => 'Generating video',
  AiJobStatus.scoring => 'Scoring',
  AiJobStatus.scored => 'Scored',
};

Color aiJobStatusColor(AiJobStatus s) => switch (s) {
  AiJobStatus.imagesReady => const Color(0xFFFFB84D),
  AiJobStatus.scored => const Color(0xFF4ADE80),
  _ => const Color(0xFFD4A8FF),
};

class AiJobStatusBadge extends StatelessWidget {
  final AiJobStatus status;

  const AiJobStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = aiJobStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        aiJobStatusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
