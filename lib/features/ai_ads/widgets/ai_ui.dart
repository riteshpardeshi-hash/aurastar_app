import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';

/// Shared look for the AI Ads screens (same palette as the rest of the app).
class AiUi {
  static const bg = AppColors.background;
  static const accent = AppColors.accent;
  static const card = Color(0xFF0E0E1A);
  static const danger = Color(0xFFFF6B6B);
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFFB84D);

  static BoxDecoration cardDecoration({bool selected = false}) => BoxDecoration(
    color: selected ? accent.withValues(alpha: 0.15) : card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: selected ? accent : Colors.white.withValues(alpha: 0.08)),
  );

  static AppBar appBar(String title, {List<Widget> actions = const []}) => AppBar(
    backgroundColor: bg,
    elevation: 0,
    iconTheme: const IconThemeData(color: Colors.white),
    title: Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, fontFamily: 'ClashDisplay'),
    ),
    actions: actions,
  );

  static void toast(BuildContext context, String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }
}

class AiSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const AiSectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'ClashDisplay'),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// "⚡ 120 credits" — the creator's balance in this campaign.
class AiCreditsChip extends StatelessWidget {
  final int credits;

  const AiCreditsChip({super.key, required this.credits});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AiUi.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AiUi.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text('$credits credits', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Full-width primary action; shows a spinner while [busy].
class AiPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const AiPrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AiUi.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AiUi.accent.withValues(alpha: 0.3),
          disabledForegroundColor: Colors.white54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}

/// Secondary (outlined) action. An optional [price] ("3 credits", "Free") sits in a
/// pill on the right so the label stays on one line and the cost reads at a glance.
class AiSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? price;

  const AiSecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.price});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? Colors.white : Colors.white38;
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white38,
          backgroundColor: enabled ? AiUi.accent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
          side: BorderSide(color: enabled ? AiUi.accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.12)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Row(
          children: [
            Icon(icon ?? Icons.auto_awesome_rounded, size: 18, color: enabled ? AiUi.accent : Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            if (price != null) ...[
              const SizedBox(width: 8),
              _PricePill(price!, enabled: enabled),
            ],
          ],
        ),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final String text;
  final bool enabled;

  const _PricePill(this.text, {required this.enabled});

  @override
  Widget build(BuildContext context) {
    final free = text == 'Free';
    final color = !enabled ? Colors.white38 : (free ? AiUi.success : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: !enabled
            ? Colors.white.withValues(alpha: 0.05)
            : (free ? AiUi.success.withValues(alpha: 0.12) : AiUi.accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!free) ...[Icon(Icons.bolt_rounded, size: 13, color: color), const SizedBox(width: 2)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Red "not enough credits" line with an optional action.
class AiWarningText extends StatelessWidget {
  final String text;

  const AiWarningText(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AiUi.danger, fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}
