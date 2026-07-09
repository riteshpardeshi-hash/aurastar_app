import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/reference_data_service.dart';
import 'rules_screen.dart';

class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  static const _purple = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  final _refService = ReferenceDataService();

  static const _categories = [
    {'name': 'Dance',   'asset': 'assets/images/your interest/Asset 89.png'},
    {'name': 'Fashion', 'asset': 'assets/images/your interest/Asset 90.png'},
    {'name': 'Comedy',  'asset': 'assets/images/your interest/Asset 91.png'},
    {'name': 'Fitness', 'asset': 'assets/images/your interest/Asset 92.png'},
    {'name': 'Sports',  'asset': 'assets/images/your interest/Asset 93.png'},
    {'name': 'Skill',   'asset': 'assets/images/your interest/Asset 94.png'},
  ];

  final Set<String> _selected = {};
  Map<String, String> _nameToId = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    try {
      final interests = await _refService.fetchInterests();
      if (!mounted) return;
      setState(() {
        _nameToId = {
          for (final i in interests)
            (i['name'] as String).toLowerCase(): i['id'] as String,
        };
      });
    } catch (_) {}
  }

  Future<void> _continue() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one interest')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ids = _selected
          .map((name) => _nameToId[name.toLowerCase()] ?? name)
          .toList();
      await _refService.saveInterests(ids);
    } catch (_) {
      // Non-fatal: navigate regardless if API isn't ready yet.
    }
    if (!mounted) return;
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

                      // ── Interest grid ──────────────────────────────────────
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.55,
                        ),
                        itemCount: _categories.length,
                        itemBuilder: (_, i) {
                          final cat = _categories[i];
                          final name = cat['name']!;
                          final asset = cat['asset']!;
                          final selected = _selected.contains(name);

                          return GestureDetector(
                            onTap: () => setState(() {
                              selected
                                  ? _selected.remove(name)
                                  : _selected.add(name);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? _purple
                                      : Colors.transparent,
                                  width: 2,
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color:
                                              _purple.withValues(alpha: 0.50),
                                          blurRadius: 14,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(asset, fit: BoxFit.cover),
                                    if (!selected)
                                      Container(
                                        color: Colors.black
                                            .withValues(alpha: 0.38),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

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
}
