import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_job_status_badge.dart';
import '../widgets/ai_ui.dart';
import 'ai_video_detail_screen.dart';

/// The creator's image sets and videos in one campaign — in progress, waiting
/// on an image pick, judged — and which one is their final ad. Generation is
/// asynchronous, so this is where creators come back to.
class MyAiVideosScreen extends StatefulWidget {
  final String campaignId;

  const MyAiVideosScreen({super.key, required this.campaignId});

  @override
  State<MyAiVideosScreen> createState() => _MyAiVideosScreenState();
}

class _MyAiVideosScreenState extends State<MyAiVideosScreen> {
  final _service = AiAdsService();
  List<AiGeneration> _items = [];
  Map<String, AiEvaluation> _latestEval = {};
  String? _finalId;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.fetchWorkspace(widget.campaignId),
        _service.fetchEvaluations(widget.campaignId),
        _service.fetchCampaign(widget.campaignId),
      ]);
      if (!mounted) return;
      final ws = results[0] as AiWorkspace;
      final evals = results[1] as List<AiEvaluation>;
      final latest = <String, AiEvaluation>{};
      for (final e in evals) {
        latest.putIfAbsent(e.videoGenerationId, () => e); // newest first from the API
      }
      setState(() {
        _items = ws.generations.where((g) => g.stage != AiStage.script).toList().reversed.toList();
        _latestEval = latest;
        _finalId = (results[2] as AiCampaign).myParticipation?.finalGenerationId;
        _loading = false;
      });
      _poll?.cancel();
      if (_items.any((g) => g.isRunning) || latest.values.any((e) => e.isPending)) {
        _poll = Timer(const Duration(seconds: 5), _load);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(AiGeneration g) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AiVideoDetailScreen(campaignId: widget.campaignId, generationId: g.id)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiUi.bg,
      appBar: AiUi.appBar('My AI videos'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
          : _items.isEmpty
          ? const Center(child: Text('No AI videos yet', style: TextStyle(color: AppColors.textFaint, fontSize: 13)))
          : RefreshIndicator(
              onRefresh: _load,
              color: AiUi.accent,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _card(_items[i]),
              ),
            ),
    );
  }

  Widget _card(AiGeneration g) {
    final eval = _latestEval[g.id];
    return GestureDetector(
      onTap: () => _open(g),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AiUi.cardDecoration(selected: g.id == _finalId),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    AiStatusBadge.generation(g),
                    if (eval != null) AiStatusBadge.evaluation(eval),
                    if (g.id == _finalId) const AiStatusBadge(label: 'Final ad', color: AiUi.success),
                  ]),
                  const SizedBox(height: 8),
                  Text(g.label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  if (g.instructions.isNotEmpty)
                    Text(g.instructions,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (eval?.overallScore != null)
              Column(children: [
                Text('${eval!.overallScore}',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, fontFamily: 'SpaceGrotesk')),
                const Text('score', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ])
            else if (g.isRunning || (eval?.isPending ?? false))
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AiUi.accent))
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
