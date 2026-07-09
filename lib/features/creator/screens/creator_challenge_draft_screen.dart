import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/creator_challenges_service.dart';

/// Create mode when [existingDraft] is null; edit mode otherwise (only
/// allowed by the backend while the draft is DRAFT or CHANGES_REQUESTED —
/// the caller is responsible for only reaching this screen in a valid state).
/// Pops with `true` if a draft was created/updated.
class CreatorChallengeDraftScreen extends StatefulWidget {
  final Map<String, dynamic>? existingDraft;

  const CreatorChallengeDraftScreen({super.key, this.existingDraft});

  @override
  State<CreatorChallengeDraftScreen> createState() => _CreatorChallengeDraftScreenState();
}

class _CreatorChallengeDraftScreenState extends State<CreatorChallengeDraftScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  final _titleCtrl      = TextEditingController();
  final _descCtrl       = TextEditingController();
  final _whatToCopyCtrl = TextEditingController();
  final _timeLimitCtrl  = TextEditingController();
  final _criterionCtrl  = TextEditingController();

  String _difficulty = 'Medium';
  String? _categoryId;
  List<Map<String, dynamic>> _categories = [];
  final List<String> _scoringCriteria = [];

  File? _pickedVideo;
  String? _existingVideoKey;
  bool _loadingCategories = true;
  bool _saving = false;

  static const _difficulties = ['Easy', 'Medium', 'Hard'];

  bool get _isEdit => widget.existingDraft != null;

  @override
  void initState() {
    super.initState();
    final d = widget.existingDraft;
    if (d != null) {
      _titleCtrl.text = d['title'] as String? ?? '';
      _descCtrl.text = d['description'] as String? ?? '';
      _difficulty = (d['difficulty'] as String?)?.isNotEmpty == true ? d['difficulty'] as String : 'Medium';
      _categoryId = (d['categoryId'] as String?)?.isNotEmpty == true ? d['categoryId'] as String : null;
      _existingVideoKey = d['videoKey'] as String?;
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await CreatorChallengesService().fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _loadingCategories = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _whatToCopyCtrl.dispose();
    _timeLimitCtrl.dispose();
    _criterionCtrl.dispose();
    super.dispose();
  }

  void _addCriterion() {
    final text = _criterionCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _scoringCriteria.add(text);
      _criterionCtrl.clear();
    });
  }

  Future<void> _pickVideo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Reference Video',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _option(Icons.videocam_rounded, 'Record', ImageSource.camera),
            const SizedBox(height: 12),
            _option(Icons.video_library_rounded, 'Choose from Gallery', ImageSource.gallery),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    if (picked != null && mounted) {
      setState(() => _pickedVideo = File(picked.path));
    }
  }

  Widget _option(IconData icon, String label, ImageSource source) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _accent, size: 22),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return _snack('Please enter a challenge title');
    if (_categoryId == null) return _snack('Please select a category');
    if (!_isEdit && _pickedVideo == null) return _snack('Please add a reference video');

    setState(() => _saving = true);
    try {
      final service = CreatorChallengesService();
      final timeLimit = int.tryParse(_timeLimitCtrl.text.trim());
      final instructions = <String, dynamic>{
        if (_whatToCopyCtrl.text.trim().isNotEmpty) 'whatToCopy': _whatToCopyCtrl.text.trim(),
        if (timeLimit != null) 'timeLimit': timeLimit,
        if (_scoringCriteria.isNotEmpty) 'scoringCriteria': _scoringCriteria,
      };

      if (_isEdit) {
        await service.updateDraft(
          widget.existingDraft!['id'] as String,
          title: title,
          category: _categoryId,
          difficulty: _difficulty,
          description: _descCtrl.text.trim(),
          challengeInstructions: instructions.isEmpty ? null : instructions,
        );
      } else {
        final uploadData = await service.getReferenceVideoUploadUrl();
        final uploadUrl = uploadData['uploadUrl'] as String;
        final videoKey = uploadData['key'] as String;
        await ApiClient().uploadToS3(uploadUrl, _pickedVideo!, contentType: 'video/mp4');

        await service.createDraft(
          title: title,
          category: _categoryId!,
          difficulty: _difficulty,
          videoKey: videoKey,
          description: _descCtrl.text.trim(),
          challengeInstructions: instructions.isEmpty ? null : instructions,
        );
      }

      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isEdit ? 'Edit Challenge' : 'Create Challenge',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Challenge Title'),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _inputDecor('e.g. Moonwalk Mirror Challenge'),
            ),
            const SizedBox(height: 22),

            _label('Description'),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _inputDecor('Describe what participants need to do…'),
            ),
            const SizedBox(height: 22),

            _label('Category'),
            const SizedBox(height: 6),
            _loadingCategories
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.map((cat) {
                      final id = cat['_id'] as String? ?? '';
                      final name = cat['name'] as String? ?? id;
                      final sel = _categoryId == id;
                      return GestureDetector(
                        onTap: () => setState(() => _categoryId = id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? _accent.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel ? _accent.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.10)),
                          ),
                          child: Text(name,
                              style: TextStyle(
                                  color: sel ? const Color(0xFFD4A8FF) : Colors.white38,
                                  fontSize: 13,
                                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                        ),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 22),

            _label('Difficulty'),
            const SizedBox(height: 10),
            Row(
              children: _difficulties.map((d) {
                final sel = _difficulty == d;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _difficulty = d),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? _accent.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? _accent.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.10)),
                      ),
                      child: Text(d,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: sel ? const Color(0xFFD4A8FF) : Colors.white38,
                              fontSize: 12,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),

            _label('Reference Video'),
            const SizedBox(height: 6),
            if (_isEdit)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.videocam_rounded, color: Colors.white38, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_existingVideoKey ?? 'Uploaded',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                  ],
                ),
              )
            else
              GestureDetector(
                onTap: _pickVideo,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _pickedVideo != null
                            ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _pickedVideo != null ? Icons.check_circle_rounded : Icons.add_a_photo_rounded,
                        color: _pickedVideo != null ? const Color(0xFF22C55E) : Colors.white38,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pickedVideo != null ? 'Video selected — tap to change' : 'Record or upload a reference video',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 22),

            _label('What to Copy  (optional)'),
            const SizedBox(height: 6),
            TextField(
              controller: _whatToCopyCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDecor('e.g. Copy the exact hand movements in the chorus'),
            ),
            const SizedBox(height: 16),

            _label('Time Limit in Seconds  (optional)'),
            const SizedBox(height: 6),
            TextField(
              controller: _timeLimitCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDecor('e.g. 30'),
            ),
            const SizedBox(height: 16),

            _label('Scoring Criteria  (optional)'),
            const SizedBox(height: 6),
            if (_scoringCriteria.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _scoringCriteria.asMap().entries.map((e) {
                    return Chip(
                      label: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: _card,
                      deleteIconColor: Colors.white38,
                      onDeleted: () => setState(() => _scoringCriteria.removeAt(e.key)),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                    );
                  }).toList(),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _criterionCtrl,
                    onSubmitted: (_) => _addCriterion(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _inputDecor('e.g. Sync to beat'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _addCriterion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent.withValues(alpha: 0.25),
                      foregroundColor: const Color(0xFFD4A8FF),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: _accent.withValues(alpha: 0.40))),
                    ),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : Text(_isEdit ? 'Save Changes' : 'Save Draft'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600));

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        filled: true,
        fillColor: _card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent, width: 1.5)),
      );
}
