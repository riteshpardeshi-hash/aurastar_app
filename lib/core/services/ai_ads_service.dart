// MOCK: the AI-ads backend endpoints do not exist yet. This service returns
// canned data, keeps the credit balance and jobs in memory, and progresses
// jobs by wall-clock time so the UI can be built and exercised. When the API
// ships, replace the bodies with ApiClient calls and keep the public
// signatures (and the model classes) as they are.

enum AiGenerationMethod { textToVideo, imagesFirst }

/// Lifecycle of one generation job. Images-first jobs start at
/// [generatingImages] and wait at [imagesReady] for the creator to pick
/// images; text-to-video jobs start at [generatingVideo]. [scoring] is the AI
/// judging the finished video against the brand brief.
enum AiJobStatus {
  generatingImages,
  imagesReady,
  generatingVideo,
  scoring,
  scored,
}

class AiBrandAsset {
  final String id;
  final String name;

  /// Empty until the admin-panel upload pipeline exists.
  final String imageUrl;

  const AiBrandAsset({
    required this.id,
    required this.name,
    this.imageUrl = '',
  });
}

class AiAdBrief {
  final String brandName;
  final String brief;
  final List<AiBrandAsset> assets;

  const AiAdBrief({
    required this.brandName,
    required this.brief,
    required this.assets,
  });
}

class AiCreditCosts {
  final int image;
  final int video;

  const AiCreditCosts({required this.image, required this.video});

  /// What the first action of [method] costs: text-to-video renders the video
  /// right away, images-first starts by generating images.
  int firstStepCost(AiGenerationMethod method) =>
      method == AiGenerationMethod.textToVideo ? video : image;
}

class AiGeneratedImage {
  final String id;

  /// Empty while this is a mock.
  final String url;

  const AiGeneratedImage({required this.id, this.url = ''});
}

class AiVideoJob {
  final String id;
  final String brandId;
  final String prompt;
  final AiGenerationMethod method;
  final AiJobStatus status;
  final List<AiGeneratedImage> images;
  final int? score;
  final String? feedback;
  final DateTime createdAt;

  const AiVideoJob({
    required this.id,
    required this.brandId,
    required this.prompt,
    required this.method,
    required this.status,
    required this.images,
    required this.createdAt,
    this.score,
    this.feedback,
  });

  bool get isInProgress =>
      status == AiJobStatus.generatingImages ||
      status == AiJobStatus.generatingVideo ||
      status == AiJobStatus.scoring;
}

class _JobRecord {
  final String id;
  final String brandId;
  final String prompt;
  final AiGenerationMethod method;
  final DateTime createdAt = DateTime.now();
  final List<AiGeneratedImage> images;
  AiJobStatus status;
  DateTime phaseStart = DateTime.now();
  int? score;
  String? feedback;

  _JobRecord({
    required this.id,
    required this.brandId,
    required this.prompt,
    required this.method,
    required this.status,
    required this.images,
  });
}

class AiAdsService {
  AiAdsService._();
  static final AiAdsService _instance = AiAdsService._();
  factory AiAdsService() => _instance;

  static const costs = AiCreditCosts(image: 5, video: 20);

  static const _imagesDuration = Duration(seconds: 6);
  static const _videoDuration = Duration(seconds: 8);
  static const _scoringDuration = Duration(seconds: 4);

  // Per-creator balance (brand-funded), in memory only while this is a mock.
  int _credits = 50;
  final List<_JobRecord> _jobs = [];

  Future<AiAdBrief> fetchBrief(String brandId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const AiAdBrief(
      brandName: 'Brand',
      brief:
          'Create a 15–30 second ad that shows our product in everyday life. '
          'Keep the tone upbeat and authentic, feature the logo in the first '
          'and last seconds, and finish with the tagline.',
      assets: [
        AiBrandAsset(id: 'logo', name: 'Logo'),
        AiBrandAsset(id: 'product', name: 'Product shot'),
        AiBrandAsset(id: 'palette', name: 'Colour palette'),
      ],
    );
  }

  Future<int> fetchCredits(String brandId) async => _credits;

  /// Starts an async generation job. Throws [OutOfAiCreditsException] when the
  /// balance can't cover the first step's cost.
  Future<AiVideoJob> startGeneration({
    required String brandId,
    required String prompt,
    required AiGenerationMethod method,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _spend(costs.firstStepCost(method));
    final record = _JobRecord(
      id: 'job-${_jobs.length + 1}',
      brandId: brandId,
      prompt: prompt,
      method: method,
      status:
          method == AiGenerationMethod.textToVideo
              ? AiJobStatus.generatingVideo
              : AiJobStatus.generatingImages,
      images: List.generate(4, (i) => AiGeneratedImage(id: 'img-$i')),
    );
    _jobs.add(record);
    return _snapshot(record);
  }

  /// Images-first step two: turn the chosen images into a video. Throws
  /// [OutOfAiCreditsException] when the balance can't cover the video cost.
  Future<AiVideoJob> startVideoFromImages(
    String jobId,
    List<String> imageIds,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final record = _jobs.firstWhere((j) => j.id == jobId);
    _advance(record);
    if (record.status != AiJobStatus.imagesReady || imageIds.isEmpty) {
      throw StateError('Job is not ready for video generation');
    }
    _spend(costs.video);
    record.status = AiJobStatus.generatingVideo;
    record.phaseStart = DateTime.now();
    return _snapshot(record);
  }

  Future<List<AiVideoJob>> fetchJobs(String brandId) async {
    final mine = _jobs.where((j) => j.brandId == brandId).toList();
    for (final j in mine) {
      _advance(j);
    }
    return mine.reversed.map(_snapshot).toList();
  }

  Future<AiVideoJob?> fetchJob(String jobId) async {
    for (final j in _jobs) {
      if (j.id == jobId) {
        _advance(j);
        return _snapshot(j);
      }
    }
    return null;
  }

  void _spend(int cost) {
    if (_credits < cost) throw OutOfAiCreditsException();
    _credits -= cost;
  }

  void _advance(_JobRecord r) {
    final elapsed = DateTime.now().difference(r.phaseStart);
    if (r.status == AiJobStatus.generatingImages &&
        elapsed >= _imagesDuration) {
      r.status = AiJobStatus.imagesReady;
      r.phaseStart = DateTime.now();
    } else if (r.status == AiJobStatus.generatingVideo &&
        elapsed >= _videoDuration) {
      r.status = AiJobStatus.scoring;
      r.phaseStart = r.phaseStart.add(_videoDuration);
    }
    if (r.status == AiJobStatus.scoring &&
        DateTime.now().difference(r.phaseStart) >= _scoringDuration) {
      r.status = AiJobStatus.scored;
      r.score = 60 + (r.prompt.length * 7) % 36;
      r.feedback =
          'Matches the upbeat tone and keeps the product front and centre. '
          'The logo could appear earlier and the tagline is missing from the '
          'closing seconds.';
    }
  }

  AiVideoJob _snapshot(_JobRecord r) => AiVideoJob(
    id: r.id,
    brandId: r.brandId,
    prompt: r.prompt,
    method: r.method,
    status: r.status,
    images: r.images,
    score: r.score,
    feedback: r.feedback,
    createdAt: r.createdAt,
  );
}

class OutOfAiCreditsException implements Exception {
  @override
  String toString() => 'You are out of credits';
}
