import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import 'my_ai_videos_screen.dart';

/// Where an invited creator reads the brand brief and assets, writes a script
/// and starts generating an AI video. Generation is asynchronous: starting it
/// spends credits and returns immediately.
class CreateAiVideosScreen extends StatefulWidget {
  final String brandId;

  const CreateAiVideosScreen({super.key, required this.brandId});

  @override
  State<CreateAiVideosScreen> createState() => _CreateAiVideosScreenState();
}

class _CreateAiVideosScreenState extends State<CreateAiVideosScreen> {
  static const _bg = AppColors.background;
  static const _accent = AppColors.accent;
  static const _card = Color(0xFF0E0E1A);

  final _service = AiAdsService();
  final _scriptController = TextEditingController();

  AiAdBrief? _brief;
  int _credits = 0;
  bool _loading = true;
  bool _submitting = false;
  AiGenerationMethod _method = AiGenerationMethod.textToVideo;

  @override
  void initState() {
    super.initState();
    _scriptController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.fetchBrief(widget.brandId),
      _service.fetchCredits(widget.brandId),
    ]);
    if (!mounted) return;
    setState(() {
      _brief = results[0] as AiAdBrief;
      _credits = results[1] as int;
      _loading = false;
    });
  }

  int get _cost => AiAdsService.costs.firstStepCost(_method);
  bool get _outOfCredits => _credits < _cost;
  bool get _canSubmit =>
      !_submitting && !_outOfCredits && _scriptController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await _service.startGeneration(
        brandId: widget.brandId,
        prompt: _scriptController.text.trim(),
        method: _method,
      );
      final balance = await _service.fetchCredits(widget.brandId);
      if (!mounted) return;
      setState(() {
        _credits = balance;
        _submitting = false;
      });
      _scriptController.clear();
      _toast(
        _method == AiGenerationMethod.textToVideo
            ? 'Your video is being generated. You can leave this screen.'
            : 'Your images are being generated. You can leave this screen.',
        action: SnackBarAction(
          label: 'View',
          textColor: AppColors.accentLight,
          onPressed: _openMyVideos,
        ),
      );
    } on OutOfAiCreditsException {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('You are out of credits');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('Something went wrong. Please try again.');
    }
  }

  void _toast(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _openMyVideos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyAiVideosScreen(brandId: widget.brandId),
      ),
    );
    // Image/video steps on the next screens spend credits.
    final balance = await _service.fetchCredits(widget.brandId);
    if (mounted) setState(() => _credits = balance);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Create AI Videos',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'ClashDisplay',
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'My AI videos',
            icon: const Icon(Icons.video_library_outlined),
            onPressed: _openMyVideos,
          ),
          if (!_loading) _creditsChip(),
          const SizedBox(width: 12),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(color: _accent))
              : _buildBody(_brief!),
    );
  }

  Widget _creditsChip() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              '$_credits credits',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AiAdBrief brief) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _sectionTitle('Brand brief'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Text(
            brief.brief,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
        _sectionTitle('Brand assets'),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: brief.assets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _assetTile(brief.assets[i]),
          ),
        ),
        _sectionTitle('Your script'),
        TextField(
          controller: _scriptController,
          minLines: 5,
          maxLines: 10,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Write your script or prompt for the video…',
            hintStyle: const TextStyle(color: AppColors.textFaint),
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _accent),
            ),
          ),
        ),
        _sectionTitle('How do you want to create it?'),
        _methodOption(
          AiGenerationMethod.textToVideo,
          Icons.movie_creation_outlined,
          'Text to video',
          'Generate the video straight from your script',
          AiAdsService.costs.video,
        ),
        const SizedBox(height: 10),
        _methodOption(
          AiGenerationMethod.imagesFirst,
          Icons.image_outlined,
          'Images first',
          'Generate images, then turn them into a video',
          AiAdsService.costs.image,
        ),
        const SizedBox(height: 20),
        if (_outOfCredits)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'You are out of credits',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFFF6B6B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _canSubmit ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _accent.withValues(alpha: 0.3),
              disabledForegroundColor: Colors.white54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child:
                _submitting
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : Text(
                      _method == AiGenerationMethod.textToVideo
                          ? 'Generate video · $_cost credits'
                          : 'Generate images · $_cost credits',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
  );

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFamily: 'ClashDisplay',
        ),
      ),
    );
  }

  Widget _assetTile(AiBrandAsset asset) {
    return Container(
      width: 104,
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (asset.imageUrl.isNotEmpty)
            Image.network(asset.imageUrl, fit: BoxFit.cover)
          else
            const Center(
              child: Icon(Icons.image_outlined, color: Colors.white24, size: 32),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(
              asset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodOption(
    AiGenerationMethod method,
    IconData icon,
    String title,
    String subtitle,
    int cost,
  ) {
    final selected = _method == method;
    return GestureDetector(
      onTap: () => setState(() => _method = method),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.15) : _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                selected ? _accent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$cost cr',
              style: const TextStyle(
                color: AppColors.accentLight,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
