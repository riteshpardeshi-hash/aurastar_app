import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/brands_service.dart';
import 'brand_profile_screen.dart';

class BrandsListScreen extends StatefulWidget {
  const BrandsListScreen({super.key});

  @override
  State<BrandsListScreen> createState() => _BrandsListScreenState();
}

class _BrandsListScreenState extends State<BrandsListScreen> {
  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  final _service = BrandsService();
  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>>? _brands;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final raw = await _service.fetchBrands(search: _query, limit: 50);
      if (!mounted) return;
      setState(() => _brands = raw.map(normaliseBrand).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _brands = [];
        _error = true;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value.trim();
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Brands'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search brands...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF14141F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_brands == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_error) {
      return const Center(
          child: Text('Failed to load brands.',
              style: TextStyle(color: Colors.white54)));
    }
    if (_brands!.isEmpty) {
      return const Center(
          child: Text('No brands found.',
              style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      itemCount: _brands!.length,
      itemBuilder: (context, index) {
        final brand = _brands![index];
        final avatar = brand['avatar'] as String? ?? '';
        final displayName = brand['displayName'] as String? ?? 'Brand';
        final isVerified = brand['isVerified'] as bool? ?? false;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _accent.withValues(alpha: 0.3),
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white))
                : null,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white)),
              ),
              if (isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified_rounded, color: _accent, size: 14),
              ],
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BrandProfileScreen(brandId: brand['id'] as String),
            ),
          ),
        );
      },
    );
  }
}
