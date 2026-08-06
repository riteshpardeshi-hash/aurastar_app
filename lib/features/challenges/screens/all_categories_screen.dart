import 'package:flutter/material.dart';
import '../../../core/services/challenges_service.dart';
import 'category_challenges_screen.dart';

const _categoryTileColor = Color(0xFF7B2CBF);

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
                        child: Text(name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _categoryTileColor,
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w700)),
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
