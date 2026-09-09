import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/reference_data_service.dart';
import 'rules_screen.dart';

class InterestsScreen extends StatefulWidget {
  /// When true, this screen is being reopened from Settings to fix an
  /// already-broken profile rather than during first-time onboarding:
  /// pre-fills current selections, pops back to the caller on success
  /// instead of chaining into RulesScreen, and shows a back button.
  final bool isEditMode;

  const InterestsScreen({super.key, this.isEditMode = false});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  static const _purple = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  final _refService = ReferenceDataService();

  // Real interests fetched from GET /interests — the old build used a fixed
  // 6-category grid (Dance/Fashion/Comedy/Fitness/Sports/Skill) that never
  // matched any real backend interest name, so every selection silently sent
  // an invalid id and PATCH /profile/interests always failed. Driving the
  // grid from the live catalog and selecting by real id fixes that at the
  // source instead of guessing a name mapping.
  List<Map<String, dynamic>> _interests = [];
  bool _loading = true;

  final Set<String> _selected = {};
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    setState(() => _loading = true);
    final interests = await _refService.fetchInterests();
    if (!mounted) return;
    setState(() {
      _interests = interests.where((i) => i['isActive'] != false).toList();
      _loading = false;
    });
    if (widget.isEditMode) await _prefillFromProfile();
  }

  // Edit mode only — pre-select whichever real interests the user's profile
  // already has, matched by id (the profile's `interests` are full Interest
  // objects, same shape as GET /interests).
  Future<void> _prefillFromProfile() async {
    final profile = await AuthApiService().getProfile();
    if (!mounted || profile == null) return;
    final interests = profile['interests'] as List?;
    if (interests == null) return;
    final savedIds = interests
        .map((i) => ((i as Map)['id'] as String?) ??
            (i['_id'] as String?) ??
            '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (!mounted) return;
    setState(() => _selected.addAll(savedIds));
  }

  Future<void> _continue() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one interest')),
      );
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await _refService.saveInterests(_selected.toList());
    } catch (e) {
      // Interests must actually be saved server-side — the backend marks a
      // profile complete only once country + city + interests are all set.
      // Silently continuing past a failure here left users stuck with an
      // incomplete profile and no way to tell why uploads failed later.
      if (!mounted) return;
      final reason = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _saving = false;
        _errorText = 'Failed to save your interests: $reason';
      });
      return;
    }
    if (!mounted) return;
    if (widget.isEditMode) {
      Navigator.pop(context, true);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RulesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              // ── Scrollable body ────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    children: [
                      if (widget.isEditMode) ...[
                        SizedBox(height: size.height * 0.02),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_back_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: size.height * 0.06),

                      // ── Title (asset includes text + underline) ────────────
                      Image.asset(
                        'assets/images/your interest/Asset 86.png',
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                      ),
                      const SizedBox(height: 18),

                      // ── Subtitles ──────────────────────────────────────────
                      Image.asset(
                        'assets/images/your interest/Asset 87.png',
                        fit: BoxFit.fitWidth,
                      ),
                      const SizedBox(height: 8),
                      Image.asset(
                        'assets/images/your interest/Asset 88.png',
                        fit: BoxFit.fitWidth,
                      ),

                      SizedBox(height: size.height * 0.045),

                      // ── Interest chips ──────────────────────────────────────
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: _purple)),
                        )
                      else if (_interests.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Column(
                            children: [
                              Text(
                                "Couldn't load interests. Please try again.",
                                style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.55),
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: _loadInterests,
                                child: const Text('Retry',
                                    style: TextStyle(color: _purple)),
                              ),
                            ],
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children:
                              _interests.map(_interestChip).toList(),
                        ),

                      if (_errorText != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _errorText!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13),
                        ),
                      ],

                      SizedBox(height: size.height * 0.055),

                      // ── Continue button ────────────────────────────────────
                      GestureDetector(
                        onTap: _saving ? null : _continue,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _saving
                                  ? [
                                      Colors.grey.shade800,
                                      Colors.grey.shade700
                                    ]
                                  : const [
                                      Color(0xFF9B4DCA),
                                      Color(0xFF5A189A)
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _saving
                                ? null
                                : [
                                    BoxShadow(
                                      color: _purple.withValues(alpha: 0.45),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    )
                                  ],
                          ),
                          child: Center(
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _interestChip(Map<String, dynamic> interest) {
    final id = interest['id'] as String;
    final name = interest['name'] as String? ?? '';
    final icon = interest['icon'] as String?;
    final selected = _selected.contains(id);

    return GestureDetector(
      onTap: () => setState(() {
        selected ? _selected.remove(id) : _selected.add(id);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _purple.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: selected ? _purple : Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.40),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _interestIcon(icon),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                color:
                    selected ? Colors.white : Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _interestIcon(String? icon) {
    if (icon == null || icon.isEmpty) {
      return const Icon(Icons.star_rounded, color: Colors.white54, size: 16);
    }
    if (icon.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          icon,
          width: 18,
          height: 18,
          errorBuilder: (_, __, ___) => const Icon(Icons.star_rounded,
              color: Colors.white54, size: 16),
        ),
      );
    }
    // Backend also returns plain emoji strings (e.g. "🎮") for some entries.
    return Text(icon, style: const TextStyle(fontSize: 16));
  }
}
