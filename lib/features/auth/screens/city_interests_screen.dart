import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/reference_data_service.dart';
import 'rules_screen.dart';

class CityInterestsScreen extends StatefulWidget {
  const CityInterestsScreen({super.key});

  @override
  State<CityInterestsScreen> createState() => _CityInterestsScreenState();
}

class _CityInterestsScreenState extends State<CityInterestsScreen> {
  static const _purple = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  final _refService = ReferenceDataService();

  // Reference data
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _cities = [];
  List<Map<String, dynamic>> _interests = [];

  // Selections
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedCity;
  final Set<String> _selectedInterestIds = {};

  bool _loadingCountries = true;
  bool _loadingCities = false;
  bool _loadingInterests = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        _refService.fetchCountries(),
        _refService.fetchInterests(),
      ]);
      if (!mounted) return;
      setState(() {
        _countries = results[0];
        _interests = results[1];
        _loadingCountries = false;
        _loadingInterests = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCountries = false;
        _loadingInterests = false;
      });
    }
  }

  Future<void> _loadCities(String countryId) async {
    setState(() {
      _loadingCities = true;
      _cities = [];
      _selectedCity = null;
    });
    try {
      final cities = await _refService.fetchCities(countryId);
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _loadingCities = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCities = false);
    }
  }

  Future<void> _continue() async {
    if (_selectedCountry == null) {
      _showSnack('Please select your country');
      return;
    }
    if (_selectedCity == null) {
      _showSnack('Please select your city');
      return;
    }
    if (_selectedInterestIds.isEmpty) {
      _showSnack('Please select at least one interest');
      return;
    }

    setState(() => _saving = true);
    try {
      await _refService.saveCountry(_selectedCountry!['id'] as String);
      await _refService.saveCity(_selectedCity!['id'] as String);
      await _refService.saveInterests(_selectedInterestIds.toList());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RulesScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('Failed to save. Please try again.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openCountryPicker() {
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet(
        title: 'Select Country',
        items: _countries,
        labelKey: 'name',
        icon: Icons.flag_rounded,
      ),
    ).then((picked) {
      if (picked == null) return;
      setState(() => _selectedCountry = picked);
      _loadCities(picked['id'] as String);
    });
  }

  void _openCityPicker() {
    if (_selectedCountry == null) {
      _showSnack('Please select a country first');
      return;
    }
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet(
        title: 'Select City',
        items: _cities,
        labelKey: 'name',
        icon: Icons.location_city_rounded,
      ),
    ).then((picked) {
      if (picked != null) setState(() => _selectedCity = picked);
    });
  }

  Map<String, List<Map<String, dynamic>>> get _groupedInterests {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final interest in _interests) {
      final cat = interest['category'] as String? ?? 'Other';
      map.putIfAbsent(cat, () => []).add(interest);
    }
    return map;
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
            Positioned(
              top: -60,
              left: size.width * 0.5 - 180,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_purple.withValues(alpha: 0.30), Colors.transparent],
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
                    Row(
                      children: List.generate(4, (i) => Container(
                        margin: const EdgeInsets.only(right: 6),
                        width: i == 1 ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == 1 ? _purple : Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )),
                    ),
                    SizedBox(height: size.height * 0.04),
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
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
                    ),
                    SizedBox(height: size.height * 0.042),

                    // ── Country ──────────────────────────────────────────────
                    _label('YOUR COUNTRY'),
                    const SizedBox(height: 10),
                    _loadingCountries
                        ? _loadingRow()
                        : _pickerTile(
                            icon: Icons.flag_rounded,
                            value: _selectedCountry?['name'] as String?,
                            hint: 'Select your country',
                            onTap: _openCountryPicker,
                          ),

                    const SizedBox(height: 20),

                    // ── City ─────────────────────────────────────────────────
                    _label('YOUR CITY'),
                    const SizedBox(height: 10),
                    _loadingCities
                        ? _loadingRow()
                        : _pickerTile(
                            icon: Icons.location_city_rounded,
                            value: _selectedCity?['name'] as String?,
                            hint: _selectedCountry == null
                                ? 'Select country first'
                                : 'Select your city',
                            onTap: _openCityPicker,
                          ),

                    SizedBox(height: size.height * 0.045),

                    // ── Interests ────────────────────────────────────────────
                    _label('YOUR INTERESTS'),
                    const SizedBox(height: 6),
                    Text(
                      'Select all that apply',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                    ),
                    const SizedBox(height: 14),

                    if (_loadingInterests)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: _purple),
                        ),
                      )
                    else
                      ..._groupedInterests.entries.map((entry) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.40),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: entry.value.map((interest) {
                              final id = interest['id'] as String;
                              final name = interest['name'] as String;
                              final selected = _selectedInterestIds.contains(id);
                              return GestureDetector(
                                onTap: () => setState(() {
                                  if (selected) {
                                    _selectedInterestIds.remove(id);
                                  } else {
                                    _selectedInterestIds.add(id);
                                  }
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _purple.withValues(alpha: 0.22)
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected ? _purple : Colors.white.withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (selected) ...[
                                        const Icon(Icons.check_circle_rounded,
                                            color: _purple, size: 14),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        name,
                                        style: TextStyle(
                                          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.50),
                                          fontSize: 13,
                                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          SizedBox(height: size.height * 0.025),
                        ],
                      )),

                    SizedBox(height: size.height * 0.04),

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
                              : [BoxShadow(color: _purple.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Center(
                      child: GestureDetector(
                        onTap: _saving
                            ? null
                            : () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const RulesScreen()),
                                ),
                        child: Text(
                          'Skip for now',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14),
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

  Widget _loadingRow() => Container(
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(color: _purple, strokeWidth: 2),
          ),
        ),
      );

  Widget _pickerTile({
    required IconData icon,
    required String? value,
    required String hint,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: value != null
                  ? _purple.withValues(alpha: 0.60)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.35), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value ?? hint,
                  style: TextStyle(
                    color: value != null ? Colors.white : Colors.white.withValues(alpha: 0.30),
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withValues(alpha: 0.35), size: 22),
            ],
          ),
        ),
      );
}

// ── Reusable searchable picker sheet ──────────────────────────────────────────

class _SearchPickerSheet extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final String labelKey;
  final IconData icon;

  const _SearchPickerSheet({
    required this.title,
    required this.items,
    required this.labelKey,
    required this.icon,
  });

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  static const _purple = Color(0xFF7B2CBF);
  final _searchCtrl = TextEditingController();
  late List<Map<String, dynamic>> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? widget.items
          : widget.items
              .where((item) => (item[widget.labelKey] as String)
                  .toLowerCase()
                  .contains(q.toLowerCase()))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(
              children: [
                Icon(widget.icon, color: _purple, size: 20),
                const SizedBox(width: 10),
                Text(
                  widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.60), size: 16),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearch,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: _purple,
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.30), fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.35), size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No results found',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (_, i) {
                      final item = _filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          item[widget.labelKey] as String,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: _purple, size: 18),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
