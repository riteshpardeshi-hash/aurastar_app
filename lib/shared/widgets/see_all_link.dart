import 'package:flutter/material.dart';

/// The one "See All" link next to a section heading. Every section uses this, so the wording,
/// arrow, colour and size never differ between them.
class SeeAllLink extends StatelessWidget {
  const SeeAllLink({super.key, required this.onTap, this.count});

  final VoidCallback onTap;

  /// Shown when the section holds more than it displays: "See All 9 >".
  final int? count;

  static const style = TextStyle(color: Color(0xFF9B4DCA), fontSize: 13, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text(count == null ? 'See All >' : 'See All $count >', style: style),
  );
}
