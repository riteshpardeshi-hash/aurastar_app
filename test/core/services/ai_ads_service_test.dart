import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/core/services/ai_ads_service.dart';

void main() {
  test('images-first job spends image credits and cannot skip to video', () async {
    final service = AiAdsService();
    final before = await service.fetchCredits('b1');

    final job = await service.startGeneration(
      brandId: 'b1',
      prompt: 'a prompt',
      method: AiGenerationMethod.imagesFirst,
    );

    expect(job.status, AiJobStatus.generatingImages);
    expect(await service.fetchCredits('b1'), before - AiAdsService.costs.image);
    // Images aren't ready yet, so picking them must be rejected (and free).
    await expectLater(
      service.startVideoFromImages(job.id, ['img-0']),
      throwsStateError,
    );
    expect(await service.fetchCredits('b1'), before - AiAdsService.costs.image);
  });

  test('generation is refused once credits run out', () async {
    final service = AiAdsService();
    while (await service.fetchCredits('b2') >= AiAdsService.costs.video) {
      await service.startGeneration(
        brandId: 'b2',
        prompt: 'p',
        method: AiGenerationMethod.textToVideo,
      );
    }
    await expectLater(
      service.startGeneration(
        brandId: 'b2',
        prompt: 'p',
        method: AiGenerationMethod.textToVideo,
      ),
      throwsA(isA<OutOfAiCreditsException>()),
    );
  });
}
