import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../widgets/ai_dialogs.dart';
import '../widgets/ai_script_view.dart';
import '../widgets/ai_ui.dart';
import 'ai_brand_assets_row.dart';
import 'ai_video_detail_screen.dart';
import 'my_ai_videos_screen.dart';

/// The creator's workspace in one campaign, as guided steps: the brief (folded),
/// 1 Script (write it with AI, refine it, or use your own), 2 Style (text to video
/// or images first, quality, on-screen text), then Your images and Your videos as two
/// separate collections — with the
/// Generate button pinned to the bottom.
///
/// Every paid action shows its exact price (a backend quote) on the button;
/// tapping the button is the confirmation, and the server never charges more
/// than that price.
/// Which script panel is open under the selected script.
enum _ScriptPanel { none, refine, newScript }

class CreateAiVideosScreen extends StatefulWidget {
  final String campaignId;

  const CreateAiVideosScreen({super.key, required this.campaignId});

  @override
  State<CreateAiVideosScreen> createState() => _CreateAiVideosScreenState();
}

class _CreateAiVideosScreenState extends State<CreateAiVideosScreen> {
  final _service = AiAdsService();
  final _scriptController = TextEditingController();
  final _directionController = TextEditingController();

  AiCampaign? _campaign;
  AiWorkspace? _workspace;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _briefOpen = false;
  _ScriptPanel _panel = _ScriptPanel.none;

  String? _scriptId;
  AiGenerationMethod _method = AiGenerationMethod.textToVideo;
  int? _seconds;
  bool _onScreenText = true;
  String? _resolution;

