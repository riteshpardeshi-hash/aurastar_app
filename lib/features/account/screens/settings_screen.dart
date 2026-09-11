import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/auth_api_service.dart';
import 'edit_profile_screen.dart';
import 'archived_videos_screen.dart';
import 'notification_preferences_screen.dart';
import '../../auth/screens/phone_auth_screen.dart';
import '../../challenges/widgets/aura_submitted_popup.dart';
import '../../auth/screens/city_interests_screen.dart';
import '../../auth/screens/interests_screen.dart';
import '../../../core/config/api_config.dart';
import '../../../shared/theme/app_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _bg = Color(0xFF080810);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _section('Account'),
          _tile(
            context,
            icon: Icons.edit_outlined,
            label: 'Edit Profile',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
          ),
          _tile(
            context,
            icon: Icons.archive_outlined,
            label: 'Archived Videos',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchivedVideosScreen()),
            ),
          ),
          _tile(
            context,
            icon: Icons.location_on_outlined,
            label: 'Country & City',
            onTap: () => _editAndConfirm(
              context,
              const CityInterestsScreen(isEditMode: true),
              'Location saved.',
            ),
          ),
          _tile(
            context,
            icon: Icons.interests_outlined,
            label: 'Interests',
            onTap: () => _editAndConfirm(
              context,
              const InterestsScreen(isEditMode: true),
              'Interests saved.',
            ),
          ),
          _tile(
            context,
            icon: Icons.notifications_outlined,
            label: 'Notification Preferences',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationPreferencesScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _section('Support'),
          _tile(
            context,
            icon: Icons.help_outline_rounded,
            label: 'Help & Rules',
            onTap: () => _showHelpSheet(context),
          ),
          const SizedBox(height: 24),
          _section('Debug'),
          _tile(
            context,
            icon: Icons.bug_report_outlined,
            label: 'Preview: Video Rejected',
            // Must be showDialog<String>, not <bool>: every dismiss control in
            // AuraSubmittedPopup pops with the String 'continue'/'retry', and
            // popping a DialogRoute<bool> with a String throws inside
            // Route.didPop — which silently swallows the pop and leaves the
            // dialog undismissable. The fixture also uses the real backend
            // shape ('scored' + verdict 'INVALID') so submissionStatusFromApi
            // resolves it to 'rejected' the same way production does; a bare
            // 'status': 'rejected' is not a real enum value and now falls
            // through to the ai_error ("Review Unavailable") screen instead.
            onTap: () => showDialog<String>(
              context: context,
              barrierDismissible: false,
              barrierColor: Colors.black.withValues(alpha: 0.85),
              builder: (_) => const AuraSubmittedPopup(
                submissionId: 'debug-preview',
                challengeTitle: 'Dancing Girl',
                challengeId: 'debug-preview',
                initialResult: {
                  'status': 'scored',
                  'verdict': 'INVALID',
                  'aiReason':
                      'The submission does not contain any dance performance, and no human subject is visible in the frame. Additionally, the video is only 3 seconds long, failing to meet the minimum duration and movement requirements of the challenge.',
                },
              ),
            ),
          ),
          _tile(
            context,
            icon: Icons.dns_outlined,
            label: 'API server',
            subtitle: ApiConfig.isCompileTimePinned
                ? '${ApiConfig.baseUrl}  (pinned via --dart-define)'
                : ApiConfig.baseUrl,
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const _ApiServerDialog(),
            ),
          ),
          const SizedBox(height: 24),
          _section('Danger Zone'),
          _tile(
            context,
            icon: Icons.logout_rounded,
            label: 'Logout',
            color: Colors.redAccent,
            onTap: () => _logout(context),
          ),
          _tile(
            context,
            icon: Icons.phonelink_erase_rounded,
            label: 'Logout of All Devices',
            color: Colors.redAccent,
            onTap: () => _logoutAll(context),
          ),
          _tile(
            context,
            icon: Icons.delete_forever_rounded,
            label: 'Delete Account',
            color: Colors.redAccent,
            onTap: () => _deleteAccount(context),
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
            color: AppColors.textFaint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    String? subtitle,
  }) {
    final c = color ?? Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      // Material (not a bare DecoratedBox color) so ListTile's ink/splash and
      // its subtitle-layout assertions have a proper backing surface.
      child: Material(
        color: const Color(0xFF0E0E20),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: c, size: 22),
          title: Text(label, style: TextStyle(color: c, fontSize: 15)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: Icon(Icons.chevron_right_rounded,
              color: Colors.white24, size: 20),
          onTap: onTap,
        ),
      ),
    );
  }

  // Pushes an edit-mode onboarding screen (Country & City / Interests) and
  // shows a confirmation once it pops back with a successful save. Used to
  // let a user fix a profile that got stuck incomplete because onboarding
  // silently swallowed a save failure.
  Future<void> _editAndConfirm(
      BuildContext context, Widget screen, String successMessage) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Logout',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await Future.wait([
      AuthApiService().logout(),
      FirebaseAuth.instance.signOut(),
    ]);
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PhoneAuthScreen()),
      (route) => false,
    );
  }

  Future<void> _logoutAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Logout of All Devices',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
            'This signs you out everywhere, including other phones or tablets logged into this account. You\'ll need to log in again on each device.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout All',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await Future.wait([
      AuthApiService().logoutAll(),
      FirebaseAuth.instance.signOut(),
    ]);
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PhoneAuthScreen()),
      (route) => false,
    );
  }

  // Required by App Store Guideline 5.1.1(v) and Google Play's account
  // deletion policy: self-service, in-app, no support ticket required.
  // Two steps — an explanation of what's kept vs. removed (mirrors the
  // hosted Privacy Policy §5), then a typed "DELETE" confirmation — since
  // unlike Logout this is irreversible.
  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await AuthApiService().deleteAccount();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // dismiss the spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t delete account: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PhoneAuthScreen()),
      (route) => false,
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _HelpSheet(),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Text(
              'Help & Rules',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: const [
                _HelpItem(
                  icon: Icons.auto_awesome,
                  title: 'How AuraSense Scores',
                  body:
                      'AuraSense evaluates your attempt based on movement accuracy, timing, sound match, and challenge completion quality. Only performance is scored — clothes, appearance, and location do not matter.',
                ),
                _HelpItem(
                  icon: Icons.star_outline_rounded,
                  title: 'How Aura Points Work',
                  body:
                      'You earn Aura Points when your submission is approved. Points determine your level and tier, unlocking brand offers as you progress from Rookie to Divine.',
                ),
                _HelpItem(
                  icon: Icons.video_library_outlined,
                  title: 'Share, Archive or Delete',
                  body:
                      'After submitting, choose what happens to your video. Sharing makes it public and eligible for leaderboards. Archiving keeps it private but retains your Auras. Deleting removes the video and deducts earned Auras.',
                ),
                _HelpItem(
                  icon: Icons.shield_outlined,
                  title: 'Fair Play',
                  body:
                      'Copy the challenge as closely as you can. Duplicate uploads, unsafe content, and fake accounts will be flagged and may result in Aura deductions or account suspension.',
                ),
                _HelpItem(
                  icon: Icons.support_agent_outlined,
                  title: 'Contact Support',
                  body:
                      'For issues or appeals, reach out via the in-app feedback option or email support@aura.app.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _HelpItem(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF7B2CBF), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 6),
                Text(body,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-step "are you sure" for account deletion: an explanation of what's
/// kept vs. removed, then a typed "DELETE" to unlock the confirm button —
/// this is the one destructive action in Settings that can't be undone.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();
  bool _canConfirm = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final ok = _ctrl.text.trim().toUpperCase() == 'DELETE';
      if (ok != _canConfirm) setState(() => _canConfirm = ok);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF12102A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Delete Account',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently removes your profile — name, photo, gender, '
            'and date of birth — and signs you out everywhere. Your videos '
            'and submissions are removed from public view.\n\n'
            'Your phone number is retained in a scrubbed record to prevent '
            'abuse of referrals and rewards, as described in our Privacy '
            'Policy.\n\nThis can\'t be undone.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 16),
          Text('Type DELETE to confirm',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'DELETE',
              hintStyle: TextStyle(color: Colors.white24),
              enabledBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: _canConfirm ? () => Navigator.pop(context, true) : null,
          child: Text('Delete Forever',
              style: TextStyle(
                  color: _canConfirm ? Colors.redAccent : Colors.white24,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

/// Debug-only picker to point the app at a different backend (local dev server
/// vs. production) without rebuilding — persists via [ApiConfig.setRuntimeOverride].
class _ApiServerDialog extends StatefulWidget {
  const _ApiServerDialog();

  @override
  State<_ApiServerDialog> createState() => _ApiServerDialogState();
}

class _ApiServerDialogState extends State<_ApiServerDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: ApiConfig.baseUrl);
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply(String url) async {
    setState(() => _saving = true);
    // '' / the production constant → clear the override (fall back to prod).
    await ApiConfig.setRuntimeOverride(
        url.trim() == ApiConfig.production ? '' : url.trim());
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('API server → ${ApiConfig.baseUrl}\n'
            'Restart the app and log in again (tokens are per-backend).'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Widget _preset(String label, String url) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _saving ? null : () => _ctrl.text = url,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 4),
            foregroundColor: const Color(0xFF7B2CBF),
          ),
          child: Text('$label  ·  $url',
              style: const TextStyle(fontSize: 12), textAlign: TextAlign.left),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF12102A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('API server', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ApiConfig.isCompileTimePinned)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Pinned by --dart-define=API_BASE_URL — this picker is ignored '
                'until that build flag is removed.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          TextField(
            controller: _ctrl,
            enabled: !_saving && !ApiConfig.isCompileTimePinned,
            autocorrect: false,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'http://host:port/api/v1',
              hintStyle: TextStyle(color: Colors.white24),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
            ),
          ),
          const SizedBox(height: 10),
          _preset('Production', ApiConfig.production),
          _preset('Local · Android emulator', ApiConfig.localAndroidEmulator),
          _preset('Local · simulator / adb reverse', ApiConfig.localLoopback),
          const SizedBox(height: 6),
          const Text(
            'Physical device on the same wifi: use http://<your-machine-LAN-IP>:3000/api/v1',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: _saving || ApiConfig.isCompileTimePinned
              ? null
              : () => _apply(_ctrl.text),
          child: const Text('Save',
              style: TextStyle(
                  color: Color(0xFF7B2CBF), fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
