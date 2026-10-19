import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/utils/error_message.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/challenge_create_flow.dart';
import '../../../core/models/creator_rubric.dart';
import '../../../core/services/category_store.dart';
import '../../../core/services/creator_challenges_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/reference_video_preview.dart';
import '../widgets/scoring_criteria_panel.dart';
import 'creator_challenge_status_screen.dart' show SubmissionRulesDialog;

/// Create mode when [existingDraft] is null; edit mode otherwise (only
/// allowed by the backend while the draft is DRAFT, CHANGES_REQUESTED or
/// REJECTED — the caller is responsible for only reaching this screen in a
/// valid state).
///
/// Everything happens on this one page (backend ADR 137): the creator fills
/// in the challenge, watches their reference video, generates the scoring
/// criteria (which saves the draft first), asks the AI for changes or edits
/// them, then submits for admin approval. "Save as draft" finishes later.
/// Pops with `true` if a draft was created, updated or submitted.
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

  String _difficulty = 'Medium';
  String? _categoryId;
  List<Map<String, dynamic>> _categories = [];

  /// Set once the challenge exists on the server (always in edit mode).
  String? _challengeId;
  String _status = 'DRAFT';
  String? _remoteVideoUrl;
  CreatorRubric? _rubric;
  bool _rubricBusy = false;
  bool _savedSomething = false;
  final _panelKey = GlobalKey<ScoringCriteriaPanelState>();
  String? _createdId;

  File? _pickedVideo;
  bool _loadingCategories = true;
  String? _categoriesError;
  bool _saving = false;
  // What the save button says while saving — creating runs a slow AI check on the video.
  String _savingLabel = '';
  // Kept across Save taps so a retry after a lost answer reuses the uploaded video instead of
  // creating a duplicate challenge (see ChallengeCreateFlow).
  late final ChallengeCreateFlow _createFlow = ChallengeCreateFlow(
    presign: () async {
      final data = await CreatorChallengesService().getReferenceVideoUploadUrl();
      return ChallengeVideoUpload(uploadUrl: data['uploadUrl'] as String, videoId: data['videoId'] as String);
    },
    upload: (url, video, onProgress) => ApiClient().uploadToS3(url, video, contentType: 'video/mp4', onProgress: onProgress),
    create: (videoId) async {
      final created = await CreatorChallengesService().createDraft(
        title: _titleCtrl.text.trim(),
        category: _categoryId!,
        difficulty: _difficulty,
        videoId: videoId,
        description: _descCtrl.text.trim(),
        challengeInstructions: _instructionsPayload(),
      );
      _createdId = created['_id'] as String?;
    },
  );

  static const _difficulties = ['Easy', 'Medium', 'Hard'];

  bool get _isEdit => widget.existingDraft != null;
  bool get _isResubmit => _status == 'CHANGES_REQUESTED' || _status == 'REJECTED';
  bool get _busy => _saving || _rubricBusy;

  @override
  void initState() {
    super.initState();
    final d = widget.existingDraft;
    if (d != null) {
      _titleCtrl.text = d['title'] as String? ?? '';
      _descCtrl.text = d['description'] as String? ?? '';
      _difficulty = (d['difficulty'] as String?)?.isNotEmpty == true ? d['difficulty'] as String : 'Medium';
      _categoryId = (d['categoryId'] as String?)?.isNotEmpty == true ? d['categoryId'] as String : null;
      _challengeId = (d['id'] as String?)?.isNotEmpty == true ? d['id'] as String : null;
      _status = d['submissionStatus'] as String? ?? 'DRAFT';
      if (_challengeId != null) _loadExisting(_challengeId!);
    }
    // Saved categories render on the first frame; _loadCategories refreshes them.
    final saved = CategoryStore.instance.peek();
    if (saved != null && saved.isNotEmpty) {
      _categories = saved;
      _loadingCategories = false;
    }
    _loadCategories();
  }

  /// Edit mode: the playable video URL and the instructions the normalised
  /// draft passed in doesn't carry.
  Future<void> _loadExisting(String id) async {
    final service = CreatorChallengesService();
    final results = await Future.wait([service.fetchPreview(id), service.fetchDraft(id)]);
    if (!mounted) return;
    final preview = results[0];
    final instructions = results[1]?['challengeInstructions'] as Map<String, dynamic>?;
    setState(() {
      _remoteVideoUrl = preview?['videoUrl'] as String?;
      if (instructions != null) {
        _whatToCopyCtrl.text = instructions['whatToCopy'] as String? ?? '';
        final limit = instructions['timeLimit'];
        if (limit != null) _timeLimitCtrl.text = '$limit';
      }
    });
  }

  /// Loads the category chips from [CategoryStore]: saved on the device, so
  /// they usually appear at once (see [initState]); the store retries a
  /// dropped connection itself. On failure the creator gets a clear message
  /// and a Try again button instead of a raw error.
  Future<void> _loadCategories({bool forceRefresh = false}) async {
    if (mounted && (_categoriesError != null || forceRefresh)) {
      setState(() {
        _categoriesError = null;
        _loadingCategories = _categories.isEmpty;
      });
    }
    try {
      final cats = await CategoryStore.instance.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loadingCategories = false;
        if (cats.isEmpty) _categoriesError = 'No categories are available right now.';
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[CreateChallenge] failed to load categories: $e');
      setState(() {
        _categoriesError = e is CategoryLoadException || isNetworkError(e)
            ? 'We couldn\'t load the categories. Check your connection and try again.'
            : 'We couldn\'t load the categories. ${humanizeError(e)}';
        _loadingCategories = false;
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _whatToCopyCtrl.dispose();
    _timeLimitCtrl.dispose();
    super.dispose();
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
    final picked = await ImagePicker().pickVideo(source: source);
    if (picked != null && mounted) {
      setState(() => _pickedVideo = File(picked.path));
      _createFlow.reset();
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

  /// The first missing required field, as a message, or null.
  String? _missingField() {
    if (_titleCtrl.text.trim().isEmpty) return 'Please enter a challenge title';
    if (_categoryId == null) return 'Please select a category';
    if (_challengeId == null && _pickedVideo == null) return 'Please add a reference video';
    return null;
  }

  /// Creates the draft (uploading the video) the first time, otherwise saves
  /// the current details so the AI and the admin see what's on screen.
  /// Returns the challenge id, or null after telling the creator what failed.
  Future<String?> _ensureSaved(void Function(String label) onProgress) async {
    final missing = _missingField();
    if (missing != null) {
      _snack(missing);
      return null;
    }
    var step = 'save the challenge';
    try {
      if (_challengeId == null) {
        final outcome = await _createFlow.run(
          _pickedVideo!,
          onStep: (s) {
            step = s;
            onProgress(switch (s) {
              'request the video upload' => 'Preparing upload…',
              'upload the reference video' => 'Uploading video… 0%',
              _ => 'Checking your video… this can take a minute',
            });
          },
          onUploadProgress: (p) => onProgress('Uploading video… ${(p * 100).round()}%'),
        );
        _savedSomething = true;
        if (outcome == ChallengeCreateOutcome.createdEarlier || _createdId == null) {
          // The challenge exists but its id was lost with the earlier answer.
          _snack('Your challenge was saved. Open it from My Challenges to continue.');
          if (mounted) Navigator.pop(context, true);
          return null;
        }
        if (mounted) setState(() => _challengeId = _createdId);
      } else {
        onProgress('Saving your changes…');
        await CreatorChallengesService().updateDraft(
          _challengeId!,
          title: _titleCtrl.text.trim(),
          category: _categoryId,
          difficulty: _difficulty,
          description: _descCtrl.text.trim(),
          challengeInstructions: _instructionsPayload(),
        );
        _savedSomething = true;
      }
      return _challengeId;
    } catch (e) {
      debugPrint('[CreateChallenge] failed to $step: $e');
      // An admin retired the chosen category since the list was saved: refresh
      // the list and ask for another one, rather than a bare "not found".
      if (humanizeError(e).toLowerCase().contains('category not found')) {
        await CategoryStore.instance.invalidate();
        if (mounted) setState(() => _categoryId = null);
        _loadCategories(forceRefresh: true);
        _snack('That category is no longer available. Please pick another one.');
        return null;
      }
      _snack("Couldn't $step. ${humanizeError(e)}");
      return null;
    }
  }

  Future<void> _saveAsDraft() async {
    if (_panelKey.currentState?.isEditing == true) {
      return _snack('Save or cancel your scoring-criteria edits first');
    }
    setState(() => _saving = true);
    final id = await _ensureSaved((label) {
      if (mounted) setState(() => _savingLabel = label);
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savingLabel = '';
    });
    if (id == null) return;
    _snack('Draft saved');
    Navigator.pop(context, true);
  }

  /// Scoring criteria are required (backend ADR 137). Without them, offer to
  /// generate them here first; otherwise the backend creates them on submit.
  /// Returns false when the creator chose to generate and review them first.
  Future<bool> _confirmScoring() async {
    if (_rubric?.hasRubric == true) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Scoring criteria needed',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
            'Players are scored with your challenge\'s scoring criteria. Generate and review them first, or let AI create them as part of submitting.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'ai'),
            child: const Text('Let AI create them', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'generate'),
            child: const Text('Generate & review', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (choice == 'generate') {
      await _panelKey.currentState?.generate();
      return false;
    }
    return choice == 'ai';
  }

  Future<void> _submit() async {
    if (_panelKey.currentState?.isEditing == true) {
      return _snack('Save or cancel your scoring-criteria edits first');
    }
    final missing = _missingField();
    if (missing != null) return _snack(missing);
    final rubric = _rubric;
    if (rubric != null && !rubric.addsUp) {
      return _snack('Your scoring criteria add up to ${rubric.totalPoints} points instead of '
          '${rubric.rules.totalPoints}. Edit them or ask the AI for new ones first.');
    }
    if (!await _confirmScoring()) return;
    if (!mounted) return;

    if (!_isResubmit) {
      final rules = await CreatorChallengesService().fetchSubmissionRules();
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => SubmissionRulesDialog(rules: rules),
      );
      if (accepted != true || !mounted) return;
    }

    setState(() => _saving = true);
    final id = await _ensureSaved((label) {
      if (mounted) setState(() => _savingLabel = label);
    });
    if (id == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (mounted) {
      setState(() => _savingLabel = _rubric?.hasRubric == true
          ? 'Submitting…'
          : 'Creating scoring criteria and submitting…');
    }
    try {
      final service = CreatorChallengesService();
      _isResubmit ? await service.resubmit(id) : await service.submit(id);
      if (!mounted) return;
      _snack(_isResubmit ? 'Resubmitted for approval' : 'Submitted for approval');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _savingLabel = '';
      });
      _snack("Couldn't submit. ${humanizeError(e)}");
    }
  }

  Map<String, dynamic>? _instructionsPayload() {
    final timeLimit = int.tryParse(_timeLimitCtrl.text.trim());
    final instructions = <String, dynamic>{
      if (_whatToCopyCtrl.text.trim().isNotEmpty) 'whatToCopy': _whatToCopyCtrl.text.trim(),
      if (timeLimit != null) 'timeLimit': timeLimit,
    };
    return instructions.isEmpty ? null : instructions;
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
    // Back returns `true` once anything was saved so the caller refreshes, and
    // is blocked while an upload / AI call is running.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        Navigator.pop(context, _savedSomething);
      },
      child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isEdit ? 'Edit Challenge' : 'Create Challenge'),
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
                : _categoriesError != null
                ? _categoriesErrorCard()
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
                                  color: sel ? const Color(0xFFD4A8FF) : AppColors.textFaint,
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
                              color: sel ? const Color(0xFFD4A8FF) : AppColors.textFaint,
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
            _referenceVideo(),
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

            const Text('Scoring Criteria',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'How every player\'s attempt is scored. Generate them from your video, then review, ask the AI for changes or edit them yourself. The admin reviews them with your challenge.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            ScoringCriteriaPanel(
              key: _panelKey,
              challengeId: _challengeId,
              ensureSaved: _ensureSaved,
              onChanged: (rubric) => setState(() => _rubric = rubric),
              onBusyChanged: (busy) => setState(() => _rubricBusy = busy),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                key: const Key('submit-for-approval'),
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                child: _saving
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                          if (_savingLabel.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                _savingLabel,
                                key: const Key('create-challenge-progress'),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      )
                    : Text(_isResubmit ? 'Resubmit for Approval' : 'Submit for Approval'),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                key: const Key('save-as-draft'),
                onPressed: _busy ? null : _saveAsDraft,
                child: const Text('Save as draft and finish later',
                    style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _categoriesErrorCard() => Container(
        key: const Key('categories-error'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFFFCA5A5), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_categoriesError!,
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, height: 1.35)),
            ),
            TextButton(
              key: const Key('categories-retry'),
              onPressed: () => _loadCategories(forceRefresh: true),
              child: const Text('Try again',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _referenceVideo() {
    // New challenge, video picked: watch it; it can be swapped until the draft is saved.
    if (_pickedVideo != null) {
      return Column(
        children: [
          ReferenceVideoPreview(file: _pickedVideo),
          const SizedBox(height: 6),
          if (_challengeId == null)
            TextButton.icon(
              onPressed: _busy ? null : _pickVideo,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFFD4A8FF)),
              label: const Text('Change video', style: TextStyle(color: Color(0xFFD4A8FF))),
            )
          else
            const Text('Uploaded with your draft',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
        ],
      );
    }
    // Editing a saved challenge: play the uploaded video.
    if (_challengeId != null) {
      if (_remoteVideoUrl != null && _remoteVideoUrl!.isNotEmpty) {
        return ReferenceVideoPreview(url: _remoteVideoUrl);
      }
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: const Row(
          children: [
            Icon(Icons.videocam_rounded, color: Colors.white38, size: 20),
            SizedBox(width: 10),
            Text('Loading your video…', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _pickVideo,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: const Column(
          children: [
            Icon(Icons.add_a_photo_rounded, color: Colors.white38, size: 28),
            SizedBox(height: 8),
            Text('Record or upload a reference video',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600));

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
