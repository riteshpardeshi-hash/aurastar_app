import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/reference_data_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'interests_screen.dart';

class CityInterestsScreen extends StatefulWidget {
  /// When true, this screen is being reopened from Settings to fix an
  /// already-broken profile rather than during first-time onboarding:
  /// pre-fills current selections, pops back to the caller on success
  /// instead of chaining into InterestsScreen, and shows a back button.
  final bool isEditMode;

  const CityInterestsScreen({super.key, this.isEditMode = false});

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

  // Selections
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedCity;

  bool _loadingCountries = true;
  bool _loadingCities = false;
  bool _saving = false;
  String? _errorText;

  // Bumped on every _loadCities call so a slow/out-of-order response from a
  // country the user has since changed away from can't clobber _cities with
  // a list that no longer matches _selectedCountry (which would let a city
  // from the wrong country get selected and saved, and the backend rejects
  // cityId/countryId mismatches).
  int _citiesRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final countries = await _refService.fetchCountries();
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _loadingCountries = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCountries = false);
    }
    if (widget.isEditMode) await _prefillFromProfile();
  }

  // Edit mode only — pre-fill with the user's currently-saved country/city
  // so they see what's actually stored server-side, not a blank form.
  Future<void> _prefillFromProfile() async {
    final profile = await AuthApiService().getProfile();
    if (!mounted || profile == null) return;
    // /profile nests these as {_id, name, ...} — normalise to 'id' since
    // that's the key _continue()/the pickers expect everywhere else.
    final rawCountry = profile['country'] as Map<String, dynamic>?;
    final rawCity = profile['city'] as Map<String, dynamic>?;
    final country = rawCountry == null
        ? null
        : {...rawCountry, 'id': rawCountry['id'] ?? rawCountry['_id']};
    final city = rawCity == null
        ? null
        : {...rawCity, 'id': rawCity['id'] ?? rawCity['_id']};
    if (country != null) {
      setState(() => _selectedCountry = country);
      await _loadCities(country['id'] as String,
          countryCode: country['code'] as String?);
    }
    if (!mounted || city == null) return;
    setState(() => _selectedCity = city);
  }

  Future<void> _loadCities(String countryId, {String? countryCode}) async {
    final requestId = ++_citiesRequestId;
    setState(() {
      _loadingCities = true;
      _cities = [];
      _selectedCity = null;
    });
    try {
      final cities =
          await _refService.fetchCities(countryId, countryCode: countryCode);
      if (!mounted || requestId != _citiesRequestId) return;
      setState(() {
        _cities = cities;
        _loadingCities = false;
      });
    } catch (_) {
      if (!mounted || requestId != _citiesRequestId) return;
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

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await _refService.saveCountry(_selectedCountry!['id'] as String);
      await _refService.saveCity(_selectedCity!['id'] as String);
      // PATCH /profile/country resets city to null server-side as a side
      // effect (confirmed even when the country value is unchanged), so a
      // success response from both calls doesn't guarantee city actually
      // stuck — re-read the profile and confirm before trusting it.
      final profile = await AuthApiService().getProfile();
      final savedCityId = (profile?['city']
              as Map<String, dynamic>?)?['_id'] as String?;
      if (savedCityId != _selectedCity!['id']) {
        throw Exception('City did not save — please try again.');
      }
    } catch (e) {
      // Country/city must both actually be saved server-side — the backend
      // marks a profile complete only once country + city + interests are
      // all set. Silently continuing past a failure here left users stuck
      // with an incomplete profile and no way to tell why uploads failed
      // later. Surface it and let them retry instead.
      if (!mounted) return;
      final reason = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _saving = false;
        _errorText = 'Failed to save your location: $reason';
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
      MaterialPageRoute(builder: (_) => const InterestsScreen()),
    );
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
      _loadCities(picked['id'] as String, countryCode: picked['code'] as String?);
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
                    widget.isEditMode
                        ? GestureDetector(
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
                          )
                        : Row(
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
                    const Text('Personalise\nyour feed',
                        style: AppTextStyles.compactTitle),
                    const SizedBox(height: 8),
                    Text(
                      'Help us show you the right challenges',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14),
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

                    if (_errorText != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13),
                      ),
                    ],

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

                    if (!widget.isEditMode) ...[
                    const SizedBox(height: 16),

                    Center(
                      child: GestureDetector(
                        onTap: _saving
                            ? null
                            : () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const InterestsScreen()),
                                ),
                        child: Text(
                          'Skip for now',
                          style: TextStyle(color: AppColors.textFaint, fontSize: 14),
                        ),
                      ),
                    ),
                    ],
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
                    color: value != null ? Colors.white : AppColors.textFaint,
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
                  hintStyle: TextStyle(color: AppColors.textFaint, fontSize: 14),
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
                      style: TextStyle(color: AppColors.textFaint, fontSize: 14),
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
