import 'package:flutter/material.dart';
import '../../../core/models/creator_rubric.dart';
import '../../../core/services/creator_challenges_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/theme/app_colors.dart';

/// Saves the challenge if it doesn't exist yet and returns its id, or null when
/// it couldn't (the caller has already told the creator why). [onProgress]
/// reports what is happening, e.g. "Uploading video… 40%".
typedef EnsureChallengeSaved = Future<String?> Function(void Function(String label) onProgress);

/// The scoring criteria every player is judged on, inline (backend ADR 137):
/// generate them with AI, ask the AI for changes, or edit names, descriptions
/// and points by hand. Used on the create/edit page — where the challenge may
/// not be saved yet, so [ensureSaved] saves it first — and on the standalone
/// scoring screen. Renders a Column; the parent scrolls.
class ScoringCriteriaPanel extends StatefulWidget {
  /// Null until the challenge is saved.
  final String? challengeId;
  final EnsureChallengeSaved? ensureSaved;

  /// Called whenever the criteria are loaded or change.
  final ValueChanged<CreatorRubric?>? onChanged;

  /// Called when generating/saving starts or stops, so the parent can disable
  /// its own buttons meanwhile.
  final ValueChanged<bool>? onBusyChanged;

  /// Injectable for widget tests.
  final CreatorChallengesService? service;

  const ScoringCriteriaPanel({
    super.key,
    required this.challengeId,
    this.ensureSaved,
    this.onChanged,
    this.onBusyChanged,
    this.service,
  });

  @override
  State<ScoringCriteriaPanel> createState() => ScoringCriteriaPanelState();
}

