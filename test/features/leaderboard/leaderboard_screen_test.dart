import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/leaderboard/leaderboard_screen.dart';
import 'package:aura_app/features/leaderboard/screens/challenge_leaderboard_screen.dart';

import '../ai_ads/ai_ads_fake_backend.dart';

// Client, 26 Nov 2026: the Leaderboard gets search and sort like every other
// list. Global: a podium, All time / Month / Week, a sort menu and the
// viewer's own rank pinned at the bottom. Challenge: searchable, sortable
// cards that open each challenge's board. Both search and sort on the
// server (backend ADR 154).

Map<String, dynamic> player(String id, String name, int score, int rank) =>
    {'_id': id, 'displayName': name, 'profileName': name.toLowerCase(), 'score': score, 'rank': rank};

final _board = [
  player('u1', 'Ada', 2045, 1),
  player('creator-1', 'Yash', 820, 2),
  player('u3', 'Shweta', 764, 3),
  player('u4', 'Ritesh', 10, 4),
  player('u5', 'Narem', 5, 5),
];

void main() {
  late FakeAiAdsBackend backend;

  setUp(() {
    backend = FakeAiAdsBackend();
    backend.on('GET /profile', {
      'user': {'_id': 'creator-1', 'displayName': 'Yash'}
    });
    backend.routes['GET /leaderboard'] = (req) {
      final search = (req.query['search'] ?? '').toLowerCase();
      final rows = _board
          .where((p) => search.isEmpty || (p['displayName'] as String).toLowerCase().contains(search))
          .toList();
      return FakeAiAdsBackend.ok({
        'responses': rows,
        'totalCount': rows.length,
        'me': {'rank': 2, 'score': 820, 'gapToFirst': 1225, 'gapToNext': 1225},
      });
    };
    backend.routes['GET /leaderboard/challenges'] = (req) {
      final search = (req.query['search'] ?? '').toLowerCase();
      final cards = [
        {
          '_id': 'ch1',
          'title': 'FitNest Jump Rope',
          'participants': 12,
          'leader': {'displayName': 'Shweta', 'score': 92},
          'myRank': 2,
        },
        {'_id': 'ch2', 'title': 'Cross-Eyed Focus', 'participants': 0, 'leader': null, 'myRank': null},
      ].where((c) => search.isEmpty || (c['title'] as String).toLowerCase().contains(search)).toList();
      return FakeAiAdsBackend.ok({'responses': cards, 'totalCount': cards.length});
    };
    backend.on('GET /challenges/ch1/submissions', {
      'submissions': [
        {'_id': 's1', 'userId': {'_id': 'u3', 'displayName': 'Shweta', 'username': 'shweta'}, 'aiScore': 92},
      ],
    });
  });
  tearDown(FakeAiAdsBackend.reset);

  Future<void> open(WidgetTester tester) => pumpAiScreen(tester, const LeaderboardScreen());

  testWidgets('Global shows the top three on a podium, the rest as rows, and your rank pinned',
      (tester) async {
    await open(tester);
    expect(find.byKey(const Key('podium-1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('podium-1')), matching: find.text('2K')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('podium-2')), matching: find.text('You')),
        findsOneWidget);
    expect(find.text('Ritesh'), findsOneWidget);
    expect(find.text('@ritesh'), findsOneWidget);

    final you = find.byKey(const Key('leaderboard-you-bar'));
    expect(you, findsOneWidget);
    expect(find.descendant(of: you, matching: find.text('1,225 Aura behind #1')), findsOneWidget);
    expect(backend.calls('GET', '/leaderboard').single.query,
        containsPair('sort', 'aura_desc'));
  });

  testWidgets('searching players asks the server, drops the podium and keeps real ranks',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('leaderboard-search')), 'Ritesh');
    await settle(tester);

    expect(backend.calls('GET', '/leaderboard').last.query, containsPair('search', 'Ritesh'));
    expect(find.byKey(const Key('podium-1')), findsNothing);
    expect(find.text('@ritesh'), findsOneWidget);
    expect(find.text('4'), findsOneWidget, reason: 'Ritesh keeps rank 4 in the results');

    await tester.enterText(find.byKey(const Key('leaderboard-search')), 'zzz');
    await settle(tester);
    expect(find.text('No players match "zzz"'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
    expect(backend.calls('GET', '/leaderboard').last.query.containsKey('search'), isFalse);
    expect(find.byKey(const Key('podium-1')), findsOneWidget);
  });

  testWidgets('period and sort combine with the search in one request', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('leaderboard-search')), 'a');
    await settle(tester);
    await tester.tap(find.byKey(const Key('leaderboard-period-week')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('leaderboard-sort')));
    await settle(tester);
    await tester.tap(find.text('Name A–Z'));
    await settle(tester);

    final q = backend.calls('GET', '/leaderboard').last.query;
    expect(q, containsPair('search', 'a'));
    expect(q, containsPair('period', 'week'));
    expect(q, containsPair('sort', 'name_asc'));
    expect(find.text('Name A–Z'), findsOneWidget, reason: 'the current sort stays visible');
  });

  testWidgets('Challenge tab shows cards with your rank, the leader and participants',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Challenge'));
    await settle(tester);

    expect(find.text('FitNest Jump Rope'), findsOneWidget);
    expect(find.text('You #2'), findsOneWidget);
    expect(find.text('👑 Shweta · 92 · 12 participants'), findsOneWidget);
    expect(find.text('No scores yet · be first'), findsOneWidget);
  });

  testWidgets('Challenge tab search, filter and sort go to the server together', (tester) async {
    await open(tester);
    await tester.tap(find.text('Challenge'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('challenge-boards-search')), 'cross');
    await settle(tester);
    await tester.tap(find.byKey(const Key('challenge-boards-filter-brand')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('challenge-boards-sort')));
    await settle(tester);
    await tester.tap(find.text('Ending soon'));
    await settle(tester);

    final q = backend.calls('GET', '/leaderboard/challenges').last.query;
    expect(q, containsPair('search', 'cross'));
    expect(q, containsPair('filter', 'brand'));
    expect(q, containsPair('sort', 'ending_soon'));
    expect(find.text('Cross-Eyed Focus'), findsOneWidget);
    expect(find.text('FitNest Jump Rope'), findsNothing);

    await tester.enterText(find.byKey(const Key('challenge-boards-search')), 'nothing');
    await settle(tester);
    expect(find.text('No challenges match "nothing"'), findsOneWidget);
  });

  // Regression: GET /leaderboard/challenge/{id} returns an empty board for
  // challenges with real scores, so a challenge's board must come from
  // GET /challenges/{id}/submissions.
  testWidgets('tapping a card opens its board from the submissions endpoint', (tester) async {
    await open(tester);
    await tester.tap(find.text('Challenge'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('challenge-board-ch1')));
    await settle(tester);

    expect(find.byType(ChallengeLeaderboardScreen), findsOneWidget);
    expect(find.text('@shweta'), findsOneWidget);
    expect(backend.sent.where((r) => r.path.startsWith('/leaderboard/challenge/')), isEmpty);
  });
}
