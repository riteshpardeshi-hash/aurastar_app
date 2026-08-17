import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../features/challenges/screens/all_categories_screen.dart'
    show categoryIconAsset;

// Small chip overlaid on a challenge thumbnail showing its category icon.
// Callers resolve the challenge's `category` (an ObjectId) to a display name
// themselves — via ChallengesService().fetchCategoryNameMap() when they only
// have the id, or directly when the name is already in hand — since where
// that lookup happens varies by screen.
class CategoryIconBadge extends StatelessWidget {
  final String? categoryName;
  final double size;

  const CategoryIconBadge({
    super.key,
    required this.categoryName,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final iconAsset = categoryIconAsset[categoryName];
    if (iconAsset == null) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4),
        ],
      ),
      child: SvgPicture.asset(
        iconAsset,
        width: size * 0.6,
        height: size * 0.6,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      ),
    );
  }
}
