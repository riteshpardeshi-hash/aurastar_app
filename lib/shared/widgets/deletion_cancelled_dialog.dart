import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shown once, right after a login whose response carried
/// `deletionCancelled: true` — i.e. this login just cancelled a pending
/// self-service deactivation/deletion request and the account is fully
/// active again (ADR 022, mirrors the backend's ADR 098). Shared by every
/// login entry point (phone OTP, Google, Apple) so the copy/styling can't
/// drift between them.
Future<void> showDeletionCancelledDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF12102A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Welcome back',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: const Text(
        'Your account deletion request was cancelled — your account is '
        'active again.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}
