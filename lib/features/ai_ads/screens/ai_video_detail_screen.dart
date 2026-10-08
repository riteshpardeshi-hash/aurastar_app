import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_dialogs.dart';
import '../widgets/ai_job_status_badge.dart';
import '../widgets/ai_ui.dart';
import '../widgets/ai_video_player.dart';

/// One generation in the workspace. What it shows depends on what it is:
///  - images: pick keyframes → turn them into a video;
///  - a video being made: progress (poll) + cancel;
///  - a finished video: play it, get it judged by AI (score + feedback),
///    iterate on it (edit / extend / new audio), submit it as the final ad.
class AiVideoDetailScreen extends StatefulWidget {
  final String campaignId;
  final String generationId;

  const AiVideoDetailScreen({super.key, required this.campaignId, required this.generationId});

  @override
  State<AiVideoDetailScreen> createState() => _AiVideoDetailScreenState();
}

enum _Iterate { edit, extend, reaudio }

class _AiVideoDetailScreenState extends State<AiVideoDetailScreen> {
  final _service = AiAdsService();
  final _instructions = TextEditingController();

  AiGeneration? _gen;
  AiWorkspace? _workspace;
  AiParticipation? _participation;
  List<AiBrandAsset> _assets = [];
  List<AiEvaluation> _evaluations = [];
  bool _loading = true;
  bool _busy = false;
  Timer? _poll;
  Timer? _ticker; // redraws the elapsed / remaining time while a video generates
  bool _onScreenText = true;
  Timer? _debounce;

  final Set<int> _picked = {};
  int? _seconds;
  bool _pickedStoryboard = false;
  _Iterate _iterate = _Iterate.edit;
  int _extendSeconds = 5;

  AiQuote? _videoQuote;
  AiQuote? _iterateQuote;

