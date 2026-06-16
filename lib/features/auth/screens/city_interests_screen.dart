import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'rules_screen.dart';

class CityInterestsScreen extends StatefulWidget {
  const CityInterestsScreen({super.key});

  @override
  State<CityInterestsScreen> createState() => _CityInterestsScreenState();
}

class _CityInterestsScreenState extends State<CityInterestsScreen> {
  static const _purple = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  final _cityCtrl = TextEditingController();
  final Set<String> _selectedInterests = {};
  bool _saving = false;

  static const _quickCities = [
    'Mumbai', 'Delhi', 'Bengaluru', 'Hyderabad', 'Chennai',
    'Kolkata', 'Pune', 'Ahmedabad', 'Jaipur', 'Surat',
  ];

  static const _categories = <String, ({IconData icon, Color color})>{
    'Dance':   (icon: Icons.music_note_rounded,        color: Color(0xFF4B6EF6)),
    'Fitness': (icon: Icons.fitness_center_rounded,    color: Color(0xFF22C55E)),
    'Fashion': (icon: Icons.checkroom_rounded,         color: Color(0xFFFF6B9D)),
    'Sports':  (icon: Icons.sports_basketball_rounded, color: Color(0xFFF97316)),
    'Comedy':  (icon: Icons.mood_rounded,              color: Color(0xFFEAB308)),
    'Skill':   (icon: Icons.psychology_rounded,        color: Color(0xFF06B6D4)),
  };

  @override
  void dispose() {
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'city': _cityCtrl.text.trim(),
        'interests': _selectedInterests.toList(),
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RulesScreen()),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')),
      );
    }
  }

  void _tapCity(String city) {
    setState(() => _cityCtrl.text = city);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Purple radial glow
            Positioned(
              top: -60,
              left: size.width * 0.5 - 180,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _purple.withValues(alpha: 0.30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Step indicator ───────────────────────────────────────
                    Row(
                      children: List.generate(4, (i) {
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          width: i == 1 ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == 1
                                ? _purple
                                : Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    SizedBox(height: size.height * 0.04),

                    // ── Title ────────────────────────────────────────────────
                    const Text(
                      'Personalise\nyour feed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Help us show you the right challenges',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                      ),
                    ),

                    SizedBox(height: size.height * 0.042),

                    // ── City input ───────────────────────────────────────────
                    _label('YOUR CITY'),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _cityCtrl.text.isNotEmpty
                              ? _purple.withValues(alpha: 0.60)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: TextField(
                        controller: _cityCtrl,
                        onChanged: (_) => setState(() {}),
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        cursorColor: _purple,
                        decoration: InputDecoration(
                          hintText: 'Enter your city',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.30),
                              fontSize: 15),
                          prefixIcon: Icon(Icons.location_city_rounded,
                              color: Colors.white.withValues(alpha: 0.35),
                              size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Quick-pick cities ────────────────────────────────────
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _quickCities.map((city) {
                        final selected = _cityCtrl.text.trim() == city;
                        return GestureDetector(
                          onTap: () => _tapCity(city),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _purple.withValues(alpha: 0.20)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? _purple
                                    : Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              city,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.50),
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    SizedBox(height: size.height * 0.045),

                    // ── Interests ────────────────────────────────────────────
                    _label('YOUR INTERESTS'),
                    const SizedBox(height: 6),
                    Text(
                      'Select all that apply',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 12),
                    ),
                    const SizedBox(height: 14),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.4,
                      ),
                      itemCount: _categories.length,
                      itemBuilder: (context, i) {
                        final name = _categories.keys.elementAt(i);
                        final meta = _categories.values.elementAt(i);
                        final selected = _selectedInterests.contains(name);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedInterests.remove(name);
                            } else {
                              _selectedInterests.add(name);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: selected
                                  ? meta.color.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? meta.color
                                    : Colors.white.withValues(alpha: 0.10),
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(meta.icon,
                                    color: selected
                                        ? meta.color
                                        : Colors.white.withValues(alpha: 0.35),
                                    size: 24),
                                const SizedBox(height: 6),
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.40),
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                                if (selected)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(Icons.check_circle_rounded,
                                        color: meta.color, size: 14),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    SizedBox(height: size.height * 0.05),

                    // ── Continue button ───────────────────────────────────────
                    GestureDetector(
                      onTap: _saving ? null : _continue,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _saving
                                ? [Colors.grey.shade800, Colors.grey.shade700]
                                : const [Color(0xFF9B4DCA), Color(0xFF5A189A)],
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

                    const SizedBox(height: 16),

                    // ── Skip ────────────────────────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: _saving
                            ? null
                            : () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const RulesScreen()),
                                ),
                        child: Text(
                          'Skip for now',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 14,
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
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.50),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      );
}
