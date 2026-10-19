import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/category_store.dart';
import 'package:aura_app/features/creator/screens/creator_challenge_draft_screen.dart';

// The create/edit page is where the creator builds the whole challenge, scoring criteria
// included (backend ADR 137): generate them on this page (saving the draft first so the AI
// sees the latest details), review / edit them, then "Submit for Approval" — not
// "Save Draft". The old free-text "scoring criteria" field never reached the scorer and
// is gone.
void main() {
  late List<http.Request> sent;
  late Map<String, dynamic> rubricView;

  Map<String, dynamic> generated() => {
        'hasRubric': true,
        'editable': true,
        'source': 'ai',
        'fixedCategories': [
          {'key': 'reference_similarity', 'name': 'Reference Similarity', 'maxPoints': 5},
        ],
        'categories': [
          for (var i = 0; i < 6; i++)
            {'key': 'k$i', 'name': 'Skill $i', 'maxPoints': i == 0 ? 15 : 14},
        ],
        'bonusRules': [],
        'totalPoints': 100, // what the backend reports for generated criteria
      };

  Map<String, dynamic> draft({String status = 'DRAFT'}) => {
        'id': 'ch-1',
        'title': 'Box Jump',
        'description': 'Jump on the box.',
        'categoryId': 'cat-1',
        'difficulty': 'Easy',
        'submissionStatus': status,
      };

  setUp(() {
    CategoryStore.instance.resetForTest();
    sent = [];
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'creator-1',
    });
    SharedPreferences.setMockInitialValues({});
    rubricView = {'hasRubric': false, 'editable': true, 'categories': []};

    ApiClient.httpClient = MockClient((req) async {
      sent.add(req);
      final path = req.url.path;
      Map<String, dynamic> data = {};
      if (path.endsWith('/rubric/generate')) {
        rubricView = generated();
        data = rubricView;
      } else if (path.endsWith('/rubric')) {
        data = rubricView;
      } else if (path.endsWith('/categories')) {
        return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'categories': [
                  {'_id': 'cat-1', 'name': 'Fitness'},
                ],
              },
            }),
            200);
      } else if (path.endsWith('/creator/challenges/ch-1') && req.method == 'PUT') {
        data = {'challenge': {'_id': 'ch-1'}};
      } else if (path.endsWith('/creator/challenges/ch-1')) {
        data = {
          'challenge': {
            '_id': 'ch-1',
            'challengeInstructions': {'whatToCopy': 'Copy the jump', 'timeLimit': 20},
          },
        };
      }
      return http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> open(WidgetTester tester, Map<String, dynamic>? existing) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: CreatorChallengeDraftScreen(existingDraft: existing)));
    await settle(tester);
  }

  testWidgets('a new challenge offers Submit for Approval, not Save Draft, and no free-text criteria field',
      (tester) async {
    await open(tester, null);

    expect(find.text('Submit for Approval'), findsOneWidget);
    expect(find.text('Save Draft'), findsNothing);
    expect(find.text('Save as draft and finish later'), findsOneWidget);
    expect(find.text('e.g. Sync to beat'), findsNothing);
    expect(find.text('Generate scoring criteria'), findsOneWidget);
  });

  testWidgets('generating without a video asks for the video instead of calling the AI',
      (tester) async {
    await open(tester, null);
    await tester.enterText(find.byType(TextField).first, 'Box Jump');
    await tester.tap(find.text('Fitness'));
    await tester.pump();

    await tester.tap(find.text('Generate scoring criteria'));
    await settle(tester);

    expect(find.text('Please add a reference video'), findsOneWidget);
    expect(sent.where((r) => r.url.path.endsWith('/rubric/generate')), isEmpty);
  });

  testWidgets('editing: generate saves the latest details first, then shows the criteria on this page',
      (tester) async {
    await open(tester, draft());
    // Instructions the normalised draft doesn't carry are loaded and prefilled.
    expect(find.text('Copy the jump'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Box Jump v2');
    await tester.tap(find.text('Generate scoring criteria'));
    await settle(tester);
    await settle(tester);

    final put = sent.indexWhere((r) => r.method == 'PUT' && r.url.path.endsWith('/creator/challenges/ch-1'));
    final gen = sent.indexWhere((r) => r.url.path.endsWith('/rubric/generate'));
    expect(put, isNonNegative);
    expect(gen, greaterThan(put));
    expect(jsonDecode(sent[put].body)['title'], 'Box Jump v2');
    expect(find.text('Skill 0'), findsOneWidget);
    expect(find.text('Ask AI for changes'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('submitting without criteria offers to generate and review them first', (tester) async {
    await open(tester, draft());

    await tester.tap(find.byKey(const Key('submit-for-approval')));
    await tester.pumpAndSettle();
    expect(find.text('Scoring criteria needed'), findsOneWidget);

    await tester.tap(find.text('Generate & review'));
    await settle(tester);
    await settle(tester);
    expect(find.text('Skill 0'), findsOneWidget);
    expect(sent.where((r) => r.url.path.endsWith('/submit')), isEmpty);
  });

  testWidgets('after changes are requested the button resubmits', (tester) async {
    rubricView = generated();
    await open(tester, draft(status: 'CHANGES_REQUESTED'));
    expect(find.text('Resubmit for Approval'), findsOneWidget);

    await tester.tap(find.byKey(const Key('submit-for-approval')));
    await settle(tester);
    await settle(tester);

    expect(sent.where((r) => r.url.path.endsWith('/creator/challenges/ch-1/resubmit')), hasLength(1));
  });

  // Regression (2026-10-19): a dropped connection while loading the categories showed
  // "ClientConnection closed before full header was received, uri=…" and no way to retry.
  group('loading the categories', () {
    void categoriesBackend({required int failures}) {
      var calls = 0;
      ApiClient.httpClient = MockClient((req) async {
        sent.add(req);
        if (req.url.path.endsWith('/categories')) {
          calls++;
          if (calls <= failures) {
            throw http.ClientException('Connection closed before full header was received', req.url);
          }
          return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'categories': [
                    {'_id': 'cat-1', 'name': 'Fitness'},
                  ],
                },
              }),
              200);
        }
        return http.Response(jsonEncode({'status': 'success', 'data': {}}), 200);
      });
    }

    Future<void> openNew(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: CreatorChallengeDraftScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300)); // the quiet retry
      await tester.pump();
    }

    testWidgets('one dropped connection is retried quietly', (tester) async {
      categoriesBackend(failures: 1);
      await openNew(tester);
      expect(find.text('Fitness'), findsOneWidget);
      expect(find.byKey(const Key('categories-error')), findsNothing);
    });

    testWidgets('a lasting failure shows a readable message and Try again works', (tester) async {
      categoriesBackend(failures: 2);
      await openNew(tester);

      expect(find.text("We couldn't load the categories. Check your connection and try again."),
          findsOneWidget);
      expect(find.textContaining('ClientConnection'), findsNothing);
      expect(find.textContaining('localhost'), findsNothing);
      expect(find.textContaining('header'), findsNothing);

      await tester.tap(find.byKey(const Key('categories-retry')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Fitness'), findsOneWidget);
      expect(find.byKey(const Key('categories-error')), findsNothing);
    });
  });
}
