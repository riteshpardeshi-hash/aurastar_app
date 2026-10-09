import 'package:flutter/material.dart';

import '../../core/services/safety_service.dart';
import '../../core/services/screen_cache.dart';
import '../theme/app_colors.dart';

// Report and block (backend ADR 117): the "⋯" menu on profiles and videos, the report
// sheet, and the block confirmation. A block is two-way and hides everything from that
// account; blocking a brand also hides its challenges, ads and AI ad campaigns.

const _accent = Color(0xFF7B2CBF);
const _sheetBg = Color(0xFF12102A);

/// "⋯" on someone's profile: report the account, or block it. [onBlocked] runs after a
/// successful block (a profile usually closes itself — it isn't visible any more).
Future<void> showProfileSafetyMenu(
  BuildContext context, {
  required String userId,
  required String name,
  bool isBrand = false,
  SafetyService? service,
  VoidCallback? onBlocked,
}) {
  final svc = service ?? SafetyService();
  return showSafetyMenu(context, [
    SafetyMenuItem(
      key: const Key('safety-report-account'),
      icon: Icons.flag_outlined,
      label: 'Report ${isBrand ? 'brand' : 'account'}',
      onTap:
          () => showReportSheet(
            context,
            title: 'Report $name',
            submit: (reason, details) => svc.reportUser(userId, reason, details: details),
          ),
    ),
    SafetyMenuItem(
      key: const Key('safety-block-account'),
      icon: Icons.block_rounded,
      label: 'Block $name',
      danger: true,
      onTap:
          () => blockWithConfirm(
            context,
            userId: userId,
            name: name,
            isBrand: isBrand,
            service: svc,
            onBlocked: onBlocked,
          ),
    ),
  ]);
}

/// "⋯" on a video: report the video, or block whoever posted it.
Future<void> showVideoSafetyMenu(
  BuildContext context, {
  required String videoId,
  String? ownerId,
  String? ownerName,
  bool ownerIsBrand = false,
  SafetyService? service,
  VoidCallback? onBlocked,
}) {
  final svc = service ?? SafetyService();
  return showSafetyMenu(context, [
    SafetyMenuItem(
      key: const Key('safety-report-video'),
      icon: Icons.flag_outlined,
      label: 'Report video',
      onTap:
          () => showReportSheet(
            context,
            title: 'Report this video',
            submit: (reason, details) => svc.reportVideo(videoId, reason, details: details),
          ),
    ),
    if (ownerId != null && ownerId.isNotEmpty)
      SafetyMenuItem(
        key: const Key('safety-block-owner'),
        icon: Icons.block_rounded,
        label: 'Block ${ownerName ?? 'this account'}',
        danger: true,
        onTap:
            () => blockWithConfirm(
              context,
              userId: ownerId,
              name: ownerName ?? 'this account',
              isBrand: ownerIsBrand,
              service: svc,
              onBlocked: onBlocked,
            ),
      ),
  ]);
}

/// Explains what a block does, then blocks. True when blocked.
Future<bool> blockWithConfirm(
  BuildContext context, {
  required String userId,
  required String name,
  bool isBrand = false,
  SafetyService? service,
  VoidCallback? onBlocked,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A0A2E),
          title: Text('Block $name?', style: const TextStyle(color: Colors.white, fontSize: 17)),
          content: Text(
            isBrand
                ? "You won't see this brand's profile, challenges, ads or AI ad campaigns, and it can't invite you. "
                    "You'll stop following each other. They aren't told you blocked them."
                : "Neither of you will see the other's profile, videos, challenges or comments, and you'll stop "
                    "following each other. They aren't told you blocked them.",
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            TextButton(
              key: const Key('safety-block-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await (service ?? SafetyService()).block(userId);
    // Cached pages (home, search, profiles) may still hold them — re-fetch everything.
    ScreenCache.clear();
    if (!context.mounted) return true;
    _toast(context, 'Blocked $name. You can unblock them in Settings → Blocked accounts.');
    onBlocked?.call();
    return true;
  } catch (e) {
    if (context.mounted) _toast(context, e is SafetyException ? e.message : "Couldn't block. Please try again.");
    return false;
  }
}

/// Reason + optional details → [submit]. [submit] returns true when it was already reported.
Future<void> showReportSheet(
  BuildContext context, {
  required String title,
  required Future<bool> Function(String reason, String? details) submit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(title: title, submit: submit),
  );
}

class _ReportSheet extends StatefulWidget {
  final String title;
  final Future<bool> Function(String reason, String? details) submit;
  const _ReportSheet({required this.title, required this.submit});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null || _busy) return;
    setState(() => _busy = true);
    try {
      final already = await widget.submit(_reason!, _details.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            already
                ? "You've already reported this — we're reviewing it."
                : "Thanks — we'll review it. We'll let you know when we've decided.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, e is SafetyException ? e.message : "Couldn't send the report. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: _sheetBg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                "Why are you reporting this? Your report is anonymous.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final e in SafetyService.reasons.entries)
                InkWell(
                  key: Key('safety-reason-${e.key}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: _busy ? null : () => setState(() => _reason = e.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          _reason == e.key ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: _reason == e.key ? _accent : Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('safety-report-details'),
                controller: _details,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add details (optional)',
                  hintStyle: const TextStyle(color: AppColors.textFaint),
                  counterStyle: const TextStyle(color: AppColors.textFaint),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  key: const Key('safety-report-send'),
                  onPressed: _reason == null || _busy ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child:
                      _busy
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                          : const Text('Send report', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SafetyMenuItem {
  final Key key;
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const SafetyMenuItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
}

/// A bottom-sheet menu of report / block actions.
Future<void> showSafetyMenu(BuildContext context, List<SafetyMenuItem> items) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // A Material surface (not a coloured box) so each item's tap ripple shows.
    builder:
        (sheetCtx) => Material(
          color: _sheetBg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(sheetCtx).padding.bottom + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items)
                  ListTile(
                    key: item.key,
                    leading: Icon(item.icon, color: item.danger ? Colors.redAccent : Colors.white),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        color: item.danger ? Colors.redAccent : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      item.onTap();
                    },
                  ),
              ],
            ),
          ),
        ),
  );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
