import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

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

  File? _pickedImage;
  String _currentPhotoUrl = '';

  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data() ?? {};
    _nameCtrl.text = data['name'] as String? ?? '';
    _usernameCtrl.text = data['username'] as String? ?? '';
    _bioCtrl.text = data['bio'] as String? ?? '';
    _currentPhotoUrl = data['profileImageUrl'] as String? ?? '';
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Change Photo',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _photoOption(Icons.camera_alt_rounded, 'Camera', ImageSource.camera),
            const SizedBox(height: 12),
            _photoOption(Icons.photo_library_rounded, 'Gallery', ImageSource.gallery),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 512);
    if (picked != null && mounted) setState(() => _pickedImage = File(picked.path));
  }

  Widget _photoOption(IconData icon, String label, ImageSource source) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _accent, size: 22),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _usernameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and username are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _saving = false);
      return;
    }

    String photoUrl = _currentPhotoUrl;
    if (_pickedImage != null) {
      final ref = FirebaseStorage.instance.ref().child('profile_photos/$uid');
      await ref.putFile(_pickedImage!);
      photoUrl = await ref.getDownloadURL();
    }

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'name': _nameCtrl.text.trim(),
      'username': _usernameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'profileImageUrl': photoUrl,
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
                  // Avatar
                  Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Stack(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
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
                            child: ClipOval(
                              child: _pickedImage != null
                                  ? Image.file(_pickedImage!, fit: BoxFit.cover)
                                  : _currentPhotoUrl.isNotEmpty
                                      ? Image.network(_currentPhotoUrl, fit: BoxFit.cover)
                                      : const Icon(Icons.person_rounded,
                                          color: Colors.white, size: 44),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: _accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Change Photo',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

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
