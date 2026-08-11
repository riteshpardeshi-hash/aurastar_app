import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/services/challenges_service.dart';
import 'category_challenges_screen.dart';

const _categoryTileColor = Color(0xFF7B2CBF);

// Categories without a designed icon below (e.g. a new one an admin adds)
// fall back to this icon.
const _fallbackIcon = Icons.category_rounded;

// Maps the backend's actual category names (GET /categories, checked live
// 2026-08-10 — 15 categories) to their designed icon in
// assets/images/new category icons/. Names not listed here fall back to
// _fallbackIcon instead of breaking. Public — also used by
// AllGeneralChallengesScreen and the home feed's Categories section for the
// same icon set.
const categoryIconAsset = <String, String>{
  'Action': 'assets/images/new category icons/action.svg',
  'Animal Dancing': 'assets/images/new category icons/animals.svg',
  'Animals in action': 'assets/images/new category icons/animals.svg',
  'Challenges': 'assets/images/new category icons/challenges.svg',
  'Dance': 'assets/images/new category icons/dance.svg',
  'Facial expressions': 'assets/images/new category icons/facial expression.svg',
  'Fashion': 'assets/images/new category icons/fashion.svg',
  'Fitness': 'assets/images/new category icons/fitness.svg',
  'Food': 'assets/images/new category icons/food.svg',
  'Juggling': 'assets/images/new category icons/juggling.svg',
  'Singing': 'assets/images/new category icons/singing.svg',
  'Sports': 'assets/images/new category icons/football.svg',
  'Tricks': 'assets/images/new category icons/Tricks.svg',
  'Yoga': 'assets/images/new category icons/yoga.svg',
  'Zombies': 'assets/images/new category icons/zombie.svg',
};

class AllCategoriesScreen extends StatefulWidget {
  // {_id, name} pairs — GET /challenges' `category` filter is the category's
  // ObjectId, not its display name, so both are needed downstream.
  final List<Map<String, dynamic>> categories;

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
  late List<Map<String, dynamic>> _categories = widget.categories;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final cats = await ChallengesService().fetchCategoriesWithIds();
    if (mounted && cats.isNotEmpty) setState(() => _categories = cats);
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
                  final id = _categories[i]['_id'] as String? ?? '';
                  final name = _categories[i]['name'] as String? ?? '';
                  final iconAsset = categoryIconAsset[name];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryChallengesScreen(
                            categoryId: id, categoryName: name),
                      ),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _categoryTileColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _categoryTileColor.withValues(alpha: 0.25),
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
                                    width: 42,
                                    height: 42,
                                    colorFilter: const ColorFilter.mode(
                                        _categoryTileColor, BlendMode.srcIn),
                                  )
                                : const Icon(_fallbackIcon,
                                    color: _categoryTileColor, size: 36),
                            const SizedBox(height: 6),
                            Text(name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _categoryTileColor,
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