  // The board: the image version shown (and used) in each slot. Starts as this set's own.
  List<_Slot>? _board;
  // "Change images": the slots being changed, each with what to change in it.
  final Map<int, TextEditingController> _changes = {};
  AiQuote? _imageEditQuote;
  AiQuote? _evalQuote;
  String? _quoteError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ticker?.cancel();
    _debounce?.cancel();
    _instructions.dispose();
    for (final c in _changes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.fetchGeneration(widget.campaignId, widget.generationId),
        _service.fetchWorkspace(widget.campaignId),
        _service.fetchEvaluations(widget.campaignId),
        _service.fetchCampaign(widget.campaignId),
      ]);
      if (!mounted) return;
      final gen = results[0] as AiGeneration;
      final ws = results[1] as AiWorkspace;
      setState(() {
        _gen = gen;
        _workspace = ws;
        _evaluations = (results[2] as List<AiEvaluation>).where((e) => e.videoGenerationId == gen.id).toList();
        _participation = (results[3] as AiCampaign).myParticipation;
        _assets = (results[3] as AiCampaign).assets;
        _seconds ??= _scriptGen(ws)?.durationSeconds ?? ws.format.minDurationSeconds;
        // A storyboard starts with every scene's frame picked — the closest match to the script.
        if (gen.stage == AiStage.image && gen.isDone && _board == null) {
          _board = [for (var i = 0; i < gen.imageUrls.length; i++) _Slot(gen.id, i, gen.imageUrls[i], gen.versionNumber)];
        }
        if (!_pickedStoryboard && gen.isDone && gen.sceneIndexes.isNotEmpty) {
          _pickedStoryboard = true;
          _picked.addAll([for (var i = 0; i < gen.imageUrls.length; i++) i]);
        }
        _loading = false;
      });
      _schedulePoll();
      _refreshQuotes();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AiUi.toast(context, e is AiAdsException ? e.message : "Couldn't load this.");
    }
  }

  AiEvaluation? get _latestEval => _evaluations.isEmpty ? null : _evaluations.first;

  /// No score yet, or the last try failed (refunded) — the creator can (re)request one.
  bool get _canRequestEval => _latestEval == null || _latestEval!.status == 'FAILED';

  String _assetName(String handle) {
    for (final a in _assets) {
      if (a.handle == handle) return a.name;
    }
    return '@$handle';
  }

  void _schedulePoll() {
    _poll?.cancel();
    final waiting = (_gen?.isRunning ?? false) || (_latestEval?.isPending ?? false);
    if (waiting) _poll = Timer(const Duration(seconds: 5), _load);
    final generating = _gen?.isRunning ?? false;
    if (generating && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!generating) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  // ─── Quotes ───────────────────────────────────────────────────────────────

  String? get _scriptForVideo {
    final g = _gen;
    if (g?.scriptId != null) return g!.scriptId;
    final scripts = _workspace?.of(AiStage.script).where((s) => s.isDone).toList() ?? [];
    return scripts.isEmpty ? null : scripts.last.id;
  }

  AiGeneration? _scriptGen(AiWorkspace ws) {
    final id = _gen?.scriptId ?? _scriptForVideo;
    for (final g in ws.generations) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// "Scene 2 · 3–7s" for a storyboard image, null for a plain take.
  String? _sceneLabel(AiGeneration g, int i) {
    if (i >= g.sceneIndexes.length) return null;
    final scene = g.sceneIndexes[i];
    final scenes = _scriptGen(_workspace!)?.scenes ?? const [];
    if (scene >= scenes.length) return 'Scene ${scene + 1}';
    var from = 0.0;
    for (var k = 0; k < scene; k++) {
      from += scenes[k].durationSeconds;
    }
    String f(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return 'Scene ${scene + 1} · ${f(from)}–${f(from + scenes[scene].durationSeconds)}s';
  }

  AiAction? get _videoFromImages {
    final g = _gen;
    if (g == null || g.stage != AiStage.image || !g.isDone || _picked.isEmpty || _scriptForVideo == null) return null;
    return AiAction(
      stage: AiStage.video,
      scriptId: _scriptForVideo,
      durationSeconds: _seconds,
      onScreenText: _onScreenText,
      keyframes: [
        for (final i in (_picked.toList()..sort())) (generationId: _board?[i].generationId ?? g.id, index: _board?[i].index ?? i),
      ],
    );
  }

  AiAction? get _iterateAction {
    final g = _gen;
    if (g == null || g.stage != AiStage.video || !g.isDone || _instructions.text.trim().isEmpty) return null;
    return AiAction(
      stage: AiStage.video,
      operation: switch (_iterate) {
        _Iterate.edit => 'EDIT',
        _Iterate.extend => 'EXTEND',
        _Iterate.reaudio => 'REAUDIO',
      },
      parentId: g.id,
      instructions: _instructions.text,
      durationSeconds: _iterate == _Iterate.extend ? _extendSeconds : null,
    );
  }

  /// Every selected image with what to change in it — null until each one says something.
  AiAction? get _imageEditAction {
    final g = _gen;
    final board = _board;
    if (g == null || board == null || g.stage != AiStage.image || !g.isDone || _changes.isEmpty) return null;
    if (_changes.values.any((c) => c.text.trim().isEmpty)) return null;
    final slots = _changes.keys.toList()..sort();
    final mixed = board.any((b) => b.generationId != g.id);
    return AiAction(
      stage: AiStage.image,
      operation: 'REFINE',
      parentId: g.id,
      edits: [for (final i in slots) (imageIndex: i, instructions: _changes[i]!.text)],
      // Only needed when the creator switched a slot to another version.
      slotSources: mixed ? [for (final b in board) (generationId: b.generationId, index: b.index)] : const [],
    );
  }

  /// Every version of each slot across this set's family (same script, same size), oldest
  /// first, without repeats — what the per-image version switcher offers.
  List<List<_Slot>> _versions(AiGeneration g) {
    final family = (_workspace?.generations ?? const <AiGeneration>[])
        .where((x) => x.stage == AiStage.image && x.isDone && x.scriptId == g.scriptId && x.imageUrls.length == g.imageUrls.length)
        .toList()
      ..sort((a, b) => a.versionNumber.compareTo(b.versionNumber));
    if (!family.any((x) => x.id == g.id)) family.add(g);
    return [
      for (var i = 0; i < g.imageUrls.length; i++)
        () {
          final seen = <String>{};
          return [
            for (final x in family)
              if (seen.add(_imagePath(x.imageUrls[i]))) _Slot(x.id, i, x.imageUrls[i], x.versionNumber),
          ];
        }(),
    ];
  }

  void _toggleChange(int slot) {
    setState(() {
      final existing = _changes.remove(slot);
      if (existing != null) {
        existing.dispose();
      } else {
        _changes[slot] = TextEditingController();
      }
    });
    _requote();
  }

  Future<void> _refreshQuotes() async {
    final g = _gen;
    if (g == null) return;
    try {
      final video = _videoFromImages;
      final iterate = _iterateAction;
      final imageEdit = _imageEditAction;
      final quotes = await Future.wait([
        if (video != null) _service.quote(widget.campaignId, video) else Future<AiQuote?>.value(null),
        if (iterate != null) _service.quote(widget.campaignId, iterate) else Future<AiQuote?>.value(null),
        if (g.stage == AiStage.video && g.isDone && _canRequestEval)
          _service.quoteEvaluation(widget.campaignId, g.id)
        else
          Future<AiQuote?>.value(null),
        if (imageEdit != null) _service.quote(widget.campaignId, imageEdit) else Future<AiQuote?>.value(null),
      ]);
      if (!mounted) return;
      setState(() {
        _imageEditQuote = quotes[3];
        _videoQuote = quotes[0];
        _iterateQuote = quotes[1];
        _evalQuote = quotes[2] ?? _evalQuote;
        _quoteError = null;
      });
    } on AiAdsException catch (e) {
      if (mounted) setState(() => _quoteError = e.message);
    } catch (_) {}
  }

  void _requote() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _refreshQuotes);
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<T?> _guard<T>(Future<T> Function() fn, {VoidCallback? onPriceChanged}) async {
    setState(() => _busy = true);
    try {
      return await fn();
    } on AiPriceChangedException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
      onPriceChanged?.call();
      _refreshQuotes();
    } on OutOfAiCreditsException catch (e) {
      if (mounted) {
        AiUi.toast(
          context,
          e.message,
          action: SnackBarAction(
            label: 'Ask for more',
            textColor: AppColors.accentLight,
            onPressed: () => showRequestCreditsSheet(context, campaignId: widget.campaignId),
          ),
        );
      }
    } on AiAdsException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
    } catch (_) {
      if (mounted) AiUi.toast(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _openNew(AiGeneration gen) async {
    if (!mounted) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AiVideoDetailScreen(campaignId: widget.campaignId, generationId: gen.id)),
    );
  }

  Future<void> _createVideo() async {
    final action = _videoFromImages;
    final quote = _videoQuote;
    if (action == null || quote == null) return;
    final gen = await _guard(() => _service.generate(widget.campaignId, action, expectedCredits: quote.credits));
    if (gen != null) await _openNew(gen);
  }

  /// Redoes the selected images with the creator's changes — a new version of the board.
  Future<void> _editImage() async {
    final action = _imageEditAction;
    final quote = _imageEditQuote;
    if (action == null || quote == null) return;
    final gen = await _guard(() => _service.generate(widget.campaignId, action, expectedCredits: quote.credits));
    if (gen == null || !mounted) return;
    if (!gen.isDone) {
      AiUi.toast(context, gen.error ?? "The images couldn't be changed — you weren't charged.");
      return;
    }
    await _openNew(gen);
  }

  Future<void> _iterateVideo() async {
    final action = _iterateAction;
    final quote = _iterateQuote;
    if (action == null || quote == null) return;
    final gen = await _guard(() => _service.generate(widget.campaignId, action, expectedCredits: quote.credits));
    if (gen != null) {
      _instructions.clear();
      await _openNew(gen);
    }
  }

  /// "Free · 4 left" — judging costs no credits (the platform pays), up to a limit.
  String _evalLabel(AiQuote? q) {
    if (q == null) return '…';
    final left = q.freeEvaluations?.left;
    return left == null ? 'Free' : 'Free · $left left';
  }

  Future<void> _evaluate() async {
    final quote = _evalQuote;
    if (quote == null) return;
    final e = await _guard(() => _service.requestEvaluation(widget.campaignId, widget.generationId));
    if (e != null) await _load();
  }

  Future<void> _cancel() async {
    final g = await _guard(() => _service.cancelVideo(widget.campaignId, widget.generationId));
    if (g != null) {
      if (mounted) AiUi.toast(context, "Cancelled — you weren't charged.");
      await _load();
    }
  }

  Future<void> _submitFinal() async {
    final p = await _guard(() => _service.submitFinal(widget.campaignId, widget.generationId));
    if (p != null) {
      if (mounted) AiUi.toast(context, 'Submitted! You can change your pick until the deadline.');
      await _load();
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final g = _gen;
    return Scaffold(
      backgroundColor: AiUi.bg,
      appBar: AiUi.appBar(
        g?.label ?? 'AI video',
        actions: [if (_workspace != null) AiCreditsChip(credits: _workspace!.creditsLeft), const SizedBox(width: 12)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
          : g == null
          ? const Center(child: Text('Not found', style: TextStyle(color: AppColors.textMuted)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Align(alignment: Alignment.centerLeft, child: AiStatusBadge.generation(g)),
                if (g.instructions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AiUi.cardDecoration(),
                    child: Text(g.instructions, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
                  ),
                ],
                const SizedBox(height: 16),
                if (g.status == 'FAILED' || g.status == 'CANCELLED')
                  Text(g.error ?? "This didn't work — you weren't charged.", style: const TextStyle(color: AiUi.danger))
                else if (g.isRunning)
                  _progress(g)
                else if (g.stage == AiStage.image)
                  _imagePicker(g)
                else if (g.stage == AiStage.video)
                  _videoResult(g),
                if (g.chargeState != 'FREE') ...[
                  const SizedBox(height: 16),
                  Text(
                    g.isRunning ? '${g.quotedCredits} credits on hold' : 'Cost ${g.chargedCredits} credits',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
                  ),
                ],
              ],
            ),
    );
  }

  /// "4:05" / "45s".
  static String _span(Duration d) {
    final m = d.inMinutes;
    final sec = d.inSeconds % 60;
    return m > 0 ? '$m:${sec.toString().padLeft(2, '0')}' : '${d.inSeconds}s';
  }

  /// The waiting screen for a generating video: elapsed vs. the backend's estimate as a
  /// progress bar, what's happening now, and what's being made.
  Widget _progress(AiGeneration g) {
    final started = g.etaStartedAt ?? g.createdAt;
    final total = g.etaSeconds;
    final elapsed = started == null ? Duration.zero : DateTime.now().difference(started);
    final fraction = total == null || total == 0 ? null : (elapsed.inSeconds / total).clamp(0.0, 1.0);
    final overdue = total != null && elapsed.inSeconds > total;
    final remaining = total == null ? null : Duration(seconds: (total - elapsed.inSeconds).clamp(0, total));
    // Steps track the estimate: sent → generating → finishing.
    final step = elapsed.inSeconds < 15 ? 0 : (fraction ?? 0) < 0.85 ? 1 : 2;
    const steps = ['Sending your script to the video AI', 'Generating your scenes', 'Finishing and checking the video'];
    final scenes = _scriptGen(_workspace!)?.scenes ?? const <AiScriptScene>[];
    return Column(
      key: const Key('ai-video-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AiUi.accent.withValues(alpha: 0.28), AiUi.card],
            ),
            border: Border.all(color: AiUi.accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.movie_creation_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Making your video', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'ClashDisplay')),
                  ),
                  Text(
                    [if (g.durationSeconds != null) '${g.durationSeconds}s', if (g.resolution != null) g.resolution!].join(' · '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  key: const Key('ai-video-progress-bar'),
                  value: overdue ? null : fraction,
                  minHeight: 8,
                  color: AiUi.accent,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('${_span(elapsed)} elapsed', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                  const Spacer(),
                  Text(
                    remaining == null
                        ? 'Usually a few minutes'
                        : overdue
                        ? 'Taking a little longer than usual…'
                        : remaining.inSeconds < 60
                        ? 'Almost there'
                        : 'About ${(remaining.inSeconds / 60).ceil()} min left',
                    key: const Key('ai-video-eta'),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (var k = 0; k < steps.length; k++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: k < step
                            ? const Icon(Icons.check_circle_rounded, color: AiUi.success, size: 18)
                            : k == step
                            ? const CircularProgressIndicator(strokeWidth: 2, color: AiUi.accent)
                            : Icon(Icons.radio_button_unchecked_rounded, color: Colors.white.withValues(alpha: 0.25), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        steps[k],
                        style: TextStyle(
                          color: k <= step ? Colors.white : AppColors.textFaint,
                          fontSize: 13,
                          fontWeight: k == step ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (scenes.isNotEmpty) ...[
          const AiSectionTitle("What's being made"),
          for (final (k, sc) in scenes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: AiUi.accent.withValues(alpha: 0.25),
                    child: Text('${k + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(sc.visual, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
        if (!g.onScreenText)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('On-screen text: off', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ),
        const SizedBox(height: 14),
        const Text(
          "You can leave this screen — the video keeps generating and will be here when you come back.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel (refunded)', style: TextStyle(color: AiUi.danger))),
        ),
      ],
    );
  }

  Widget _textToggle() => SwitchListTile(
    key: const Key('ai-onscreen-text'),
    contentPadding: EdgeInsets.zero,
    value: _onScreenText,
    activeThumbColor: AiUi.accent,
    title: const Text('Show on-screen text', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
    subtitle: const Text("Captions and titles from your script. Turn off for a clean video — the voiceover stays.", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
    onChanged: (v) {
      setState(() => _onScreenText = v);
      _requote();
    },
  );

  Widget _imagePicker(AiGeneration g) {
    final ws = _workspace!;
    final q = _videoQuote;
    final f = ws.format;
    final board = _board ?? [for (var i = 0; i < g.imageUrls.length; i++) _Slot(g.id, i, g.imageUrls[i], g.versionNumber)];
    final versions = _versions(g);
    final scriptSeconds = _scriptGen(ws)?.durationSeconds;
    final options = {
      if (ws.shortClipSeconds > 0 && ws.shortClipSeconds < f.minDurationSeconds) ws.shortClipSeconds,
      f.minDurationSeconds,
      ((f.minDurationSeconds + f.maxDurationSeconds) / 2).round(),
      f.maxDurationSeconds,
    }.toList()..sort();
    final storyboard = g.sceneIndexes.isNotEmpty;
    final editCount = _changes.length;
    final eq = _imageEditQuote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(storyboard ? 'Your storyboard' : 'Pick the images for your video',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'ClashDisplay')),
        const SizedBox(height: 4),
        Text(
          storyboard
              ? 'One frame per scene — each guides its scene in the video. Untick one to let the AI improvise that scene.'
              : 'Select one or more — they set the look of the video.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        for (var row = 0; row < board.length; row += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _imageTile(g, board, versions, row)),
                const SizedBox(width: 10),
                Expanded(child: row + 1 < board.length ? _imageTile(g, board, versions, row + 1) : const SizedBox.shrink()),
              ],
            ),
          ),
        AiSectionTitle(editCount > 1 ? 'Change images' : 'Change an image'),
        const Text('Tap the images to change and say what to change in each — only those are redone.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < board.length; i++)
            FilterChip(
              key: Key('ai-edit-image-$i'),
              label: Text('Image ${i + 1}'),
              selected: _changes.containsKey(i),
              onSelected: (_) => _toggleChange(i),
            ),
        ]),
        for (final i in (_changes.keys.toList()..sort())) ...[
          const SizedBox(height: 10),
          TextField(
            key: Key('ai-image-change-$i'),
            controller: _changes[i],
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => _requote(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.all(10),
                child: CircleAvatar(radius: 12, backgroundColor: AiUi.accent, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
              ),
              hintText: 'What should change in image ${i + 1}?',
              hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13),
              filled: true,
              fillColor: AiUi.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
          ),
        ],
        if (editCount > 0) ...[
          const SizedBox(height: 10),
          AiSecondaryButton(
            label: editCount == 1 ? 'Update image ${_changes.keys.first + 1}' : 'Update $editCount images',
            icon: Icons.auto_fix_high_rounded,
            price: _imageEditAction == null ? null : (eq == null ? '…' : '${eq.credits} credits'),
            onPressed: _busy || eq == null || !eq.canAfford || _imageEditAction == null ? null : _editImage,
          ),
        ],
        if (scriptSeconds != null) ...[
          const AiSectionTitle('Length'),
          Row(
            key: const Key('ai-fixed-length'),
            children: [
              const Icon(Icons.timer_outlined, color: AppColors.textMuted, size: 16),
              const SizedBox(width: 6),
              Text('${scriptSeconds}s', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Text('· set by your script', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ],
          ),
        ] else ...[
          const AiSectionTitle('Length'),
          Wrap(spacing: 8, children: [
            for (final s in options)
              ChoiceChip(label: Text('${s}s'), selected: s == _seconds, onSelected: (_) {
                setState(() => _seconds = s);
                _requote();
              }),
          ]),
        ],
        const SizedBox(height: 8),
        _textToggle(),
        const SizedBox(height: 12),
        if (_quoteError != null) AiWarningText(_quoteError!),
        if (q != null && !q.canAfford) const AiWarningText('Not enough credits for this video.'),
        AiPrimaryButton(
          label: _picked.isEmpty ? 'Pick at least one image' : q == null ? 'Create video · …' : 'Create video · ${q.credits} credits',
          busy: _busy,
          onPressed: _picked.isEmpty || q == null || !q.canAfford ? null : _createVideo,
        ),
      ],
    );
  }

  /// One image slot: the chosen version's image (number, scene, picked, "Edited · v2"), and
  /// a version switcher underneath when the slot has more than one. Versions are counted
  /// per image — this image's v1 is its original, v2 its first edit, and so on — so the
  /// numbers line up across images whatever set each edit happened in.
  Widget _imageTile(AiGeneration g, List<_Slot> board, List<List<_Slot>> versions, int i) {
    final slot = board[i];
    final mine = versions[i];
    final current = mine.indexWhere((v) => _imagePath(v.url) == _imagePath(slot.url));
    final edited = current > 0; // not this image's original
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 9 / 16,
          child: GestureDetector(
            key: Key('ai-image-$i'),
            onTap: () {
              setState(() => _picked.contains(i) ? _picked.remove(i) : _picked.add(i));
              _requote();
            },
            child: Container(
              decoration: AiUi.cardDecoration(selected: _picked.contains(i)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(slot.url, key: ValueKey(slot.url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: Colors.white24)),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      key: Key('ai-image-number-$i'),
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _changes.containsKey(i) ? AiUi.accent : Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                      ),
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (edited)
                    Positioned(
                      top: 10,
                      left: 40,
                      child: Container(
                        key: Key('ai-image-$i-edited'),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AiUi.success.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)),
                        child: Text('Edited · v${current + 1}', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  if (_sceneLabel(g, i) case final label?)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
                        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  if (_picked.contains(i)) const Positioned(top: 8, right: 8, child: Icon(Icons.check_circle, color: AiUi.accent, size: 22)),
                ],
              ),
            ),
          ),
        ),
        if (mine.length > 1) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (k, v) in mine.indexed)
                GestureDetector(
                  key: Key('ai-image-$i-version-${k + 1}'),
                  onTap: () {
                    setState(() => _board = [...board]..[i] = v);
                    _requote();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _imagePath(v.url) == _imagePath(slot.url) ? AiUi.accent : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _imagePath(v.url) == _imagePath(slot.url) ? AiUi.accent : Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Text('v${k + 1}', style: TextStyle(color: _imagePath(v.url) == _imagePath(slot.url) ? Colors.white : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _videoResult(AiGeneration g) {
    final eval = _latestEval;
    final isFinal = _participation?.finalGenerationId == g.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (g.videoUrl != null) AiVideoPlayer(url: g.videoUrl!),
        if (isFinal) ...[
          const SizedBox(height: 10),
          const Text('✓ This is your final ad', textAlign: TextAlign.center, style: TextStyle(color: AiUi.success, fontWeight: FontWeight.w700)),
        ],
        const AiSectionTitle('AI score'),
        if (eval == null || _canRequestEval) ...[
          if (eval != null)
            Text(eval.error ?? "It couldn't be judged — you weren't charged.", style: const TextStyle(color: AiUi.danger))
          else
            const Text(
              'The AI judges your ad (with the brand\'s logo, end card and sound added) against the brief and the brand\'s rules.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          const SizedBox(height: 12),
          if (_evalQuote != null && !_evalQuote!.canAfford)
            AiWarningText(_evalQuote!.reason ?? "You can't get this video judged right now."),
          AiPrimaryButton(
            label: '${eval == null ? 'Get AI score' : 'Try again'} · ${_evalLabel(_evalQuote)}',
            busy: _busy,
            onPressed: _evalQuote == null || !_evalQuote!.canAfford ? null : _evaluate,
          ),
        ] else if (eval.isPending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Column(children: [
              CircularProgressIndicator(color: AiUi.accent),
              SizedBox(height: 12),
              Text('Scoring your video against the brand brief…', style: TextStyle(color: Colors.white)),
            ]),
          )
        else ...[
          _scoreCard(eval),
          const SizedBox(height: 16),
          if (!isFinal) AiPrimaryButton(label: 'Submit as my final ad (free)', busy: _busy, onPressed: _submitFinal),
        ],
        if (g.isDone) _iterateSection(),
      ],
    );
  }

  Widget _scoreCard(AiEvaluation e) {
    String clock(double s) => '${(s ~/ 60)}:${(s % 60).round().toString().padLeft(2, '0')}';
    return Container(
      key: const Key('ai-score-card'),
      padding: const EdgeInsets.all(16),
      decoration: AiUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${e.overallScore ?? '-'}',
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, fontFamily: 'SpaceGrotesk')),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('/ 100 · match with the brand brief', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            ],
          ),
          if (e.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(e.summary, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
          ],
          if (e.mandatoryPass == false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Missing brand assets: ${e.mandatoryAssets.where((m) => !m.present).map((m) => _assetName(m.handle)).join(', ')}',
                style: const TextStyle(color: AiUi.warning, fontSize: 12),
              ),
            ),
          for (final v in [...e.forbiddenClaimViolations, ...e.safetyIssues])
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('⚠ $v', style: const TextStyle(color: AiUi.danger, fontSize: 12))),
          const SizedBox(height: 12),
          for (final c in e.criteria)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(c.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                    Text('${c.score.toStringAsFixed(c.score % 1 == 0 ? 0 : 1)}/10', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: c.score / 10,
                    minHeight: 4,
                    backgroundColor: Colors.white12,
                    color: c.score >= 7 ? AiUi.success : c.score >= 4 ? AiUi.warning : AiUi.danger,
                  ),
                  if (c.reason.isNotEmpty)
                    Text(c.reason, style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
                ],
              ),
            ),
          if (e.feedback.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('Feedback', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            for (final f in e.feedback)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${f.atSeconds == null ? '•' : clock(f.atSeconds!)}  ${f.note}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
          ],
          if (e.suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Try this', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            for (final s in e.suggestions)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('→ $s', style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
          ],
        ],
      ),
    );
  }

  Widget _iterateSection() {
    final q = _iterateQuote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AiSectionTitle('Improve this video'),
        Wrap(spacing: 8, children: [
          for (final (mode, label) in [(_Iterate.edit, 'Edit'), (_Iterate.extend, 'Make it longer'), (_Iterate.reaudio, 'New audio')])
            ChoiceChip(label: Text(label), selected: _iterate == mode, onSelected: (_) {
              setState(() => _iterate = mode);
              _requote();
            }),
        ]),
        if (_iterate == _Iterate.extend) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final s in [4, 5, 8, 10])
              ChoiceChip(label: Text('+${s}s'), selected: _extendSeconds == s, onSelected: (_) {
                setState(() => _extendSeconds = s);
                _requote();
              }),
          ]),
        ],
        const SizedBox(height: 10),
        TextField(
          key: const Key('ai-iterate-instructions'),
          controller: _instructions,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) {
            setState(() {});
            _requote();
          },
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: switch (_iterate) {
              _Iterate.edit => 'What should change? e.g. "show the can in the first 2 seconds"',
              _Iterate.extend => 'What happens next?',
              _Iterate.reaudio => 'What should it sound like? e.g. "upbeat lo-fi, no voiceover"',
            },
            hintStyle: const TextStyle(color: AppColors.textFaint),
            filled: true,
            fillColor: AiUi.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        if (q != null && !q.canAfford) const AiWarningText('Not enough credits for this change.'),
        AiSecondaryButton(
          label: _instructions.text.trim().isEmpty ? 'Describe the change first' : q == null ? 'Make the change · …' : 'Make the change · ${q.credits} credits',
          onPressed: _busy || q == null || !q.canAfford ? null : _iterateVideo,
        ),
      ],
    );
  }
}

/// One image on the board: which set it comes from, its position there, and its version.
class _Slot {
  final String generationId;
  final int index;
  final String url;
  final int version;

  const _Slot(this.generationId, this.index, this.url, this.version);
}

/// The same stored image has a different signed URL on every fetch — compare by path.
String _imagePath(String url) => Uri.tryParse(url)?.path ?? url;
