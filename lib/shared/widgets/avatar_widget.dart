import 'package:flutter/material.dart';

/// Circular avatar that falls back to an initial letter both when [photoUrl]
/// is empty AND when it fails to load (expired/invalid URL, permissions
/// issue, network error). Plain `CircleAvatar(backgroundImage: NetworkImage(...))`
/// has no error handling — a broken image URL renders as a blank circle with
/// no fallback at all, which is indistinguishable from "still loading" or
/// "photo never saved" to the user.
class AvatarWidget extends StatelessWidget {
  final String photoUrl;
  final String fallbackText;
  final double radius;
  final Color? backgroundColor;
  final TextStyle? textStyle;

  const AvatarWidget({
    super.key,
    required this.photoUrl,
    required this.fallbackText,
    required this.radius,
    this.backgroundColor,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? const Color(0xFF7B2CBF).withValues(alpha: 0.20);
    final style = textStyle ??
        TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.6,
        );
    final initial = Text(fallbackText, style: style);

    if (photoUrl.isEmpty) {
      return CircleAvatar(radius: radius, backgroundColor: bg, child: initial);
    }

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          child: initial,
        ),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : CircleAvatar(radius: radius, backgroundColor: bg),
      ),
    );
  }
}