  // Quotes per action key; null = loading, absent = not asked yet.
  final Map<String, AiQuote?> _quotes = {};
  final Map<String, String> _quoteErrors = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scriptController.addListener(() {
      setState(() {});
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () => _quoteFor(_aiScriptAction));
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scriptController.dispose();
    _directionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_service.fetchCampaign(widget.campaignId), _service.fetchWorkspace(widget.campaignId)]);
      if (!mounted) return;
      final ws = results[1] as AiWorkspace;
      final scripts = ws.of(AiStage.script).where((g) => g.isDone).toList();
      setState(() {
        _campaign = results[0] as AiCampaign;
        _workspace = ws;
        _loading = false;
        _scriptId ??= scripts.isEmpty ? null : scripts.last.id;
        _seconds ??= ws.format.minDurationSeconds;
        // The brand sets the quality for the whole campaign (backend ADR 144); the app just
        // sends it along. An older backend without it falls back to 720p as before.
        _resolution =
            ws.format.resolution ??
            (ws.prices.resolutions.contains('720p') ? '720p' : (ws.prices.resolutions.isEmpty ? null : ws.prices.resolutions.first));
      });
      _refreshQuotes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AiAdsException ? e.message : "Couldn't open your workspace.";
      });
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  // Scripts are written for the chosen length — the backend makes the scene timings add up to it.
  AiAction get _aiScriptAction => AiAction(stage: AiStage.script, instructions: _scriptController.text, durationSeconds: _seconds);

  AiAction? get _refineAction =>
      _scriptId == null
          ? null
          : AiAction(
            stage: AiStage.script,
            operation: 'REFINE',
            parentId: _scriptId,
            instructions: _directionController.text,
            durationSeconds: _seconds,
          );

  /// Picks a script version and, when it was written for a length, matches the video to it.
  void _selectScript(AiGeneration script) {
    _scriptId = script.id;
    if (script.durationSeconds != null) _seconds = script.durationSeconds;
  }

  AiAction? get _createAction {
    if (_scriptId == null) return null;
    return _method == AiGenerationMethod.textToVideo
        ? AiAction(
          stage: AiStage.video,
          scriptId: _scriptId,
          durationSeconds: _seconds,
          resolution: _resolution,
          onScreenText: _onScreenText,
        )
        : AiAction(stage: AiStage.image, scriptId: _scriptId, perScene: true);
  }

  String _key(AiAction a) => a.toJson().toString();

  Future<void> _quoteFor(AiAction? action) async {
    if (action == null) return;
    final key = _key(action);
    setState(() {
      _quotes[key] = null;
      _quoteErrors.remove(key);
    });
    try {
      final q = await _service.quote(widget.campaignId, action);
      if (mounted) setState(() => _quotes[key] = q);
    } on AiAdsException catch (e) {
      if (mounted) {
        setState(() {
          _quotes.remove(key);
          _quoteErrors[key] = e.message;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _quotes.remove(key));
    }
  }

  void _refreshQuotes() {
    _quoteFor(_aiScriptAction);
    _quoteFor(_refineAction);
    _quoteFor(_createAction);
  }

  /// Price label for a button: "Write it with AI · 12 credits".
  String _priced(String label, AiAction? action) {
    if (action == null) return label;
    final key = _key(action);
    if (_quoteErrors.containsKey(key)) return label;
    if (!_quotes.containsKey(key) || _quotes[key] == null) return '$label · …';
    return '$label · ${_quotes[key]!.credits} credits';
  }

  /// Price pill text for a secondary button: "3 credits", "…" while quoting, none on a quote error.
  String? _priceTag(AiAction? action) {
    if (action == null) return null;
    final key = _key(action);
    if (_quoteErrors.containsKey(key)) return null;
    final q = _quotes[key];
    return q == null ? '…' : '${q.credits} credits';
  }

  AiQuote? _quote(AiAction? a) => a == null ? null : _quotes[_key(a)];

  /// Runs a paid action at its quoted price, handling every way it can be refused.
  Future<AiGeneration?> _runPaid(AiAction action) async {
    final quote = _quote(action);
    if (quote == null) return null;
    setState(() => _busy = true);
    try {
      return await _service.generate(widget.campaignId, action, expectedCredits: quote.credits);
    } on AiPriceChangedException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
      _quoteFor(action);
    } on OutOfAiCreditsException catch (e) {
      if (mounted) _offerMoreCredits(e.message);
    } on AiAdsException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
    } catch (_) {
      if (mounted) AiUi.toast(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  void _offerMoreCredits(String message) {
    AiUi.toast(
      context,
      message,
      action: SnackBarAction(label: 'Ask for more', textColor: AppColors.accentLight, onPressed: _askForCredits),
    );
  }

  Future<void> _askForCredits() async {
    final sent = await showRequestCreditsSheet(context, campaignId: widget.campaignId);
    if (sent && mounted) AiUi.toast(context, 'Request sent — the brand will review it.');
  }

  Future<void> _writeWithAi() async {
    final gen = await _runPaid(_aiScriptAction);
    if (gen == null || !mounted) return;
    if (!gen.isDone) {
      AiUi.toast(context, gen.error ?? "The script couldn't be written — you weren't charged.");
    } else {
      _scriptController.clear();
      _selectScript(gen);
    }
    await _load();
  }

  Future<void> _useOwnScript() async {
    setState(() => _busy = true);
    try {
      final gen = await _service.createOwnScript(widget.campaignId, _scriptController.text.trim());
      _scriptController.clear();
      _scriptId = gen.id;
      await _load();
    } on AiAdsException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refine() async {
    final action = _refineAction;
    if (action == null) return;
    final gen = await _runPaid(action);
    if (gen == null || !mounted) return;
    if (gen.isDone) {
      _directionController.clear();
      _selectScript(gen);
    } else {
      AiUi.toast(context, gen.error ?? "The script couldn't be refined — you weren't charged.");
    }
    await _load();
  }

  Future<void> _editScript(AiGeneration script) async {
    final text = await showEditScriptDialog(context, text: script.scriptText);
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final gen = await _service.editScript(widget.campaignId, script.id, text);
      _scriptId = gen.id;
      await _load();
    } on AiAdsException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
    }
  }

  Future<void> _create() async {
    final action = _createAction;
    if (action == null) return;
    final gen = await _runPaid(action);
    if (gen == null || !mounted) return;
    AiUi.toast(
      context,
      action.stage == AiStage.video
          ? 'Your video is being generated. You can leave this screen.'
          : gen.isDone
          ? 'Your images are ready — pick the ones to use.'
          : gen.error ?? "No image could be made — you weren't charged.",
    );
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AiVideoDetailScreen(campaignId: widget.campaignId, generationId: gen.id)),
    );
    if (mounted) _load();
  }

  Future<void> _openGeneration(AiGeneration gen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AiVideoDetailScreen(campaignId: widget.campaignId, generationId: gen.id)),
    );
    if (mounted) _load();
  }

  /// Image sets and videos made so far (not failed or cancelled), newest first.
  List<AiGeneration> _work(AiWorkspace ws) =>
      ws.generations.where((g) => g.stage != AiStage.script && (g.isDone || g.isRunning)).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

  /// The newest finished image set drawn from the selected script — its storyboard.
  AiGeneration? _latestBoard(AiWorkspace ws) {
    AiGeneration? best;
    for (final g in ws.generations) {
      if (g.stage == AiStage.image && g.isDone && g.scriptId == _scriptId && (best == null || g.versionNumber > best.versionNumber)) {
        best = g;
      }
    }
    return best;
  }

  /// One made item: an image set (first image + count), a video (a frame of itself), or a spinner.
  Widget _workTile(AiGeneration g) {
    return GestureDetector(
      key: Key('ai-work-${g.id}'),
      onTap: () => _openGeneration(g),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 9 / 14,
            child: Container(
              decoration: AiUi.cardDecoration(),
              clipBehavior: Clip.antiAlias,
              child:
                  g.stage == AiStage.image && g.imageUrls.isNotEmpty
                      ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            g.imageUrls.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: Colors.white24),
                          ),
                          if (g.imageUrls.length > 1)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${g.imageUrls.length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                        ],
                      )
                      : g.videoUrl != null && !g.isRunning
                      // A finished video shows a frame of itself, not an empty box (tester
                      // report); the shared thumbnail widget extracts and caches it.
                      ? Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoThumbnailWidget(key: Key('ai-work-thumb-${g.id}'), videoUrl: g.videoUrl!),
                          const Center(child: Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 28)),
                        ],
                      )
                      : Center(
                        child:
                            g.isRunning
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AiUi.accent),
                                )
                                : const Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 28),
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            g.isRunning ? '${g.label} · making…' : g.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// Step 3: what's been made so far — three across, newest first.
  Widget _workGrid(List<AiGeneration> work) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 20) / 3;
        return Wrap(spacing: 10, runSpacing: 12, children: [for (final g in work.take(6)) SizedBox(width: w, child: _workTile(g))]);
      },
    );
  }

  Future<void> _openMyVideos() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MyAiVideosScreen(campaignId: widget.campaignId)));
    if (mounted) _load();
  }

  // ─── UI ───────────────────────────────────────────────────────────────────
  //
  // Guided steps (client feedback, 24 Nov): the page used to open on "Your images &
  // videos", so creators landed on old work instead of the next ad. It now reads top to
  // bottom as the job is done — the brief (folded), 1 Script, 2 Style, 3 Your images &
  // videos — and the Generate button sits in a bar pinned to the bottom with what it will
  // make and its price, so it is never four screens away.

  @override
  Widget build(BuildContext context) {
    final ws = _workspace;
    final made = ws == null ? 0 : _work(ws).length;
    return Scaffold(
      backgroundColor: AiUi.bg,
      appBar: AiUi.appBar(
        'Create AI Videos',
        actions: [
          IconButton(
            key: const Key('ai-my-videos'),
            tooltip: 'My AI videos',
            icon: Badge(
              isLabelVisible: made > 0,
              backgroundColor: AiUi.accent,
              label: Text('$made'),
              child: const Icon(Icons.video_library_outlined),
            ),
            onPressed: _openMyVideos,
          ),
          if (ws != null) AiCreditsChip(credits: ws.creditsLeft),
          const SizedBox(width: 12),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
              : ws == null || _campaign == null
              ? Center(child: Text(_error ?? 'Not available', style: const TextStyle(color: AppColors.textMuted)))
              : _buildBody(_campaign!, ws),
    );
  }

  /// A pill choice (length, version, mode, quality) — see [AiPill].
  Widget _choice(String label, {required bool selected, required VoidCallback onSelected}) =>
      AiPill(label: label, selected: selected, onTap: onSelected);

  /// "① Script ............ v2 · 15s · 3 scenes"
  Widget _step(int n, String title, {String? summary, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AiUi.accent, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'ClashDisplay')),
          const Spacer(),
          if (trailing != null)
            trailing
          else if (summary != null)
            Text(summary, style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
        ],
      ),
    );
  }

  /// The brief and the brand's assets, folded to one line once read; tap to open.
  Widget _briefCard(AiCampaign campaign) {
    final images = campaign.assets.where((a) => a.imageUrl.isNotEmpty).take(3).toList();
    return Container(
      key: const Key('ai-brief-card'),
      decoration: AiUi.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _briefOpen = !_briefOpen),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    for (final a in images)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            a.imageUrl,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(width: 38, height: 38),
                          ),
                        ),
                      ),
                    if (images.isNotEmpty) const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Brand brief & assets',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            campaign.brief.summary,
                            maxLines: _briefOpen ? null : 1,
                            overflow: _briefOpen ? null : TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Icon(_briefOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
            if (_briefOpen) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: AiBrandAssetsRow(assets: campaign.assets)),
          ],
        ),
      ),
    );
  }

  /// Refine · Edit · New script — one row instead of four stacked buttons.
  Widget _scriptActions(AiGeneration selected) {
    Widget action(String label, IconData icon, VoidCallback? onTap, {bool on = false, Key? key}) => Expanded(
      child: OutlinedButton.icon(
        key: key,
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: on ? Colors.white : AiUi.accent),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: on ? AiUi.accent.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.03),
          side: BorderSide(color: on ? AiUi.accent : Colors.white.withValues(alpha: 0.14)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return Row(
      children: [
        action(
          'Refine',
          Icons.auto_awesome_rounded,
          _busy ? null : () => setState(() => _panel = _panel == _ScriptPanel.refine ? _ScriptPanel.none : _ScriptPanel.refine),
          on: _panel == _ScriptPanel.refine,
          key: const Key('ai-script-refine'),
        ),
        const SizedBox(width: 8),
        action('Edit (free)', Icons.edit_outlined, _busy ? null : () => _editScript(selected)),
        const SizedBox(width: 8),
        action(
          'New script',
          Icons.add_rounded,
          _busy ? null : () => setState(() => _panel = _panel == _ScriptPanel.newScript ? _ScriptPanel.none : _ScriptPanel.newScript),
          on: _panel == _ScriptPanel.newScript,
          key: const Key('ai-script-new'),
        ),
      ],
    );
  }

  /// Write a script from scratch (or an idea for the AI): Write with AI, or Use my text.
  List<Widget> _newScriptPanel({required bool first, required AiQuote? scriptQuote}) => [
    _textField(_scriptController, first ? 'Write your script, or an idea for the AI…' : 'Start a new script…', minLines: 4),
    const SizedBox(height: 10),
    AiSecondaryButton(
      label: 'Write with AI',
      price: _priceTag(_aiScriptAction),
      onPressed: _busy || !(scriptQuote?.canAfford ?? false) ? null : _writeWithAi,
    ),
    const SizedBox(height: 8),
    AiSecondaryButton(
      label: 'Use my text',
      price: 'Free',
      icon: Icons.check_rounded,
      onPressed: _busy || _scriptController.text.trim().isEmpty ? null : _useOwnScript,
    ),
  ];

  /// One "label ........ control" line in the Style card.
  Widget _styleRow(String label, Widget control, {String? help}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          control,
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help, style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(AiCampaign campaign, AiWorkspace ws) {
    final scripts = ws.of(AiStage.script).where((g) => g.isDone).toList();
    AiGeneration? selected;
    for (final s in scripts) {
      if (s.id == _scriptId) selected = s;
    }
    final scriptQuote = _quote(_aiScriptAction);
    final work = _work(ws);
    final board = _method == AiGenerationMethod.imagesFirst ? _latestBoard(ws) : null;
    final keyframes = selected == null || selected.scenes.isEmpty ? null : (selected.scenes.length > 4 ? 4 : selected.scenes.length);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _briefCard(campaign),

              // ── 1 Script ──────────────────────────────────────────────────
              _step(
                1,
                'Script',
                summary:
                    selected == null
                        ? null
                        : [
                          'v${selected.versionNumber}',
                          if (_seconds != null) '${_seconds}s',
                          if (selected.scenes.isNotEmpty) '${selected.scenes.length} scenes',
                        ].join(' · '),
              ),
              Row(
                children: [
                  const Text('Length', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('· your script and video are made for it', style: TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _lengthOptions(ws))
                    _choice(
                      '${s}s',
                      selected: s == _seconds,
                      onSelected: () {
                        setState(() => _seconds = s);
                        _refreshQuotes();
                      },
                    ),
                ],
              ),
              if (_seconds != null && _seconds! < ws.format.minDurationSeconds)
                Padding(
                  key: const Key('ai-short-take-hint'),
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'A quick ${_seconds}s first take — the brand wants ${ws.format.minDurationSeconds}–${ws.format.maxDurationSeconds}s, you can extend it before you submit.',
                    style: const TextStyle(color: AiUi.warning, fontSize: 12, height: 1.4),
                  ),
                ),
              const SizedBox(height: 14),
              if (scripts.isEmpty)
                ..._newScriptPanel(first: true, scriptQuote: scriptQuote)
              else ...[
                if (scripts.length > 1) ...[
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final s in scripts.reversed)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _choice(
                              'v${s.versionNumber}',
                              selected: s.id == _scriptId,
                              onSelected: () {
                                setState(() => _selectScript(s));
                                _refreshQuotes();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (selected != null) ...[
                  KeyedSubtree(key: const Key('ai-selected-script'), child: AiScriptView(script: selected)),
                  const SizedBox(height: 10),
                  _scriptActions(selected),
                  if (_panel == _ScriptPanel.refine) ...[
                    const SizedBox(height: 10),
                    _textField(
                      _directionController,
                      'How should the AI change it? e.g. "make it funnier"',
                      minLines: 1,
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 600), () => _quoteFor(_refineAction));
                      },
                    ),
                    const SizedBox(height: 8),
                    AiSecondaryButton(
                      label: 'Refine with AI',
                      price: _priceTag(_refineAction),
                      onPressed:
                          _busy || _directionController.text.trim().isEmpty || !(_quote(_refineAction)?.canAfford ?? false)
                              ? null
                              : _refine,
                    ),
                  ],
                ],
                if (_panel == _ScriptPanel.newScript || selected == null) ...[
                  const SizedBox(height: 10),
                  ..._newScriptPanel(first: false, scriptQuote: scriptQuote),
                ],
              ],

              // ── 2 Style ───────────────────────────────────────────────────
              _step(2, 'Style'),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                decoration: AiUi.cardDecoration(),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _styleRow(
                        'How to make it',
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _choice(
                              'Text to video',
                              selected: _method == AiGenerationMethod.textToVideo,
                              onSelected: () {
                                setState(() => _method = AiGenerationMethod.textToVideo);
                                _quoteFor(_createAction);
                              },
                            ),
                            _choice(
                              'Images first',
                              selected: _method == AiGenerationMethod.imagesFirst,
                              onSelected: () {
                                setState(() => _method = AiGenerationMethod.imagesFirst);
                                _quoteFor(_createAction);
                              },
                            ),
                          ],
                        ),
                        help:
                            _method == AiGenerationMethod.textToVideo
                                ? 'The video is made straight from your script.'
                                : keyframes == null
                                ? 'One keyframe per scene of your script, then make the video.'
                                : '$keyframes keyframes — one per scene — then make the video.',
                      ),
                      if (_method == AiGenerationMethod.textToVideo) ...[
                        if (_resolution != null)
                          KeyedSubtree(
                            key: const Key('ai-quality-set-by-brand'),
                            child: _styleRow(
                              'Quality',
                              Text('$_resolution, set by the brand', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                            ),
                          ),
                        SwitchListTile(
                          key: const Key('ai-onscreen-text'),
                          contentPadding: EdgeInsets.zero,
                          value: _onScreenText,
                          activeThumbColor: AiUi.accent,
                          title: const Text(
                            'Show on-screen text',
                            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Captions and titles from your script. Turn off for a clean video — the voiceover stays.',
                            style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
                          ),
                          onChanged: (v) {
                            setState(() => _onScreenText = v);
                            _quoteFor(_createAction);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (board != null) ...[
                // This script already has a storyboard — open it rather than paying for a new one.
                const SizedBox(height: 10),
                Container(
                  key: const Key('ai-existing-storyboard'),
                  padding: const EdgeInsets.all(12),
                  decoration: AiUi.cardDecoration(),
                  child: Row(
                    children: [
                      for (final url in board.imageUrls.take(4))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              url,
                              width: 34,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(width: 34, height: 60),
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Your storyboard for this script is ready — ${board.label}, ${board.imageUrls.length} images.',
                          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AiSecondaryButton(
                  label: 'Make a new storyboard',
                  icon: Icons.refresh_rounded,
                  price: _createAction == null ? null : (_quote(_createAction) == null ? '…' : '${_quote(_createAction)!.credits} credits'),
                  onPressed: _busy || _scriptId == null || !(_quote(_createAction)?.canAfford ?? false) ? null : _create,
                ),
              ],

              // ── 3 Your images, 4 Your videos ─────────────────────────────
              // Two separate collections, images first (client feedback, 24 Nov).
              for (final (i, (title, items))
                  in [
                    ('Your images', work.where((g) => g.stage == AiStage.image).toList()),
                    ('Your videos', work.where((g) => g.stage == AiStage.video).toList()),
                  ].where((c) => c.$2.isNotEmpty).indexed) ...[
                _step(
                  3 + i,
                  title,
                  trailing: GestureDetector(
                    key: Key('ai-see-all-${title.split(' ').last}'),
                    onTap: _openMyVideos,
                    child: Text(
                      items.length > 6 ? 'See all ${items.length}' : 'See all',
                      style: const TextStyle(color: AiUi.accent, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                _workGrid(items),
              ],
              if (ws.freeEvaluations.limit > 0) ...[
                const SizedBox(height: 16),
                Text(
                  'Getting your ad judged by AI is free — ${ws.freeEvaluations.left} of ${ws.freeEvaluations.limit} left.',
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        _generateBar(ws, board),
      ],
    );
  }

  /// Pinned to the bottom: what will be made, the warnings that block it, and the button.
  Widget _generateBar(AiWorkspace ws, AiGeneration? board) {
    final createQuote = _quote(_createAction);
    final createError = _createAction == null ? null : _quoteErrors[_key(_createAction!)];
    final what =
        _method == AiGenerationMethod.textToVideo
            ? [if (_seconds != null) '${_seconds}s', if (_resolution != null) _resolution!, 'text to video'].join(' · ')
            : 'Images first';
    return Container(
      key: const Key('ai-generate-bar'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AiUi.bg,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_scriptId == null)
              const AiWarningText('Get a script first — write it, or let the AI write it.')
            else if (createError != null)
              AiWarningText(createError)
            else if (createQuote != null && !createQuote.canAfford)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AiWarningText('This costs ${createQuote.credits} credits and you have ${createQuote.creditsLeft}.'),
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: _askForCredits,
                    child: const Text('Ask the brand for more credits'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: Text(what, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
                  Text('${ws.creditsLeft} credits left', style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
                ],
              ),
            const SizedBox(height: 8),
            if (board != null)
              AiPrimaryButton(label: 'Open your storyboard', onPressed: _busy ? null : () => _openGeneration(board))
            else
              AiPrimaryButton(
                label: _priced(_method == AiGenerationMethod.textToVideo ? 'Generate video' : 'Generate images', _createAction),
                busy: _busy,
                onPressed: _scriptId == null || !(createQuote?.canAfford ?? false) ? null : _create,
              ),
          ],
        ),
      ),
    );
  }

  /// The brand's min / middle / max, plus the always-allowed short first take (5s).
  List<int> _lengthOptions(AiWorkspace ws) {
    final f = ws.format;
    final mid = ((f.minDurationSeconds + f.maxDurationSeconds) / 2).round();
    return {
        if (ws.shortClipSeconds > 0 && ws.shortClipSeconds < f.minDurationSeconds) ws.shortClipSeconds,
        f.minDurationSeconds,
        mid,
        f.maxDurationSeconds,
      }.toList()
      ..sort();
  }

  Widget _textField(TextEditingController c, String hint, {int minLines = 4, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      minLines: minLines,
      maxLines: 10,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textFaint),
        filled: true,
        fillColor: AiUi.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AiUi.accent)),
      ),
    );
  }
}
