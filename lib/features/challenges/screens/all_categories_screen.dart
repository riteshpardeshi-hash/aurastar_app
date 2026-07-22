import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/services/challenges_service.dart';
import 'category_challenges_screen.dart';

// Fallback styling for categories the backend returns that aren't in the
// known `categoryMeta` map (see category_challenges_screen.dart) or don't
// have a custom icon asset below.
const _fallbackMeta = (icon: Icons.category_rounded, color: Color(0xFF7B2CBF));

// Maps the backend's actual category names to their designed icon in
// assets/images/category icons/. Categories not listed here (e.g. a new one
// an admin adds before an icon is designed for it) fall back to
// _fallbackMeta's generic icon instead of breaking.
const _categoryIconAsset = <String, String>{
  'Beatboxing': 'assets/images/category icons/beatbox.svg',
  'Calisthenics': 'assets/images/category icons/Calesthenic.svg',
  'Cosplay Showdown': 'assets/images/category icons/Cosplay.svg',
  'Dance Battle': 'assets/images/category icons/dance.svg',
  'Freestyle Football': 'assets/images/category icons/football.svg',
  'Gaming Highlights': 'assets/images/category icons/gaming.svg',
  'Music Covers': 'assets/images/category icons/music.svg',
  'Parkour & Free Running': 'assets/images/category icons/parkour.svg',
  'Skateboarding': 'assets/images/category icons/skate.svg',
};

class AllCategoriesScreen extends StatefulWidget {
  final List<String> categories;

  const AllCategoriesScreen({super.key, required this.categories});

  @override
  State<AllCategoriesScreen> createState() => _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends State<AllCategoriesScreen> {
  static const _bg = Color(0xFF080810);

  // The list passed in is whatever the caller had already fetched at
  // navigation time — if the user tapped through before that fetch
  // resolved, it's still the hardcoded placeholder. Seed from it for an
  // instant first paint, then independently refetch so this screen is
  // correct even when it got here first.
  late List<String> _categories = widget.categories;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final names = await ChallengesService().fetchCategories();
    if (mounted && names.isNotEmpty) setState(() => _categories = names);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Text(
                    'All Categories',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'ClashDisplay',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.82,
                ),
                itemCount: _categories.length,
                itemBuilder: (context, i) {
                  final name = _categories[i];
                  final meta = categoryMeta[name] ?? _fallbackMeta;
                  final iconAsset = _categoryIconAsset[name];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CategoryChallengesScreen(category: name),
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: meta.color.withValues(alpha: 0.25),
                            width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconAsset != null
                                ? SvgPicture.asset(
                                    iconAsset,
                                    width: 36,
                                    height: 36,
                                    colorFilter: const ColorFilter.mode(
                                        Colors.white, BlendMode.srcIn),
                                  )
                                : Icon(meta.icon,
                                    color: Colors.white, size: 30),
                            const SizedBox(height: 6),
                            Text(name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: meta.color,
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
