import 'package:flutter/material.dart';
import '../../../core/services/notifications_service.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  static const _bg = Color(0xFF080810);
  static const _card = Color(0xFF0E0E20);
  static const _accent = Color(0xFF7B2CBF);

  final _service = NotificationsService();

  bool _loading = true;
  bool _saving = false;
  bool _pushEnabled = false;
  Map<String, bool> _categories = const {
    'score': true,
    'streak': true,
    'offer': true,
    'leaderboard': true,
    'discovery': true,
  };
  bool _quietEnabled = true;
  int _quietStart = 22;
  int _quietEnd = 9;

  static const _categoryMeta = [
    ('score', 'Score Results', Icons.auto_awesome_rounded),
    ('streak', 'Streak Reminders', Icons.local_fire_department_rounded),
    ('offer', 'Offers & Rewards', Icons.local_offer_rounded),
    ('leaderboard', 'Leaderboard Moves', Icons.leaderboard_rounded),
    ('discovery', 'New Challenges', Icons.explore_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _service.fetchPreferences();
    if (!mounted) return;
    setState(() {
      if (prefs != null) {
        _pushEnabled = prefs['pushEnabled'] as bool? ?? false;
        final cats = prefs['categories'] as Map<String, dynamic>?;
        if (cats != null) {
          _categories = {
            for (final e in _categories.entries)
              e.key: cats[e.key] as bool? ?? e.value,
          };
        }
        final quiet = prefs['quietHours'] as Map<String, dynamic>?;
        if (quiet != null) {
          _quietEnabled = quiet['enabled'] as bool? ?? _quietEnabled;
          _quietStart = (quiet['startHour'] as num?)?.toInt() ?? _quietStart;
          _quietEnd = (quiet['endHour'] as num?)?.toInt() ?? _quietEnd;
        }
      }
      _loading = false;
    });
  }

  Map<String, dynamic> get _quietHoursPayload => {
        'enabled': _quietEnabled,
        'startHour': _quietStart,
        'endHour': _quietEnd,
      };

  // Sends the complete categories/quietHours object on every change rather
  // than just the one changed key — the spec only documents partial-update
  // semantics at the top level (pushEnabled/categories/quietHours), not
  // guaranteed deep-merge behavior inside the categories/quietHours objects
  // themselves, so a single-key patch risks the backend replacing the whole
  // nested object and silently resetting the other keys.
  Future<void> _save(Future<void> Function() apply, VoidCallback revert) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await apply();
    } catch (e) {
      if (mounted) {
        revert();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: ${_describe(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _describe(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  void _toggleMaster(bool value) {
    final previous = _pushEnabled;
    setState(() => _pushEnabled = value);
    _save(
      () => _service.updatePreferences(pushEnabled: value),
      () => setState(() => _pushEnabled = previous),
    );
  }

  void _toggleCategory(String key, bool value) {
    final previous = Map<String, bool>.from(_categories);
    setState(() => _categories = {..._categories, key: value});
    _save(
      () => _service.updatePreferences(categories: _categories),
      () => setState(() => _categories = previous),
    );
  }

  void _updateQuietHours({bool? enabled, int? startHour, int? endHour}) {
    final previousEnabled = _quietEnabled;
    final previousStart = _quietStart;
    final previousEnd = _quietEnd;
    setState(() {
      if (enabled != null) _quietEnabled = enabled;
      if (startHour != null) _quietStart = startHour;
      if (endHour != null) _quietEnd = endHour;
    });
    _save(
      () => _service.updatePreferences(quietHours: _quietHoursPayload),
      () => setState(() {
        _quietEnabled = previousEnabled;
        _quietStart = previousStart;
        _quietEnd = previousEnd;
      }),
    );
  }

  String _formatHour(int h) {
    final period = h < 12 ? 'AM' : 'PM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:00 $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Notification Preferences'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              children: [
                _sectionCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: _accent,
                    title: const Text('Push Notifications',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: const Text(
                      'Get notified about scores, streaks, offers and more',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    value: _pushEnabled,
                    onChanged: _saving ? null : _toggleMaster,
                  ),
                ),
                const SizedBox(height: 24),
                _section('Categories'),
                _sectionCard(
                  child: Opacity(
                    opacity: _pushEnabled ? 1 : 0.4,
                    child: Column(
                      children: [
                        for (final meta in _categoryMeta)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            activeThumbColor: _accent,
                            secondary: Icon(meta.$3, color: Colors.white70),
                            title: Text(meta.$2,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            value: _categories[meta.$1] ?? true,
                            onChanged: (!_pushEnabled || _saving)
                                ? null
                                : (v) => _toggleCategory(meta.$1, v),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _section('Quiet Hours'),
                _sectionCard(
                  child: Opacity(
                    opacity: _pushEnabled ? 1 : 0.4,
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: _accent,
                          title: const Text('Mute during quiet hours',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 14)),
                          value: _quietEnabled,
                          onChanged: (!_pushEnabled || _saving)
                              ? null
                              : (v) => _updateQuietHours(enabled: v),
                        ),
                        if (_quietEnabled) ...[
                          const Divider(color: Colors.white10, height: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _hourPicker(
                                  label: 'From',
                                  value: _quietStart,
                                  enabled: _pushEnabled && !_saving,
                                  onChanged: (h) =>
                                      _updateQuietHours(startHour: h),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _hourPicker(
                                  label: 'To',
                                  value: _quietEnd,
                                  enabled: _pushEnabled && !_saving,
                                  onChanged: (h) =>
                                      _updateQuietHours(endHour: h),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _sectionCard({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        // The switch rows' ink splashes need a Material ancestor with a
        // defined color to paint against — without this the framework
        // warns "ink splashes may be invisible" since the BoxDecoration
        // above isn't one.
        child: Material(type: MaterialType.transparency, child: child),
      );

  Widget _hourPicker({
    required String label,
    required int value,
    required bool enabled,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              dropdownColor: _card,
              iconEnabledColor: Colors.white54,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: List.generate(
                24,
                (h) => DropdownMenuItem(value: h, child: Text(_formatHour(h))),
              ),
              onChanged: enabled ? (h) { if (h != null) onChanged(h); } : null,
            ),
          ),
        ),
      ],
    );
  }
}
