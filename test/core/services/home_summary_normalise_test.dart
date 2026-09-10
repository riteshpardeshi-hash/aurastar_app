import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/home_service.dart';

// Regression: `/home/featured` (and the other `/home/*` challenge endpoints)
// return *populated* Challenge documents — `category` is `{ _id, name }`, not a
// string, and the video URL can sit on a nested `videoId`. `normaliseHomeSummary`
// used `c['category'] as String`, which threw
// `_Map<String, dynamic> is not a subtype of type 'String'` and red-screened
// the whole home feed the moment a challenge was featured.
void main() {
  test('handles a populated challenge doc (category object, nested videoId)', () {
    final out = normaliseHomeSummary({
      '_id': 'ch-1',
      'title': 'The Funky Goat Dance Challenge',
      'description': 'Replicate the quirky moves.',
      'category': {'_id': 'cat-1', 'name': 'Dance'},
      'creatorId': {'displayName': 'Admin Yash', 'avatar': 'a.png', 'role': 'admin'},
      'videoId': {'videoUrl': 'https://cdn/v.mp4', 'thumbnailUrl': 'https://cdn/t.jpg'},
      'submissionsCount': 4,
    });

    expect(out['id'], 'ch-1');
    expect(out['title'], 'The Funky Goat Dance Challenge');
    expect(out['instructions'], 'Replicate the quirky moves.');
    expect(out['category'], 'Dance'); // the name, not the {_id,name} map
    expect(out['videoUrl'], 'https://cdn/v.mp4'); // pulled off nested videoId
    expect(out['thumbnailUrl'], 'https://cdn/t.jpg');
    expect(out['submissionsCount'], 4);
  });

  test('handles a flat summary doc (category + videoUrl as strings)', () {
    final out = normaliseHomeSummary({
      '_id': 'ch-2',
      'title': 'Backflip',
      'videoUrl': 'https://cdn/b.mp4',
      'thumbnailUrl': 'https://cdn/b.jpg',
      'category': 'Sports',
    });

    expect(out['category'], 'Sports');
    expect(out['videoUrl'], 'https://cdn/b.mp4');
    expect(out['instructions'], 'Backflip'); // falls back to title when no description
  });

  test('missing / malformed fields never throw', () {
    final out = normaliseHomeSummary({'category': 123, 'videoId': 'not-a-map'});
    expect(out['id'], '');
    expect(out['title'], '');
    expect(out['category'], '');
    expect(out['videoUrl'], '');
  });
}
