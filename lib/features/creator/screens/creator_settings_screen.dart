import 'package:flutter/material.dart';
import '../../../core/services/creator_account_service.dart';
import '../../../shared/theme/app_colors.dart';

class CreatorSettingsScreen extends StatefulWidget {
  const CreatorSettingsScreen({super.key});

  @override
  State<CreatorSettingsScreen> createState() => _CreatorSettingsScreenState();
}

class _CreatorSettingsScreenState extends State<CreatorSettingsScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  final _service = CreatorAccountService();

  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;

  String _visibility = 'public';
  final Map<String, bool> _notifications = {
    'newFollowers': true,
    'likes': true,
    'gateUnlock': true,
    'challengeApproval': true,
    'challengeRejection': true,
    'participations': true,
  };

  final _instagramCtrl = TextEditingController();
  final _youtubeCtrl   = TextEditingController();
  final _tiktokCtrl    = TextEditingController();
  final _twitterCtrl   = TextEditingController();
  final _websiteCtrl   = TextEditingController();

  static const _notificationLabels = {
    'newFollowers': 'New followers',
    'likes': 'Likes on your videos',
    'gateUnlock': 'Gate unlocks',
    'challengeApproval': 'Challenge approved',
    'challengeRejection': 'Challenge rejected / changes requested',
    'participations': 'New challenge participations',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _instagramCtrl.dispose();
    _youtubeCtrl.dispose();
    _tiktokCtrl.dispose();
    _twitterCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _service.fetchSettings();
    if (!mounted) return;
    setState(() {
      _visibility = settings['visibility'] as String? ?? 'public';
      final notifs = settings['notifications'] as Map<String, dynamic>?;
      if (notifs != null) {
        for (final key in _notifications.keys) {
          if (notifs[key] is bool) _notifications[key] = notifs[key] as bool;
        }
      }
      final links = settings['linkedAccounts'] as Map<String, dynamic>?;
      _instagramCtrl.text = links?['instagram'] as String? ?? '';
      _youtubeCtrl.text   = links?['youtube'] as String? ?? '';
      _tiktokCtrl.text    = links?['tiktok'] as String? ?? '';
      _twitterCtrl.text   = links?['twitter'] as String? ?? '';
      _websiteCtrl.text   = links?['website'] as String? ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.updateSettings(
        visibility: _visibility,
        notifications: _notifications,
        linkedAccounts: {
          if (_instagramCtrl.text.trim().isNotEmpty) 'instagram': _instagramCtrl.text.trim(),
          if (_youtubeCtrl.text.trim().isNotEmpty) 'youtube': _youtubeCtrl.text.trim(),
          if (_tiktokCtrl.text.trim().isNotEmpty) 'tiktok': _tiktokCtrl.text.trim(),
          if (_twitterCtrl.text.trim().isNotEmpty) 'twitter': _twitterCtrl.text.trim(),
          if (_websiteCtrl.text.trim().isNotEmpty) 'website': _websiteCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Settings saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(e.toString());
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Creator Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
            'Your creator page will be removed and all live challenges archived. Your account is kept and you can keep using the app as a player. This cannot be undone from within the app.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await _service.deleteProfile();
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
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
        title: const Text('Creator Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Profile Visibility'),
                  const SizedBox(height: 8),
                  _visibilityOption('public', 'Public', 'Anyone can view your page and challenges'),
                  const SizedBox(height: 8),
                  _visibilityOption('followers_only', 'Followers Only', 'Only your followers can view your page'),

                  const SizedBox(height: 24),
                  _label('Notifications'),
                  const SizedBox(height: 4),
                  ..._notifications.keys.map((key) => SwitchListTile(
                        value: _notifications[key]!,
                        onChanged: (v) => setState(() => _notifications[key] = v),
                        activeThumbColor: _accent,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_notificationLabels[key] ?? key,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      )),

                  const SizedBox(height: 20),
                  _label('Linked Accounts'),
                  const SizedBox(height: 8),
                  _linkField(_instagramCtrl, 'Instagram URL'),
                  const SizedBox(height: 10),
                  _linkField(_youtubeCtrl, 'YouTube URL'),
                  const SizedBox(height: 10),
                  _linkField(_tiktokCtrl, 'TikTok URL'),
                  const SizedBox(height: 10),
                  _linkField(_twitterCtrl, 'Twitter / X URL'),
                  const SizedBox(height: 10),
                  _linkField(_websiteCtrl, 'Website URL'),

                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        disabledBackgroundColor: _accent.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),

                  const SizedBox(height: 32),
                  _label('Danger Zone'),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _deleting ? null : _confirmDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _deleting
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2.5))
                          : const Text('Delete Creator Profile', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700));

  Widget _visibilityOption(String value, String title, String subtitle) {
    final sel = _visibility == value;
    return GestureDetector(
      onTap: () => setState(() => _visibility = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? _accent.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                color: sel ? _accent : Colors.white38, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
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
      ),
    );
  }
}
