import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_dialogs.dart';
import '../widgets/ai_script_view.dart';
import '../widgets/ai_ui.dart';
import 'ai_brand_assets_row.dart';
import 'ai_video_detail_screen.dart';
import 'my_ai_videos_screen.dart';

/// The creator's workspace in one campaign: read the brief and the brand's
/// assets, get a script (write it with AI, refine it, or use your own), then
/// generate the video — straight from the script, or images first.
///
/// Every paid action shows its exact price (a backend quote) on the button;
/// tapping the button is the confirmation, and the server never charges more
/// than that price.
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

  String? _scriptId;
  AiGenerationMethod _method = AiGenerationMethod.textToVideo;
  int? _seconds;
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
      final results = await Future.wait([
        _service.fetchCampaign(widget.campaignId),
        _service.fetchWorkspace(widget.campaignId),
      ]);
      if (!mounted) return;
      final ws = results[1] as AiWorkspace;
      final scripts = ws.of(AiStage.script).where((g) => g.isDone).toList();
      setState(() {
        _campaign = results[0] as AiCampaign;
        _workspace = ws;
        _loading = false;
        _scriptId ??= scripts.isEmpty ? null : scripts.last.id;
        _seconds ??= ws.format.minDurationSeconds;
        _resolution ??= ws.prices.resolutions.contains('720p')
            ? '720p'
            : (ws.prices.resolutions.isEmpty ? null : ws.prices.resolutions.first);
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
  AiAction get _aiScriptAction =>
      AiAction(stage: AiStage.script, instructions: _scriptController.text, durationSeconds: _seconds);

  AiAction? get _refineAction => _scriptId == null
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
        ? AiAction(stage: AiStage.video, scriptId: _scriptId, durationSeconds: _seconds, resolution: _resolution)
        : AiAction(stage: AiStage.image, scriptId: _scriptId, imageCount: 4);
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

  Future<void> _openMyVideos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyAiVideosScreen(campaignId: widget.campaignId)),
    );
    if (mounted) _load();
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ws = _workspace;
    return Scaffold(
      backgroundColor: AiUi.bg,
      appBar: AiUi.appBar(
        'Create AI Videos',
        actions: [
          IconButton(tooltip: 'My AI videos', icon: const Icon(Icons.video_library_outlined), onPressed: _openMyVideos),
          if (ws != null) AiCreditsChip(credits: ws.creditsLeft),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
          : ws == null || _campaign == null
          ? Center(child: Text(_error ?? 'Not available', style: const TextStyle(color: AppColors.textMuted)))
          : _buildBody(_campaign!, ws),
    );
  }

  Widget _buildBody(AiCampaign campaign, AiWorkspace ws) {
    final scripts = ws.of(AiStage.script).where((g) => g.isDone).toList();
    AiGeneration? selected;
    for (final s in scripts) {
      if (s.id == _scriptId) selected = s;
    }
    final scriptQuote = _quote(_aiScriptAction);
    final createQuote = _quote(_createAction);
    final createError = _createAction == null ? null : _quoteErrors[_key(_createAction!)];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (ws.freeEvaluations.limit > 0)
          Text(
            'Getting your ad judged by AI is free — ${ws.freeEvaluations.left} of ${ws.freeEvaluations.limit} left.',
            style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
          ),
        const AiSectionTitle('Brand brief'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AiUi.cardDecoration(),
          child: Text(campaign.brief.summary, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45)),
        ),
        const AiSectionTitle('Brand assets'),
        AiBrandAssetsRow(assets: campaign.assets),

        AiSectionTitle(
          'Length',
          trailing: Text('Your script and video are made for this', style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final s in _lengthOptions(ws))
              ChoiceChip(
                label: Text('${s}s'),
                selected: s == _seconds,
                onSelected: (_) {
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
              'A quick ${_seconds}s first take — the brand wants ${ws.format.minDurationSeconds}–${ws.format.maxDurationSeconds}s, so extend it before you submit.',
              style: const TextStyle(color: AiUi.warning, fontSize: 12, height: 1.4),
            ),
          ),
        AiSectionTitle('Your script', trailing: scripts.isEmpty ? null : Text('${scripts.length} version${scripts.length == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.textFaint, fontSize: 11))),
        if (scripts.isNotEmpty) ...[
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in scripts.reversed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('v${s.versionNumber}'),
                      selected: s.id == _scriptId,
                      onSelected: (_) {
                        setState(() => _selectScript(s));
                        _refreshQuotes();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 10),
            KeyedSubtree(key: const Key('ai-selected-script'), child: AiScriptView(script: selected)),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _editScript(selected!),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit (free)'),
                ),
              ],
            ),
            _textField(_directionController, 'How should the AI change it? e.g. "make it funnier"', minLines: 1, onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 600), () => _quoteFor(_refineAction));
            }),
            const SizedBox(height: 8),
            AiSecondaryButton(
              label: 'Refine with AI',
              price: _priceTag(_refineAction),
              onPressed: _busy || _directionController.text.trim().isEmpty || !(_quote(_refineAction)?.canAfford ?? false) ? null : _refine,
            ),
            const SizedBox(height: 14),
          ],
        ],
        _textField(_scriptController, scripts.isEmpty ? 'Write your script, or an idea for the AI…' : 'Start a new script…', minLines: 4),
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

        const AiSectionTitle('How do you want to create it?'),
        _methodOption(AiGenerationMethod.textToVideo, Icons.movie_creation_outlined, 'Text to video', 'Generate the video straight from your script'),
        const SizedBox(height: 10),
        _methodOption(AiGenerationMethod.imagesFirst, Icons.image_outlined, 'Images first', 'Generate 4 keyframes, pick the best, then make the video'),
        if (_method == AiGenerationMethod.textToVideo) ...[
          if (ws.prices.resolutions.length > 1) ...[
            const AiSectionTitle('Quality'),
            Wrap(
              spacing: 8,
              children: [
                for (final r in ws.prices.resolutions)
                  ChoiceChip(
                    label: Text(r),
                    selected: r == _resolution,
                    onSelected: (_) {
                      setState(() => _resolution = r);
                      _quoteFor(_createAction);
                    },
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 20),
        if (_scriptId == null)
          const AiWarningText('Get a script first — write it, or let the AI write it.')
        else if (createError != null)
          AiWarningText(createError)
        else if (createQuote != null && !createQuote.canAfford) ...[
          AiWarningText(
            'This costs ${createQuote.credits} credits and you have ${createQuote.creditsLeft}.',
          ),
          TextButton(onPressed: _askForCredits, child: const Text('Ask the brand for more credits')),
        ],
        AiPrimaryButton(
          label: _priced(_method == AiGenerationMethod.textToVideo ? 'Generate video' : 'Generate images', _createAction),
          busy: _busy,
          onPressed: _scriptId == null || !(createQuote?.canAfford ?? false) ? null : _create,
        ),
      ],
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
    }.toList()..sort();
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AiUi.accent)),
      ),
    );
  }

  Widget _methodOption(AiGenerationMethod method, IconData icon, String title, String subtitle) {
    final selected = _method == method;
    return GestureDetector(
      onTap: () {
        setState(() => _method = method);
        _quoteFor(_createAction);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AiUi.cardDecoration(selected: selected),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: AiUi.accent, size: 20),
          ],
        ),
      ),
    );
  }
}
