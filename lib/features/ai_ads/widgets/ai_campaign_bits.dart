import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/services/ai_ads_service.dart';
import '../../../core/services/app_config_service.dart';

/// Small pieces shared by the home campaign spotlight, the campaign list and the campaign
/// screen (backend ADR 141): time left, status chips, the brand's avatar, the cover picture.
class AiCampaignBits {
  AiCampaignBits._();

  // Meaning-bearing colours: yellow = waiting / time left, peach = look at this now (ends
  // today), green = done / you're in.
  static const timeColor = Color(0xFFFACC15);
  static const urgentColor = Color(0xFFFB923C);
  static const joinedColor = Color(0xFF22C55E);
  static const lilac = Color(0xFFD4A8FF);

  /// "2d 6h left", "Ends in 5h", "Ends in 20m", or null when there's no deadline / it's past.
  static String? timeLeft(DateTime? deadline, {DateTime? now}) {
    if (deadline == null) return null;
    final left = deadline.difference(now ?? DateTime.now());
    if (left.isNegative) return null;
    if (left.inHours < 1) return 'Ends in ${left.inMinutes.clamp(1, 59)}m';
    if (left.inHours < 24) return 'Ends in ${left.inHours}h';
    final h = left.inHours % 24;
    return h == 0 ? '${left.inDays}d left' : '${left.inDays}d ${h}h left';
  }

  /// Under a day to go — shown in peach so it stands out.
  static bool endsSoon(DateTime? deadline, {DateTime? now}) {
    if (deadline == null) return false;
    final left = deadline.difference(now ?? DateTime.now());
    return !left.isNegative && left.inHours < 24;
  }

  /// Statuses where the creator is actually in the campaign. An invite not yet accepted or a
  /// request not yet approved is not "joined".
  static const joinedStatuses = {'ACTIVE', 'SUBMITTED', 'WINNER', 'NOT_SELECTED'};

  static bool isJoined(String? status) => joinedStatuses.contains(status);

  /// "7 of 10 seats left", "Full", or without a cap "Open to all" (or "No creator limit"
  /// for an invite-only campaign, which is not open to all).
  static String seatsLabel(int? seatsLeft, int? cap, {bool inviteOnly = false}) {
    if (seatsLeft == null || cap == null) return inviteOnly ? 'No creator limit' : 'Open to all';
    if (seatsLeft <= 0) return 'Full';
    return '$seatsLeft of $cap seats left';
  }

  /// Share of seats taken, 0..1, or null without a cap.
  static double? seatsTaken(int? seatsLeft, int? cap) {
    if (seatsLeft == null || cap == null || cap <= 0) return null;
    return ((cap - seatsLeft) / cap).clamp(0.0, 1.0);
  }

  /// Prizes follow the coupons switch (ADR 119), like every other reward in the app.
  static bool get showPrizes => AppConfigService.instance.couponsEnabled.value;
}

/// A rounded pill: icon + text in one colour on a dark glass background.
class AiChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;

  const AiChip({super.key, required this.label, this.icon, this.color = Colors.white, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The time-left chip: yellow, or peach when the campaign ends within a day.
class AiTimeChip extends StatelessWidget {
  final DateTime? deadline;
  final String? prefix;

  const AiTimeChip({super.key, required this.deadline, this.prefix});

  @override
  Widget build(BuildContext context) {
    final label = AiCampaignBits.timeLeft(deadline);
    if (label == null) return const SizedBox.shrink();
    final soon = AiCampaignBits.endsSoon(deadline);
    return AiChip(
      label: prefix == null ? label : '$prefix · $label',
      icon: soon ? Icons.local_fire_department_rounded : Icons.timer_outlined,
      color: soon ? AiCampaignBits.urgentColor : AiCampaignBits.timeColor,
    );
  }
}

/// Where the creator stands in a campaign, as a chip — or the "AI Ad Campaign" tag when they
/// haven't joined.
class AiStandingChip extends StatelessWidget {
  final String? status;

  const AiStandingChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'ACTIVE' => const AiChip(label: 'Joined', icon: Icons.check_rounded, color: AiCampaignBits.joinedColor, filled: true),
      'SUBMITTED' => const AiChip(label: 'Submitted', icon: Icons.check_circle_rounded, color: AiCampaignBits.joinedColor, filled: true),
      'REQUESTED' => const AiChip(label: 'Request sent', icon: Icons.hourglass_top_rounded, color: AiCampaignBits.timeColor, filled: true),
      'INVITED' => const AiChip(label: "You're invited", icon: Icons.mail_rounded, color: AiCampaignBits.lilac, filled: true),
      _ => const AiChip(label: 'AI Ad Campaign', icon: Icons.auto_awesome_rounded, color: AiCampaignBits.lilac, filled: true),
    };
  }
}

/// The brand's logo in a white circle, or its first letter.
class AiBrandAvatar extends StatelessWidget {
  final AiBrandRef brand;
  final double size;

  const AiBrandAvatar({super.key, required this.brand, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final letter = Text(
      brand.name.isEmpty ? 'B' : brand.name.characters.first.toUpperCase(),
      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: size * 0.48),
    );
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: brand.logo == null
          ? letter
          : CachedNetworkImage(
              imageUrl: brand.logo!,
              // Presigned URLs change on every load: cache by the object, not the signature.
              cacheKey: brand.logo!.split('?').first,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorWidget: (_, __, ___) => letter,
              placeholder: (_, __) => letter,
            ),
    );
  }
}

/// The campaign's cover picture filling its box, with a dark gradient for the text on top.
/// Without a picture, a purple gradient.
class AiCoverBackground extends StatelessWidget {
  final String? url;
  final double bottomShade;

  const AiCoverBackground({super.key, required this.url, this.bottomShade = 0.92});

  static const _fallback = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF2D0B5A), Color(0xFF0A1A40)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url == null)
          const DecoratedBox(decoration: _fallback)
        else
          CachedNetworkImage(
            imageUrl: url!,
            cacheKey: url!.split('?').first,
            fit: BoxFit.cover,
            placeholder: (_, __) => const DecoratedBox(decoration: _fallback),
            errorWidget: (_, __, ___) => const DecoratedBox(decoration: _fallback),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.45, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.15),
                Colors.black.withValues(alpha: bottomShade),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A thin rounded bar of seats taken.
class AiSeatsBar extends StatelessWidget {
  final double value;

  const AiSeatsBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 5,
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        valueColor: const AlwaysStoppedAnimation(Color(0xFFB57BEE)),
      ),
    );
  }
}
