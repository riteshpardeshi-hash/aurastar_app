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
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final iconAsset = categoryIconAsset[categoryName];
    if (iconAsset == null) return const SizedBox.shrink();
    return SvgPicture.asset(
      iconAsset,
      width: size,
      height: size,
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
    );
  }
}
