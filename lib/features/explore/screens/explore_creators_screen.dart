import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/creators_service.dart';
import 'creator_profile_screen.dart';

class ExploreCreatorsScreen extends StatefulWidget {
  const ExploreCreatorsScreen({super.key});

  @override
  State<ExploreCreatorsScreen> createState() => _ExploreCreatorsScreenState();
}

class _ExploreCreatorsScreenState extends State<ExploreCreatorsScreen> {
  final _service = CreatorsService();
  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>>? _creators;
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
      final raw = await _service.fetchCreators(search: _query, limit: 50);
      if (!mounted) return;
      setState(() => _creators = raw.map(normaliseCreator).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creators = [];
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
      appBar: AppBar(title: const Text("Explore Brands")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search brands...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
    if (_creators == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return const Center(child: Text('Failed to load creators.'));
    }
    if (_creators!.isEmpty) {
      return const Center(child: Text('No creators found.'));
    }
    return ListView.builder(
      itemCount: _creators!.length,
      itemBuilder: (context, index) {
        final creator = _creators![index];
        final avatar = creator['avatar'] as String? ?? '';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.orange,
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
          title: Text(creator['displayName'] as String? ?? 'Creator'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CreatorProfileScreen(creatorId: creator['id'] as String),
            ),
          ),
        );
      },
    );
  }
}
