import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/ai_ads_service.dart';

import '../../features/ai_ads/ai_ads_fake_backend.dart';

// The AI Ads client against the real backend contract (backend ADRs 111–115):
// paths, request bodies, response parsing and error mapping. The backend
// never charges more than the quoted price, so `expectedCredits` must always
// travel with a paid action, and 402/409 must surface as typed errors the UI
// can act on (ask for credits / re-quote).
void main() {
  late FakeAiAdsBackend backend;
  final service = AiAdsService();

  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  group('campaigns', () {
    test('listCampaigns filters by brand and parses the paginated responses', () async {
      backend.on('GET /creator/ai-campaigns', {
        'responses': [
          {'_id': 'c1', 'title': 'Summer Fizz', 'brief': {'product': 'Fizz'}, 'seatsLeft': 2, 'myStatus': 'INVITED', 'participationMode': 'INVITE_ONLY'},
        ],
      });

      final list = await service.listCampaigns(brandId: 'brand-9');

      expect(backend.sent.single.query['brandId'], 'brand-9');
      expect(list.single.title, 'Summer Fizz');
      expect(list.single.product, 'Fizz');
      expect(list.single.seatsLeft, 2);
      expect(list.single.myStatus, 'INVITED');
      expect(list.single.participationMode, 'INVITE_ONLY');
    });

    test('listCampaigns without a brand sends no brandId', () async {
      backend.on('GET /creator/ai-campaigns', {'responses': []});
      await service.listCampaigns();
      expect(backend.sent.single.query.containsKey('brandId'), isFalse);
    });

    test('fetchCampaign parses brief, format, assets and my participation', () async {
      backend.on('GET $base', campaignJson(finalGenerationId: 'v1'));

      final c = await service.fetchCampaign(campaignId);

      expect(c.isLive, isTrue);
      expect(c.brief.summary, contains('Key message: Zero sugar, all zing.'));
      expect(c.brief.forbiddenClaims, ['cures thirst forever']);
      expect(c.format.maxDurationSeconds, 20);
      expect(c.assets.first.name, 'Logo'); // no label → role name
      expect(c.assets.first.imageUrl, 'https://s3/logo.png');
      expect(c.assets.last.name, 'Fizz jingle');
      expect(c.assets.last.imageUrl, isEmpty); // audio has no image
      expect(c.myParticipation!.canWork, isTrue);
      expect(c.myParticipation!.finalGenerationId, 'v1');
    });

    test('a submitted creator can still work; a winner cannot', () {
      expect(AiParticipation.fromJson({'_id': 'p', 'status': 'SUBMITTED'}).canWork, isTrue);
      expect(AiParticipation.fromJson({'_id': 'p', 'status': 'WINNER'}).canWork, isFalse);
      expect(AiParticipation.fromJson({'_id': 'p', 'status': 'REQUESTED'}).canWork, isFalse);
    });

    test('requestToJoin always sends acceptTerms and a trimmed message', () async {
      backend.on('POST $base/request', {});
      await service.requestToJoin(campaignId, message: '  love the brand  ');
      expect(backend.sent.single.body, {'acceptTerms': true, 'message': 'love the brand'});
    });

    test('accepting an invite accepts the terms; declining does not', () async {
      backend.on('POST /creator/ai-campaign-invites/p1/respond', {});
      await service.respondToInvite('p1', accept: true);
      await service.respondToInvite('p1', accept: false);
      expect(backend.sent[0].body, {'accept': true, 'acceptTerms': true});
      expect(backend.sent[1].body, {'accept': false});
    });

    test('myCampaigns reads the populated campaign title', () async {
      backend.on('GET /creator/ai-campaigns/mine', {
        'responses': [
          {'_id': 'p1', 'status': 'ACTIVE', 'creditsLeft': 40, 'campaignId': {'_id': 'c1', 'title': 'Summer Fizz'}},
        ],
      });
      final mine = await service.myCampaigns();
      expect(mine.single.campaignId, 'c1');
      expect(mine.single.title, 'Summer Fizz');
      expect(mine.single.participation.creditsLeft, 40);
    });
  });

  group('workspace', () {
    test('fetchWorkspace parses prices; an unpriced resolution is unavailable', () async {
      backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1')], creditsLeft: 10));

      final ws = await service.fetchWorkspace(campaignId);

      expect(ws.prices.resolutions, ['480p', '720p']);
      expect(ws.freeEvaluations.left, 5);
      expect(ws.freeEvaluations.limit, 5);
      expect(ws.of(AiStage.script).single.scenes.single.visual, 'Can pops');
      expect(ws.format.maxDurationSeconds, 20);
    });

    test('a workspace without freeEvaluations (older backend) reads as none', () {
      final ws = AiWorkspace.fromJson({...workspaceJson(), 'freeEvaluations': null});
      expect(ws.freeEvaluations.limit, 0);
    });

    test('an action serialises only what it sets, with video settings nested', () {
      const action = AiAction(
        stage: AiStage.video,
        scriptId: 's1',
        keyframes: [(generationId: 'i1', index: 1)],
        resolution: '720p',
        durationSeconds: 10,
        instructions: '   ',
      );
      expect(action.toJson(), {
        'stage': 'VIDEO',
        'operation': 'GENERATE',
        'scriptId': 's1',
        'keyframes': [{'generationId': 'i1', 'index': 1}],
        'settings': {'resolution': '720p', 'durationSeconds': 10},
      });
    });

    test('quote posts the action and parses affordability', () async {
      backend.on('POST $base/workspace/quote', quoteJson(9, canAfford: false, creditsLeft: 8));

      final q = await service.quote(campaignId, const AiAction(stage: AiStage.image, scriptId: 's1', imageCount: 3));

      expect(backend.sent.single.body, {'stage': 'IMAGE', 'operation': 'GENERATE', 'scriptId': 's1', 'imageCount': 3});
      expect(q.credits, 9);
      expect(q.canAfford, isFalse);
  
      expect(q.note, 'est.');
    });

    test('generate sends the price the creator saw as expectedCredits', () async {
      backend.on('POST $base/workspace/generations', generationJson(id: 'v1', stage: 'VIDEO', status: 'RUNNING'), status: 201);

      final g = await service.generate(campaignId, const AiAction(stage: AiStage.video, scriptId: 's1'), expectedCredits: 25);

      expect(backend.sent.single.body!['expectedCredits'], 25);
      expect(g.isRunning, isTrue);
      expect(g.label, 'Video v1');
    });

    test('402 becomes OutOfAiCreditsException with the backend message', () async {
      backend.fail('POST $base/workspace/generations', 402, 'This costs 25 credits and you have 10. Ask the brand for more.');

      expect(
        () => service.generate(campaignId, const AiAction(stage: AiStage.script), expectedCredits: 2),
        throwsA(isA<OutOfAiCreditsException>().having((e) => e.message, 'message', contains('Ask the brand for more'))),
      );
    });

    test('409 "price changed" becomes AiPriceChangedException', () async {
      backend.fail('POST $base/workspace/generations', 409, 'The price changed — this now costs 6 credits');
      expect(
        () => service.generate(campaignId, const AiAction(stage: AiStage.script), expectedCredits: 2),
        throwsA(isA<AiPriceChangedException>()),
      );
    });

    test('any other 409 stays a plain AiAdsException', () async {
      backend.fail('POST $base/workspace/generations', 409, 'A video is already running');
      expect(
        () => service.generate(campaignId, const AiAction(stage: AiStage.video), expectedCredits: 2),
        throwsA(isA<AiAdsException>().having((e) => e is AiPriceChangedException, 'is price changed', isFalse)
            .having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('own scripts and script edits post the text (both free)', () async {
      backend.on('POST $base/workspace/scripts', generationJson(id: 's2', operation: 'MANUAL_EDIT'), status: 201);
      backend.on('POST $base/workspace/generations/s1/script', generationJson(id: 's3', version: 2, operation: 'MANUAL_EDIT'));

      await service.createOwnScript(campaignId, 'My script');
      final edited = await service.editScript(campaignId, 's1', 'Edited');

      expect(backend.sent[0].body, {'text': 'My script'});
      expect(backend.sent[1].body, {'text': 'Edited'});
      expect(edited.versionNumber, 2);
    });

    test('cancelVideo hits the cancel route and parses the refund', () async {
      backend.on('POST $base/workspace/generations/v1/cancel', {
        ...generationJson(id: 'v1', stage: 'VIDEO', status: 'CANCELLED'),
        'chargeState': 'REFUNDED',
      });
      final g = await service.cancelVideo(campaignId, 'v1');
      expect(g.wasRefunded, isTrue);
    });
  });

  group('evaluation + submission', () {
    test('requestEvaluation is free — sends no price — and parses the queued job', () async {
      backend.on('POST $base/workspace/generations/v1/evaluate', evaluationJson(status: 'QUEUED'), status: 202);

      final e = await service.requestEvaluation(campaignId, 'v1');

      expect(backend.sent.single.body, isEmpty);
      expect(e.isPending, isTrue);
      expect(e.overallScore, isNull);
    });

    test('a finished evaluation parses scores, missing assets and timed feedback', () async {
      backend.on('GET $base/workspace/evaluations', [evaluationJson()]);

      final e = (await service.fetchEvaluations(campaignId)).single;

      expect(e.isDone, isTrue);
      expect(e.overallScore, 72);
      expect(e.criteria[1].score, 6.5);
      expect(e.mandatoryPass, isFalse);
      expect(e.mandatoryAssets.single, (handle: 'img1', present: false, note: 'Never shown'));
      expect(e.feedback.single.atSeconds, 3.5);
      expect(e.suggestions, isNotEmpty);
    });

    test('quoteEvaluation and submitFinal use the generation routes', () async {
      backend.on('POST $base/workspace/generations/v1/evaluate/quote', evalQuoteJson(left: 0, reason: 'Used up'));
      backend.on('POST $base/workspace/generations/v1/submit', {'_id': 'p1', 'status': 'SUBMITTED', 'finalGenerationId': 'v1', 'finalScore': 72});

      final eq = await service.quoteEvaluation(campaignId, 'v1');
      expect(eq.credits, 0);
      expect(eq.free, isTrue);
      expect(eq.canAfford, isFalse);
      expect(eq.reason, 'Used up');
      expect(eq.freeEvaluations!.left, 0);
      final p = await service.submitFinal(campaignId, 'v1');
      expect(p.status, 'SUBMITTED');
      expect(p.finalScore, 72);
    });
  });

  group('credits + rewards', () {
    test('requestCredits sends the amount and a trimmed reason', () async {
      backend.on('POST $base/credit-requests', {'_id': 'r1', 'requestedCredits': 50, 'status': 'PENDING'}, status: 201);

      final r = await service.requestCredits(campaignId, 50, reason: ' need a 1080p pass ');

      expect(backend.sent.single.body, {'credits': 50, 'reason': 'need a 1080p pass'});
      expect(r.status, 'PENDING');
    });

    test('rewards parse the campaign title; only granted/fulfilled can be confirmed', () async {
      backend.on('GET /creator/ai-rewards', [
        {'_id': 'w1', 'type': 'COUPON', 'title': '20% off', 'couponCode': 'FIZZ20', 'status': 'FULFILLED', 'campaignId': {'title': 'Summer Fizz'}},
        {'_id': 'w2', 'type': 'MONEY', 'title': 'Cash', 'value': 500, 'currency': 'INR', 'status': 'RECEIVED'},
      ]);

      final rewards = await service.myRewards();

      expect(rewards[0].campaignTitle, 'Summer Fizz');
      expect(rewards[0].canConfirm, isTrue);
      expect(rewards[1].value, 500);
      expect(rewards[1].canConfirm, isFalse);
    });

    test('confirmRewardReceived posts to the reward', () async {
      backend.on('POST /creator/ai-rewards/w1/received', {'_id': 'w1', 'type': 'COUPON', 'title': 'x', 'status': 'RECEIVED'});
      final r = await service.confirmRewardReceived('w1');
      expect(r.status, 'RECEIVED');
    });
  });
}
