import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../dashboard/dashboard.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const _purple = Color(0xFF7B2CBF);

  final _pageCtrl = PageController();
  int _page = 0;

  // City state
  String? _city;
  String _cityQuery = '';
  final _citySearch = TextEditingController();

  // Interests state
  final Set<String> _interests = {};

  // Referral code (optional)
  final _referralCodeCtrl = TextEditingController();

  bool _saving = false;

  static const _cities = [
    'Mumbai', 'Delhi NCR', 'Bengaluru', 'Pune', 'Hyderabad',
    'Chennai', 'Kolkata', 'Ahmedabad', 'Surat', 'Jaipur',
    'Lucknow', 'Kochi', 'Nagpur', 'Chandigarh', 'Bhopal',
    'Indore', 'Patna', 'Vadodara', 'Guwahati', 'Coimbatore',
  ];

  static const _zones = [
    (label: 'Meme',    icon: Icons.tag_faces_rounded,      color: Color(0xFFFF6B6B)),
    (label: 'Drama',   icon: Icons.theater_comedy_rounded, color: Color(0xFFFF9F43)),
    (label: 'Move',    icon: Icons.directions_run_rounded, color: Color(0xFF54A0FF)),
    (label: 'Sound',   icon: Icons.music_note_rounded,     color: Color(0xFF5F27CD)),
    (label: 'Animal',  icon: Icons.pets_rounded,           color: Color(0xFF01CBC6)),
    (label: 'Fitness', icon: Icons.fitness_center_rounded, color: Color(0xFF00D2D3)),
  ];

  static const _perms = [
    (icon: Icons.videocam_outlined,       title: 'Camera',         body: 'Record your challenge attempts',              color: Color(0xFF54A0FF)),
    (icon: Icons.mic_outlined,            title: 'Microphone',     body: 'Sound match is part of your Aura score',     color: Color(0xFFFF6B6B)),
    (icon: Icons.photo_library_outlined,  title: 'Photo Library',  body: 'Save and share your best plays',             color: Color(0xFF5F27CD)),
    (icon: Icons.notifications_outlined,  title: 'Notifications',  body: 'Get rank alerts and reward updates',         color: Color(0xFFFF9F43)),
  ];

  @override
  void initState() {
    super.initState();
    _loadPendingReferralCode();
  }

  Future<void> _loadPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('pending_referral_code') ?? '';
    if (code.isNotEmpty && mounted) {
      _referralCodeCtrl.text = code;
    }
  }

  List<String> get _filteredCities => _cityQuery.isEmpty
      ? _cities
      : _cities
          .where((c) => c.toLowerCase().contains(_cityQuery.toLowerCase()))
          .toList();

  void _goTo(int page) {
    setState(() => _page = page);
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final prefs = await SharedPreferences.getInstance();

    try {
      final manualCode = _referralCodeCtrl.text.trim().toUpperCase();
      final deepLinkCode = prefs.getString('pending_referral_code') ?? '';

      // Validate manually-entered code before saving anything
      if (manualCode.isNotEmpty) {
        final referrerId = await _lookupReferrerId(uid, manualCode);
        if (referrerId == null) {
          if (mounted) setState(() => _saving = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Referral code not found. Clear it to continue.'),
                backgroundColor: Colors.redAccent,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        // Valid — save city/interests then apply
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'city': _city ?? '',
          'interests': _interests.toList(),
          'referredBy': referrerId,
        });
        await FirebaseFirestore.instance.collection('users').doc(referrerId).update({
          'referralCount': FieldValue.increment(1),
        });
        await prefs.remove('pending_referral_code');
      } else {
        // No manual code — save city/interests, apply deep-link code if present
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'city': _city ?? '',
          'interests': _interests.toList(),
        });
        if (deepLinkCode.isNotEmpty) {
          final referrerId = await _lookupReferrerId(uid, deepLinkCode);
          if (referrerId != null) {
            await FirebaseFirestore.instance.collection('users').doc(uid).update({
              'referredBy': referrerId,
            });
            await FirebaseFirestore.instance.collection('users').doc(referrerId).update({
              'referralCount': FieldValue.increment(1),
            });
          }
          await prefs.remove('pending_referral_code');
        }
      }
    } catch (_) {
      // network error — proceed without referral
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'city': _city ?? '',
        'interests': _interests.toList(),
      }).catchError((_) {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Dashboard()),
      (_) => false,
    );
  }

  /// Returns referrer UID if code is valid, null otherwise.
  Future<String?> _lookupReferrerId(String uid, String code) async {
    try {
      // Already referred — skip
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if ((userDoc.data()?['referredBy'] as String? ?? '').isNotEmpty) return null;

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('referralCode', isEqualTo: code)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;

      final referrerId = snap.docs.first.id;
      return referrerId == uid ? null : referrerId; // can't refer yourself
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _citySearch.dispose();
    _referralCodeCtrl.dispose();
    super.dispose();
  }

  // ── Step dots ───────────────────────────────────────────────────────────────

  Widget _dots() => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final active = i == _page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 6),
            width: active ? 28 : 8,
            height: 4,
            decoration: BoxDecoration(
              color: i <= _page
                  ? _purple
                  : Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      );

  // ── Shared button ───────────────────────────────────────────────────────────

  Widget _btn({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool loading = false,
  }) =>
      GestureDetector(
        onTap: (enabled && !loading) ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: enabled ? _purple : Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _purple.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      );

  // ── Page 1 — Choose City ────────────────────────────────────────────────────

  Widget _cityPage() {
    final cities = _filteredCities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dots(),
        const SizedBox(height: 20),
        const Text(
          'Choose City',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Local fame starts here',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
        ),
        const SizedBox(height: 20),
        // Search
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: TextField(
            controller: _citySearch,
            onChanged: (v) => setState(() => _cityQuery = v),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            cursorColor: _purple,
            decoration: InputDecoration(
              hintText: 'Search city...',
              hintStyle:
                  TextStyle(color: Colors.white.withValues(alpha: 0.30), fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.35), size: 20),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // City list
        Expanded(
          child: cities.isEmpty
              ? Center(
                  child: Text('No city found',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 14)),
                )
              : ListView.separated(
                  itemCount: cities.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                  itemBuilder: (_, i) {
                    final c = cities[i];
                    final sel = _city == c;
                    return ListTile(
                      onTap: () => setState(() => _city = c),
                      contentPadding: const EdgeInsets.symmetric(vertical: 2),
                      title: Text(
                        c,
                        style: TextStyle(
                          color: sel
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.75),
                          fontSize: 16,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      trailing: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: sel ? _purple : Colors.transparent,
                          shape: BoxShape.circle,
                          border: sel
                              ? null
                              : Border.all(
                                  color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: sel
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                            : null,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        _btn(
          label: 'Continue',
          enabled: _city != null,
          onTap: () => _goTo(1),
        ),
      ],
    );
  }

  // ── Page 2 — Aura Zones ─────────────────────────────────────────────────────

  Widget _interestsPage() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dots(),
          const SizedBox(height: 20),
          const Text(
            'Aura Zones',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick your interests — your feed will match',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.5,
              physics: const NeverScrollableScrollPhysics(),
              children: _zones.map((z) {
                final sel = _interests.contains(z.label);
                return GestureDetector(
                  onTap: () => setState(() {
                    sel
                        ? _interests.remove(z.label)
                        : _interests.add(z.label);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: sel
                          ? _purple.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: sel
                            ? _purple
                            : Colors.white.withValues(alpha: 0.12),
                        width: sel ? 2 : 1,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                  color: _purple.withValues(alpha: 0.22),
                                  blurRadius: 10)
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: z.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(z.icon,
                              color: sel
                                  ? z.color
                                  : z.color.withValues(alpha: 0.55),
                              size: 20),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          z.label,
                          style: TextStyle(
                            color: sel
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.65),
                            fontSize: 14,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          _btn(
            label: _interests.isEmpty
                ? 'Pick at least one'
                : 'Continue  (${_interests.length} selected)',
            enabled: _interests.isNotEmpty,
            onTap: () => _goTo(2),
          ),
        ],
      );

  // ── Page 3 — Permissions ────────────────────────────────────────────────────

  Widget _permissionsPage() => SingleChildScrollView(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dots(),
          const SizedBox(height: 20),
          const Text(
            'Permissions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Needed for scoring and rewards',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
          ),
          const SizedBox(height: 28),
          Column(
              children: _perms
                  .map(
                    (p) => Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: p.color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child:
                                Icon(p.icon, color: p.color, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.title,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(p.body,
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Icon(Icons.check_circle_rounded,
                              color: _purple.withValues(alpha: 0.70),
                              size: 20),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 20),
          // ── Optional referral code ──────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.group_add_rounded,
                  color: _purple.withValues(alpha: 0.70), size: 16),
              const SizedBox(width: 8),
              Text(
                'Got a referral code? (Optional)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: TextField(
              controller: _referralCodeCtrl,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                letterSpacing: 2,
                fontFamily: 'SpaceGrotesk',
              ),
              cursorColor: _purple,
              decoration: InputDecoration(
                hintText: 'e.g. X7KP2M9Q',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 13,
                  letterSpacing: 0,
                  fontFamily: 'SpaceGrotesk',
                ),
                prefixIcon: Icon(Icons.loyalty_rounded,
                    color: Colors.white.withValues(alpha: 0.35), size: 20),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _btn(
            label: 'Enable & Start Playing',
            enabled: true,
            loading: _saving,
            onTap: _finish,
          ),
          const SizedBox(height: 12),
        ],
      ),
      );

  // ── Root build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Subtle purple glow top-right
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _purple.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: _cityPage(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: _interestsPage(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: _permissionsPage(),
                ),
              ],
            ),

            // Back button (pages 1 & 2)
            if (_page > 0)
              Positioned(
                top: 16,
                right: 24,
                child: GestureDetector(
                  onTap: () => _goTo(_page - 1),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_back_rounded,
                        color: Colors.white.withValues(alpha: 0.70), size: 20),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
