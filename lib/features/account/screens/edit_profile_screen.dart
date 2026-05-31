import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data() ?? {};
    _nameCtrl.text = data['name'] as String? ?? '';
    _usernameCtrl.text = data['username'] as String? ?? '';
    _bioCtrl.text = data['bio'] as String? ?? '';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _usernameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and username are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'name': _nameCtrl.text.trim(),
      'username': _usernameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated.')),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar placeholder
                  Center(
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.40),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 40),
                    ),
                  ),
                  const SizedBox(height: 32),

                  _label('Full Name'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _nameCtrl,
                    hint: 'Your full name',
                    icon: Icons.badge_outlined,
                    capitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 20),

                  _label('Username'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _usernameCtrl,
                    hint: 'Your username',
                    icon: Icons.alternate_email_rounded,
                    prefix: '@',
                  ),
                  const SizedBox(height: 20),

                  _label('Bio'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _bioCtrl,
                    hint: 'Tell people about yourself…',
                    maxLines: 4,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    String? prefix,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: capitalization,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: _accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.30), fontSize: 15),
          prefixIcon: icon != null && maxLines == 1
              ? Icon(icon,
                  color: Colors.white.withValues(alpha: 0.35), size: 20)
              : null,
          prefixText: prefix,
          prefixStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.40), fontSize: 15),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: (icon == null && maxLines > 1) ? 16 : 0,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
