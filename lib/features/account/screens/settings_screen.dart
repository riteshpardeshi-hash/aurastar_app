import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/auth_api_service.dart';
import 'edit_profile_screen.dart';
import 'archived_videos_screen.dart';
import '../../splash/screens/splash_screen.dart';

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
          const SizedBox(height: 24),
          _section('Support'),
          _tile(
            context,
            icon: Icons.help_outline_rounded,
            label: 'Help & Rules',
            onTap: () => _showHelpSheet(context),
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

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: Icon(icon, color: c, size: 22),
        title: Text(label, style: TextStyle(color: c, fontSize: 15)),
        trailing: Icon(Icons.chevron_right_rounded,
            color: Colors.white24, size: 20),
        onTap: onTap,
      ),
    );
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
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
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
      MaterialPageRoute(builder: (_) => const SplashScreen()),
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
                        color: Colors.white60,
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
