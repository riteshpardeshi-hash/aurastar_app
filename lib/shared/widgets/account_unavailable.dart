import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A profile the API won't show: not found, deactivated, or blocked — either way round,
/// the backend answers 404 for all of them (ADR 117), so the screen can't and shouldn't
/// say which.
class AccountUnavailable extends StatelessWidget {
  final Widget? backButton;
  const AccountUnavailable({super.key, this.backButton});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (backButton != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: backButton),
          ),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off_outlined, color: Colors.white38, size: 44),
                  SizedBox(height: 12),
                  Text(
                    "This account isn't available",
                    key: Key('profile-unavailable'),
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'It may have been removed, or one of you blocked the other.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
