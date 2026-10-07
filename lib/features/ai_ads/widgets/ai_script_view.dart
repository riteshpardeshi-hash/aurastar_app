import 'package:flutter/material.dart';

import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import 'ai_ui.dart';

/// A script as a readable storyboard: title + length, the hook, one card per scene on a
/// timeline (when it plays, what we see, the voiceover, the on-screen text), then the call
/// to action. A hand-written script (no scenes) is shown as plain text.
class AiScriptView extends StatelessWidget {
  final AiGeneration script;

  const AiScriptView({super.key, required this.script});

  @override
  Widget build(BuildContext context) {
    final scenes = script.scenes;
    if (scenes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: AiUi.cardDecoration(),
        child: Text(script.scriptText, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.55)),
      );
    }

    final total = scenes.fold<double>(0, (sum, sc) => sum + sc.durationSeconds);
    var start = 0.0;
    final timed = <({AiScriptScene scene, double from, double to})>[];
    for (final sc in scenes) {
      timed.add((scene: sc, from: start, to: start + sc.durationSeconds));
      start += sc.durationSeconds;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                script.scriptTitle.isEmpty ? 'Your ad' : script.scriptTitle,
                style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.3, fontWeight: FontWeight.w700, fontFamily: 'ClashDisplay'),
              ),
            ),
            const SizedBox(width: 10),
            _Chip(icon: Icons.timer_outlined, text: '${_secs(total)}s · ${scenes.length} scene${scenes.length == 1 ? '' : 's'}'),
          ],
        ),
        if (script.scriptHook.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Callout(label: 'HOOK', text: script.scriptHook, color: AiUi.accent),
        ],
        const SizedBox(height: 14),
        for (var i = 0; i < timed.length; i++)
          _SceneCard(index: i + 1, scene: timed[i].scene, from: timed[i].from, to: timed[i].to, last: i == timed.length - 1),
        if (script.scriptCallToAction.isNotEmpty) ...[
          const SizedBox(height: 4),
          _Callout(label: 'CALL TO ACTION', text: script.scriptCallToAction, color: AiUi.success),
        ],
      ],
    );
  }
}

String _secs(double s) => s == s.roundToDouble() ? s.toInt().toString() : s.toStringAsFixed(1);

class _SceneCard extends StatelessWidget {
  final int index;
  final AiScriptScene scene;
  final double from;
  final double to;
  final bool last;

  const _SceneCard({required this.index, required this.scene, required this.from, required this.to, required this.last});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail: numbered dot + connector to the next scene.
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AiUi.accent.withValues(alpha: 0.25), shape: BoxShape.circle, border: Border.all(color: AiUi.accent)),
                  child: Text('$index', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                if (!last) Expanded(child: Container(width: 2, color: AiUi.accent.withValues(alpha: 0.25))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: AiUi.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Scene $index', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                        '${_secs(from)}–${_secs(to)}s',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(scene.visual, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                  if (scene.voiceover.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _Line(icon: Icons.mic_none_rounded, label: 'Voiceover', text: '“${scene.voiceover}”', italic: true),
                  ],
                  if (scene.onScreenText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _Line(icon: Icons.text_fields_rounded, label: 'On screen', text: scene.onScreenText, emphasised: true),
                  ],
                  if (scene.brandAssetCues.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final cue in scene.brandAssetCues) _Chip(icon: Icons.sell_outlined, text: cue)],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Voiceover / on-screen text: a small labelled icon line.
class _Line extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final bool italic;
  final bool emphasised;

  const _Line({required this.icon, required this.label, required this.text, this.italic = false, this.emphasised = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: AiUi.accent)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(color: AppColors.textFaint, fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  color: emphasised ? Colors.white : AppColors.textMuted,
                  fontSize: 13,
                  height: 1.45,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                  fontWeight: emphasised ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hook / call to action: a tinted block with a coloured edge.
class _Callout extends StatelessWidget {
  final String label;
  final String text;
  final Color color;

  const _Callout({required this.label, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