class ScoringCriteriaPanelState extends State<ScoringCriteriaPanel> {
  static const _card = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);
  static const _ok = Color(0xFF22C55E);
  static const _warn = Color(0xFFF59E0B);

  late final CreatorChallengesService _service = widget.service ?? CreatorChallengesService();

  String? _challengeId;
  CreatorRubric? _rubric;
  String? _loadError;
  bool _loading = false;
  bool _generating = false;
  bool _saving = false;
  String _busyLabel = '';

  /// The editable working copy; null while not editing.
  List<RubricCategory>? _draft;
  final List<TextEditingController> _nameCtrls = [];
  final List<TextEditingController> _descCtrls = [];

  RubricRules get _rules => _rubric?.rules ?? const RubricRules();

  static const _emptyRubric = CreatorRubric(
    hasRubric: false,
    editable: true,
    source: null,
    referenceDescription: null,
    fixedCategories: [],
    categories: [],
    bonusRules: [],
    rules: RubricRules(),
  );
  bool get busy => _generating || _saving;
  CreatorRubric? get rubric => _rubric;

  /// True while the creator has unsaved edits open.
  bool get isEditing => _draft != null;

  @override
  void initState() {
    super.initState();
    _challengeId = widget.challengeId;
    if (_challengeId != null) _load();
  }

  @override
  void didUpdateWidget(ScoringCriteriaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.challengeId != null && widget.challengeId != _challengeId) {
      _challengeId = widget.challengeId;
      _load();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in [..._nameCtrls, ..._descCtrls]) {
      c.dispose();
    }
    _nameCtrls.clear();
    _descCtrls.clear();
  }

  void _setRubric(CreatorRubric? rubric) {
    setState(() => _rubric = rubric);
    widget.onChanged?.call(rubric);
  }

  void _setBusy(bool generating, bool saving, [String label = '']) {
    final was = busy;
    setState(() {
      _generating = generating;
      _saving = saving;
      _busyLabel = label;
    });
    if (was != busy) widget.onBusyChanged?.call(busy);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rubric = await _service.fetchRubric(_challengeId!);
      if (!mounted) return;
      setState(() => _loading = false);
      _setRubric(rubric);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'We couldn\'t load the scoring criteria. ${humanizeError(e)}';
        _loading = false;
      });
    }
  }

  /// Saves the challenge first when needed. Returns the id, or null.
  Future<String?> _ensureId() async {
    if (widget.ensureSaved != null) {
      final id = await widget.ensureSaved!((label) {
        if (mounted) setState(() => _busyLabel = label);
      });
      if (id != null) _challengeId = id;
      return id;
    }
    return _challengeId;
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  /// Generates (or regenerates with [notes]) the criteria, saving the challenge first if needed.
  Future<void> generate({String? notes}) async {
    _setBusy(true, false, 'Saving your challenge…');
    try {
      final id = await _ensureId();
      if (id == null) return;
      if (mounted) setState(() => _busyLabel = 'Watching your video and writing the scoring criteria…');
      final rubric = await _service.generateRubric(id, notes: notes);
      if (!mounted) return;
      _stopEditing();
      _setRubric(rubric);
      _snack('Scoring criteria ready — review them below, ask the AI for changes or edit them.');
    } catch (e) {
      if (mounted) _snack(_friendly(e));
    } finally {
      if (mounted) _setBusy(false, false);
    }
  }

  Future<void> _askForChanges() async {
    final notes = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12102A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RegenerateSheet(
        inputDecor: _inputDecor('e.g. Focus more on the landing, less on speed'),
        buttonStyle: _primaryStyle(),
      ),
    );
    if (notes != null) await generate(notes: notes);
  }

  void _startEditing({bool fromScratch = false}) {
    final source = fromScratch
        ? _rules.blankCategories(_rules.minCategories)
        : List<RubricCategory>.from(_rubric?.categories ?? const []);
    _disposeControllers();
    for (final c in source) {
      _nameCtrls.add(TextEditingController(text: c.name));
      _descCtrls.add(TextEditingController(text: c.description ?? ''));
    }
    setState(() => _draft = source);
  }

  void _stopEditing() {
    _disposeControllers();
    setState(() => _draft = null);
  }

  List<RubricCategory> _currentDraft() => [
        for (var i = 0; i < _draft!.length; i++)
          _draft![i].copyWith(name: _nameCtrls[i].text, description: _descCtrls[i].text),
      ];

  void _addCategory() {
    setState(() {
      _draft = [..._currentDraft(), RubricCategory(name: '', maxPoints: _rules.minPoints)];
      _nameCtrls.add(TextEditingController());
      _descCtrls.add(TextEditingController());
    });
  }

  void _removeCategory(int i) {
    setState(() {
      final next = _currentDraft()..removeAt(i);
      _nameCtrls.removeAt(i).dispose();
      _descCtrls.removeAt(i).dispose();
      _draft = next;
    });
  }

  void _changePoints(int i, int delta) {
    final c = _draft![i];
    final next = (c.maxPoints + delta).clamp(_rules.minPoints, _rules.maxPoints);
    setState(() => _draft![i] = c.copyWith(maxPoints: next));
  }

  Future<void> _save() async {
    final categories = _currentDraft();
    final problem = (_rubric ?? _emptyRubric).validateEdits(categories);
    if (problem != null) {
      _snack(problem);
      return;
    }
    _setBusy(false, true, 'Saving…');
    try {
      final id = await _ensureId();
      if (id == null) return;
      final rubric = await _service.updateRubric(id, categories);
      if (!mounted) return;
      _stopEditing();
      _setRubric(rubric);
      _snack('Scoring criteria saved');
    } catch (e) {
      if (mounted) _snack(_friendly(e));
    } finally {
      if (mounted) _setBusy(false, false);
    }
  }

  String _friendly(Object e) {
    if (e.toString().contains('TimeoutException')) {
      return 'This is taking longer than usual. Check back in a minute.';
    }
    return humanizeError(e);
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

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }
    if (_loadError != null) {
      return Column(
        children: [
          Text(_loadError!, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted)),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }
    if (busy && _draft == null) return _busyState();

    // Not saved yet: nothing to load, the criteria can still be generated or written.
    final rubric = _rubric ?? _emptyRubric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_draft != null)
          ..._editor()
        else if (!rubric.hasRubric)
          ..._emptyState(rubric)
        else
          ..._readView(rubric),
      ],
    );
  }

  Widget _busyState() => Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: _cardDecor(border: _accent.withValues(alpha: 0.45)),
        child: Column(
          children: [
            const CircularProgressIndicator(color: _accent),
            const SizedBox(height: 16),
            Text(_busyLabel.isEmpty ? 'Working…' : _busyLabel,
                key: const Key('scoring-busy-label'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('This can take up to a minute. Keep the app open.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ],
        ),
      );

  List<Widget> _emptyState(CreatorRubric rubric) => [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecor(border: _warn.withValues(alpha: 0.4)),
          child: const Row(
            children: [
              Icon(Icons.rule_folder_outlined, color: _warn, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Players are scored out of 100 using these criteria. Generate them from your reference video, then review and adjust them before you submit.',
                  style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (rubric.editable) ...[
          _primaryButton('Generate scoring criteria', () => generate(), icon: Icons.auto_awesome),
          const SizedBox(height: 10),
          _outlineButton('Write my own', () => _startEditing(fromScratch: true)),
        ],
      ];

  List<Widget> _readView(CreatorRubric rubric) => [
        Row(
          children: [
            _sourceBadge(rubric.source),
            const Spacer(),
            Text('Out of ${rubric.totalPoints}',
                key: const Key('rubric-total'),
                style: TextStyle(
                    color: rubric.addsUp ? AppColors.textFaint : _warn,
                    fontSize: 12,
                    fontWeight: rubric.addsUp ? FontWeight.w400 : FontWeight.w700)),
          ],
        ),
        if (!rubric.addsUp) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('rubric-total-warning'),
            padding: const EdgeInsets.all(12),
            decoration: _cardDecor(border: _warn.withValues(alpha: 0.5)),
            child: Text(
              'These criteria add up to ${rubric.totalPoints} points instead of ${_rules.totalPoints}. '
              'Edit them or ask the AI for new ones before you submit.',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 10),
        for (final c in rubric.categories) _categoryCard(c),
        const SizedBox(height: 6),
        _fixedSection(rubric),
        if (rubric.editable) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _outlineButton('Ask AI for changes', _askForChanges, icon: Icons.auto_awesome)),
              const SizedBox(width: 10),
              Expanded(child: _outlineButton('Edit', () => _startEditing(), icon: Icons.edit_outlined)),
            ],
          ),
        ],
      ];

  List<Widget> _editor() {
    final draft = _draft!;
    // Shown out of 100 — the score a perfect attempt gets: the fixed
    // categories + the creator's categories + the bonus.
    final total = (_rubric ?? _emptyRubric).totalWith(draft);
    final target = _rules.totalPoints;
    final balanced = total == target;
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: _cardDecor(border: (balanced ? _ok : _warn).withValues(alpha: 0.45)),
        child: Row(
          children: [
            Icon(balanced ? Icons.check_circle_outline : Icons.error_outline,
                color: balanced ? _ok : _warn, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                balanced
                    ? 'Scored out of $target (${_rules.fixedPoints} always scored + ${_rules.categoryPointsTotal} yours + ${_rules.bonusMaxPoints} bonus)'
                    : total < target
                        ? '${target - total} points left to assign'
                        : '${total - target} points over — take some away',
                style: TextStyle(color: balanced ? _ok : _warn, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            Text('$total / $target',
                key: const Key('points-total'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < draft.length; i++) _editableCard(i),
      if (draft.length < _rules.maxCategories)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : _addCategory,
            icon: const Icon(Icons.add, color: Color(0xFFD4A8FF)),
            label: const Text('Add category', style: TextStyle(color: Color(0xFFD4A8FF))),
          ),
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _outlineButton('Cancel', busy ? null : _stopEditing)),
          const SizedBox(width: 10),
          Expanded(child: _primaryButton(_saving ? 'Saving…' : 'Save criteria', busy ? null : _save)),
        ],
      ),
    ];
  }

  Widget _editableCard(int i) {
    final c = _draft![i];
    final canRemove = _draft!.length > _rules.minCategories;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecor(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('category-name-$i'),
                  controller: _nameCtrls[i],
                  maxLength: _rules.nameMaxLength,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  decoration: _inputDecor('Category name').copyWith(counterText: ''),
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Remove category',
                  onPressed: busy ? null : () => _removeCategory(i),
                  icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('category-description-$i'),
            controller: _descCtrls[i],
            maxLength: _rules.descriptionMaxLength,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDecor('What should the judge look for? (optional)').copyWith(counterText: ''),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Points', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
              const Spacer(),
              _stepButton(Icons.remove, c.maxPoints > _rules.minPoints ? () => _changePoints(i, -1) : null,
                  key: Key('points-minus-$i')),
              SizedBox(
                width: 40,
                child: Text('${c.maxPoints}',
                    key: Key('points-$i'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              _stepButton(Icons.add, c.maxPoints < _rules.maxPoints ? () => _changePoints(i, 1) : null,
                  key: Key('points-plus-$i')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap, {Key? key}) => InkWell(
        key: key,
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: onTap == null ? 0.03 : 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: onTap == null ? Colors.white24 : Colors.white),
        ),
      );

  Widget _categoryCard(RubricCategory c) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: _cardDecor(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                Text('${c.maxPoints} pts',
                    style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
            if ((c.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(c.description!,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
            ],
          ],
        ),
      );

  Widget _fixedSection(CreatorRubric rubric) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Always scored',
                style: TextStyle(color: AppColors.textFaint, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final c in rubric.fixedCategories) _fixedRow(c.name, '${c.maxPoints} pts'),
            if (rubric.bonusRules.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Bonus',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final b in rubric.bonusRules) _fixedRow(b.description, '+${b.maxPoints}'),
            ],
          ],
        ),
      );

  Widget _fixedRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ],
        ),
      );

  Widget _sourceBadge(String? source) {
    final mine = source == 'manual';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mine ? Icons.edit_note : Icons.auto_awesome, size: 14, color: const Color(0xFFD4A8FF)),
          const SizedBox(width: 6),
          Text(mine ? 'Edited by you' : 'Generated by AI',
              style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  BoxDecoration _cardDecor({Color? border}) => BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border ?? Colors.white.withValues(alpha: 0.08)),
      );

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent),
        ),
      );

  ButtonStyle _primaryStyle() => ElevatedButton.styleFrom(
        backgroundColor: _accent,
        disabledBackgroundColor: _accent.withValues(alpha: 0.5),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _primaryButton(String label, VoidCallback? onTap, {IconData? icon}) => SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          onPressed: onTap,
          style: _primaryStyle(),
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _outlineButton(String label, VoidCallback? onTap, {IconData? icon}) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
}

/// Owns its text controller so it outlives the sheet's closing animation.
class _RegenerateSheet extends StatefulWidget {
  final InputDecoration inputDecor;
  final ButtonStyle buttonStyle;

  const _RegenerateSheet({required this.inputDecor, required this.buttonStyle});

  @override
  State<_RegenerateSheet> createState() => _RegenerateSheetState();
}

class _RegenerateSheetState extends State<_RegenerateSheet> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask AI for changes',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'Tell the AI what to change. It rewrites the criteria, replacing your edits.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('regenerate-notes'),
              controller: _notes,
              maxLength: 500,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: widget.inputDecor,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _notes.text),
                style: widget.buttonStyle,
                child: const Text('Regenerate', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
}
