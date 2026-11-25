import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/ai_ads_service.dart';
import 'package:aura_app/core/services/app_config_service.dart';
import 'package:aura_app/features/ai_ads/widgets/ai_campaign_bits.dart';
import 'package:aura_app/features/ai_ads/widgets/ai_campaign_spotlight.dart';

import 'ai_ads_fake_backend.dart';

/// Which page dot is the wide (active) one.
int _activeDot(WidgetTester tester) {
  final dots = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)).toList();
  return dots.indexWhere((d) => (d.constraints?.maxWidth ?? 0) == 18);
}

// The creator home's campaign spotlight (client-approved option A, backend ADR 141).
AiCampaignSummary _c(
  String id, {
  String? myStatus,
  int? seatsLeft,
  int? cap,
  Duration due = const Duration(days: 2),
  AiPrize? prize,
}) =>
    AiCampaignSummary(
      id: id,
      title: 'Campaign $id',
      product: 'Lemonade',
      deadline: DateTime.now().add(due),
      seatsLeft: seatsLeft,
      creatorCap: cap,
      myStatus: myStatus,
      brand: AiBrandRef(id: 'b$id', name: 'Brand $id'),
      prize: prize,
      format: const AiAdFormat(aspectRatio: '9:16', minDurationSeconds: 15, maxDurationSeconds: 30),
      creditsPerCreator: 40,
    );

Future<void> _pump(WidgetTester tester, List<AiCampaignSummary> campaigns) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AiCampaignSpotlight(
          loader: () async => campaigns,
          fallback: const Text('FEATURED'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    AppConfigService.instance.couponsEnabled.value = false;
    FakeAiAdsBackend.reset();
  });

  testWidgets('with no open campaigns the usual Featured carousel shows instead', (tester) async {
    await _pump(tester, const []);
    expect(find.text('FEATURED'), findsOneWidget);
    expect(find.byKey(const Key('ai-campaign-spotlight')), findsNothing);
  });

  testWidgets('an open campaign: brand, title, format, seats and a Join button', (tester) async {
    await _pump(tester, [_c('1', seatsLeft: 7, cap: 10)]);
    expect(find.text('FEATURED'), findsNothing);
    expect(find.text('AI Ad Contests'), findsOneWidget);
    expect(find.text('Brand 1'), findsOneWidget);
    expect(find.text('Campaign 1'), findsOneWidget);
    expect(find.text('15–30s vertical AI video · Lemonade'), findsOneWidget);
    expect(find.text('7 of 10 seats left'), findsOneWidget);
    expect(find.text('Join →'), findsOneWidget);
    expect(find.textContaining('left'), findsWidgets); // the time-left chip
  });

  testWidgets('campaigns the creator is in come first, with their next step', (tester) async {
    await _pump(tester, [
      _c('open', due: const Duration(hours: 5)),
      _c('mine', myStatus: 'ACTIVE', due: const Duration(days: 3)),
    ]);
    // First page is the joined one, even though the open one ends sooner.
    expect(find.text('Campaign mine'), findsOneWidget);
    expect(find.text('Create video →'), findsOneWidget);
    expect(find.text('Joined'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Campaign open'), findsOneWidget);
    // Ends within a day: peach "Ends in …" chip.
    expect(find.textContaining('Ends in'), findsOneWidget);
  });

  testWidgets('a pending request shows Pending; a full campaign the creator is not in is left out', (tester) async {
    await _pump(tester, [
      _c('full', seatsLeft: 0, cap: 5),
      _c('req', myStatus: 'REQUESTED'),
    ]);
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Campaign full'), findsNothing);
    // Only one card, so no page dots.
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('the prize shows only while coupons are on (ADR 119)', (tester) async {
    final campaigns = [_c('p', prize: const AiPrize(amount: 5000))];
    await _pump(tester, campaigns);
    expect(find.textContaining('₹5,000'), findsNothing);

    AppConfigService.instance.couponsEnabled.value = true;
    await _pump(tester, campaigns);
    expect(find.textContaining('₹5,000 prize'), findsOneWidget);
  });

  testWidgets('back from a campaign, the reloaded list stays on the card the creator was on', (tester) async {
    // The campaign screen itself isn't under test: the fake backend answers 404 for it.
    FakeAiAdsBackend();
    var list = [_c('a'), _c('b', due: const Duration(days: 3)), _c('c', due: const Duration(days: 4))];
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiCampaignSpotlight(
            loader: () async {
              loads++;
              return list;
            },
            fallback: const Text('FEATURED'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Campaign b'), findsOneWidget);

    Future<void> openAndComeBack() async {
      await tester.tap(find.text('Join →').hitTestable());
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await openAndComeBack();
    expect(loads, 2);
    expect(find.text('Campaign b'), findsOneWidget);
    expect(_activeDot(tester), 1);

    // The list got shorter meanwhile: step back to the last card that still exists.
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Campaign c'), findsOneWidget);
    list = [_c('a'), _c('b', due: const Duration(days: 3))];
    await openAndComeBack();
    expect(find.text('Campaign b'), findsOneWidget);
    expect(_activeDot(tester), 1);
  });

  group('labels', () {
    final now = DateTime(2026, 11, 23, 12);

    test('time left', () {
      expect(AiCampaignBits.timeLeft(now.add(const Duration(days: 2, hours: 6)), now: now), '2d 6h left');
      expect(AiCampaignBits.timeLeft(now.add(const Duration(days: 3)), now: now), '3d left');
      expect(AiCampaignBits.timeLeft(now.add(const Duration(hours: 5)), now: now), 'Ends in 5h');
      expect(AiCampaignBits.timeLeft(now.add(const Duration(minutes: 20)), now: now), 'Ends in 20m');
      expect(AiCampaignBits.timeLeft(now.subtract(const Duration(minutes: 1)), now: now), isNull);
      expect(AiCampaignBits.endsSoon(now.add(const Duration(hours: 23)), now: now), isTrue);
      expect(AiCampaignBits.endsSoon(now.add(const Duration(hours: 25)), now: now), isFalse);
    });

    test('seats', () {
      expect(AiCampaignBits.seatsLabel(7, 10), '7 of 10 seats left');
      expect(AiCampaignBits.seatsLabel(0, 10), 'Full');
      expect(AiCampaignBits.seatsLabel(null, null), 'Open to all');
      expect(AiCampaignBits.seatsTaken(7, 10), closeTo(0.3, 1e-9));
    });

    test('prize amounts', () {
      expect(const AiPrize(amount: 5000).amountLabel, '₹5,000');
      expect(const AiPrize(amount: 150000).amountLabel, '₹1,50,000');
      expect(const AiPrize(amount: 2500, currency: 'USD').amountLabel, 'USD 2,500');
      expect(const AiPrize(description: 'Gift hamper').short, 'Gift hamper');
      expect(AiPrize.fromJson({'currency': 'INR'}), isNull);
      expect(AiPrize.fromJson(null), isNull);
    });

    test('format', () {
      expect(const AiAdFormat(aspectRatio: '1:1', minDurationSeconds: 15, maxDurationSeconds: 15).label, '15s square');
    });
  });
}
