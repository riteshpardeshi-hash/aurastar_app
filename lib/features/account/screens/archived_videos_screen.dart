import 'package:flutter/material.dart';

// Archiving a submission was never wired to a real backend write — the old
// Firestore query below (`submissions` collection) queried a collection
// that no longer exists post-migration (submissions live in the REST/Mongo
// API now), and the `StreamBuilder` only checked `snap.hasData`, never
// `snap.hasError`, so a permission-denied error left it spinning forever.
// There is also no REST equivalent: the `Submission` schema has no
// `isArchived` field, and the only place that ever set it
// (`admin/screens/review_screen.dart`) is itself unreachable. So the
// correct state here isn't "loading" or "error" — it's always empty, since
// no submission can ever be archived through any currently reachable path.
class ArchivedVideosScreen extends StatelessWidget {
  const ArchivedVideosScreen({super.key});

  static const _bg = Color(0xFF080810);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Archived Videos'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.archive_outlined, color: Colors.white24, size: 52),
            SizedBox(height: 14),
            Text('No archived videos',
                style: TextStyle(color: Colors.white38, fontSize: 15)),
            SizedBox(height: 6),
            Text('Videos you archive will appear here',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
