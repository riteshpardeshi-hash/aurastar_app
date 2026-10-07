// AI Ads — the creator side of brand-funded AI ad campaigns, backed by the
// real backend (backend ADRs 111–115; full contract in AI-ADS-MOBILE-HANDOFF.md
// and GET /docs → "Creator - AI Ad Campaigns").
//
// Flow: a creator joins a brand's campaign (request + accept the ownership
// terms, or accept an invite) → writes a script (AI, refine, or their own) →
// optionally generates keyframe images → generates a video → iterates (edit /
// extend / change audio) → gets it judged by AI → submits a final ad.
// Every AI action is quoted first ([quote]) and the creator confirms the price;
// the backend never charges more than the price it showed ([generate] sends it
// back as `expectedCredits`). Credits are the brand's, allocated per creator.
// Prices = what the AI providers charge + the platform's margin, synced by the
// backend (backend ADR 116). Getting an ad judged is free, up to a number of
// evaluations per creator.
import 'api_client.dart';

// ─── Errors ───────────────────────────────────────────────────────────────────

/// Any AI Ads request the backend refused. [message] is user-presentable.
class AiAdsException implements Exception {
  final int statusCode;
  final String message;

  const AiAdsException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// 402 — the creator's credits don't cover it (nothing ran, nothing charged).
class OutOfAiCreditsException extends AiAdsException {
  const OutOfAiCreditsException([String message = 'You are out of credits']) : super(402, message);
}

/// 409 "The price changed — this now costs N credits" — re-quote and confirm again.
class AiPriceChangedException extends AiAdsException {
  const AiPriceChangedException(String message) : super(409, message);
}

// ─── Parsing helpers ──────────────────────────────────────────────────────────

String _id(dynamic v) => v is Map ? '${v['_id'] ?? ''}' : '${v ?? ''}';
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : _int(v);
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');
List<String> _strings(dynamic v) => v is List ? v.map((e) => '$e').toList() : const [];
List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];

// ─── Campaigns + joining ──────────────────────────────────────────────────────

class AiBrandAsset {
  final String id;
  final String name;
  final String handle;
  final String role;
  final String kind;
  final bool mandatory;
  final String usageRule;

  /// Presigned (1 h) — empty for non-image assets.
  final String imageUrl;

  /// Presigned (1 h) view link for any kind.
  final String viewUrl;

  const AiBrandAsset({
    required this.id,
    required this.name,
    this.handle = '',
    this.role = '',
    this.kind = 'image',
    this.mandatory = false,
    this.usageRule = '',
    this.imageUrl = '',
    this.viewUrl = '',
  });

  factory AiBrandAsset.fromJson(Map<String, dynamic> j) {
    final kind = '${j['kind'] ?? 'image'}';
    final url = '${j['viewUrl'] ?? ''}';
    final role = '${j['role'] ?? ''}';
    final label = '${j['label'] ?? ''}';
    return AiBrandAsset(
      id: _id(j['_id']),
      name: label.isNotEmpty ? label : _roleLabel(role),
      handle: '${j['handle'] ?? ''}',
      role: role,
      kind: kind,
      mandatory: j['mandatory'] == true,
      usageRule: '${j['usageRule'] ?? ''}',
      imageUrl: kind == 'image' ? url : '',
      viewUrl: url,
    );
  }

  static String _roleLabel(String role) => switch (role) {
    'LOGO' => 'Logo',
    'PRODUCT_IMAGE' => 'Product shot',
    'BRAND_VIDEO' => 'Brand video',
    'JINGLE' => 'Jingle',
    'SOUND_EFFECT' => 'Sound effect',
    _ => 'Reference',
  };
}

class AiAdBrief {
  final String product;
  final String objective;
  final String targetAudience;
  final String keyMessage;
  final String tone;
  final String callToAction;
  final List<String> dos;
  final List<String> donts;
  final List<String> forbiddenClaims;

  const AiAdBrief({
    this.product = '',
    this.objective = '',
    this.targetAudience = '',
    this.keyMessage = '',
    this.tone = '',
    this.callToAction = '',
    this.dos = const [],
    this.donts = const [],
    this.forbiddenClaims = const [],
  });

  factory AiAdBrief.fromJson(Map<String, dynamic>? j) {
    final b = j ?? const {};
    return AiAdBrief(
      product: '${b['product'] ?? ''}',
      objective: '${b['objective'] ?? ''}',
      targetAudience: '${b['targetAudience'] ?? ''}',
      keyMessage: '${b['keyMessage'] ?? ''}',
      tone: '${b['tone'] ?? ''}',
      callToAction: '${b['callToAction'] ?? ''}',
      dos: _strings(b['dos']),
      donts: _strings(b['donts']),
      forbiddenClaims: _strings(b['forbiddenClaims']),
    );
  }

  /// One readable paragraph for the brief card.
  String get summary => [
    if (product.isNotEmpty) 'Product: $product.',
    if (objective.isNotEmpty) objective,
    if (keyMessage.isNotEmpty) 'Key message: $keyMessage.',
    if (targetAudience.isNotEmpty) 'For: $targetAudience.',
    if (tone.isNotEmpty) 'Tone: $tone.',
    if (callToAction.isNotEmpty) 'Call to action: $callToAction.',
  ].join(' ');
}

class AiAdFormat {
  final String aspectRatio;
  final int minDurationSeconds;
  final int maxDurationSeconds;
  final String language;

  const AiAdFormat({
    this.aspectRatio = '9:16',
    this.minDurationSeconds = 10,
    this.maxDurationSeconds = 30,
    this.language = 'English',
  });

  factory AiAdFormat.fromJson(Map<String, dynamic>? j) {
    final f = j ?? const {};
    return AiAdFormat(
      aspectRatio: '${f['aspectRatio'] ?? '9:16'}',
      minDurationSeconds: _intOrNull(f['minDurationSeconds']) ?? 10,
      maxDurationSeconds: _intOrNull(f['maxDurationSeconds']) ?? 30,
      language: '${f['language'] ?? 'English'}',
    );
  }
}

/// A creator's place in a campaign.
class AiParticipation {
  final String id;

  /// INVITED, REQUESTED, ACTIVE, SUBMITTED, WINNER, NOT_SELECTED, DECLINED,
  /// REJECTED, REVOKED, WITHDRAWN or REMOVED.
  final String status;
  final int creditsLeft;
  final int allocatedCredits;
  final String? finalGenerationId;
  final int? finalScore;

  const AiParticipation({
    required this.id,
    required this.status,
    this.creditsLeft = 0,
    this.allocatedCredits = 0,
    this.finalGenerationId,
    this.finalScore,
  });

  factory AiParticipation.fromJson(Map<String, dynamic> j) => AiParticipation(
    id: _id(j['_id']),
    status: '${j['status'] ?? ''}',
    creditsLeft: _int(j['creditsLeft']),
    allocatedCredits: _int(j['allocatedCredits']),
    finalGenerationId: j['finalGenerationId'] == null ? null : _id(j['finalGenerationId']),
    finalScore: _intOrNull(j['finalScore']),
  );

  /// Can make things (generate, get judged, change the final pick).
  bool get canWork => status == 'ACTIVE' || status == 'SUBMITTED';
}

class AiCampaignSummary {
  final String id;
  final String title;
  final String product;
  final String objective;
  final DateTime? deadline;
  final int? seatsLeft;

  /// This creator's participation status, or null when they haven't joined.
  final String? myStatus;
  final String participationMode;

  const AiCampaignSummary({
    required this.id,
    required this.title,
    this.product = '',
    this.objective = '',
    this.deadline,
    this.seatsLeft,
    this.myStatus,
    this.participationMode = 'OPEN',
  });

  factory AiCampaignSummary.fromJson(Map<String, dynamic> j) {
    final brief = j['brief'] is Map ? Map<String, dynamic>.from(j['brief']) : const <String, dynamic>{};
    return AiCampaignSummary(
      id: _id(j['_id']),
      title: '${j['title'] ?? ''}',
      product: '${brief['product'] ?? ''}',
      objective: '${brief['objective'] ?? ''}',
      deadline: _date(j['deadline']),
      seatsLeft: _intOrNull(j['seatsLeft']),
      myStatus: j['myStatus'] as String?,
      participationMode: '${j['participationMode'] ?? 'OPEN'}',
    );
  }
}

class AiCampaign {
  final String id;
  final String title;
  final String status;
  final AiAdBrief brief;
  final AiAdFormat format;
  final DateTime? deadline;
  final String participationMode;
  final int? seatsLeft;
  final int? creditsPerCreator;
  final List<AiBrandAsset> assets;
  final AiParticipation? myParticipation;

  const AiCampaign({
    required this.id,
    required this.title,
    required this.status,
    required this.brief,
    required this.format,
    required this.assets,
    this.deadline,
    this.participationMode = 'OPEN',
    this.seatsLeft,
    this.creditsPerCreator,
    this.myParticipation,
  });

  factory AiCampaign.fromJson(Map<String, dynamic> j) => AiCampaign(
    id: _id(j['_id']),
    title: '${j['title'] ?? ''}',
    status: '${j['status'] ?? ''}',
    brief: AiAdBrief.fromJson(j['brief'] as Map<String, dynamic>?),
    format: AiAdFormat.fromJson(j['format'] as Map<String, dynamic>?),
    deadline: _date(j['deadline']),
    participationMode: '${j['participationMode'] ?? 'OPEN'}',
    seatsLeft: _intOrNull(j['seatsLeft']),
    creditsPerCreator: _intOrNull(j['creditsPerCreator']),
    assets: _maps(j['assets']).map(AiBrandAsset.fromJson).toList(),
    myParticipation: j['myParticipation'] is Map
        ? AiParticipation.fromJson(Map<String, dynamic>.from(j['myParticipation']))
        : null,
  );

  bool get isLive => status == 'LIVE';
  bool get isPaused => status == 'PAUSED';

  /// Closed, completed or cancelled — nothing more can be made or submitted.
  bool get hasEnded => status == 'CLOSED' || status == 'COMPLETED' || status == 'CANCELLED';
}

// ─── Workspace ────────────────────────────────────────────────────────────────

enum AiStage { script, image, video }

enum AiGenerationMethod { textToVideo, imagesFirst }

String _stageName(AiStage s) => s.name.toUpperCase();
AiStage _stage(String v) => switch (v) {
  'IMAGE' => AiStage.image,
  'VIDEO' => AiStage.video,
  _ => AiStage.script,
};

class AiPrices {
  final int? scriptUpTo;
  final int? imageEach;

  /// Credits per second (decimal, display only); null = resolution unavailable.
  final Map<String, double?> videoPerSecond;

  const AiPrices({
    this.scriptUpTo,
    this.imageEach,
    this.videoPerSecond = const {},
  });

  factory AiPrices.fromJson(Map<String, dynamic>? j) {
    final p = j ?? const {};
    final video = p['videoPerSecond'] is Map ? Map<String, dynamic>.from(p['videoPerSecond']) : const <String, dynamic>{};
    return AiPrices(
      scriptUpTo: _intOrNull(p['scriptUpTo']),
      imageEach: _intOrNull(p['imageEach']),
      videoPerSecond: video.map((k, v) => MapEntry(k, v is num ? v.toDouble() : null)),
    );
  }

  /// Resolutions the platform has priced (others are unavailable).
  List<String> get resolutions =>
      ['480p', '720p', '1080p'].where((r) => videoPerSecond[r] != null).toList();
}

class AiScriptScene {
  /// Half-second steps (the backend fits the scenes to the chosen length).
  final double durationSeconds;
  final String visual;
  final String voiceover;
  final String onScreenText;

  /// Brand asset handles cued in this scene, e.g. "@img1".
  final List<String> brandAssetCues;

  const AiScriptScene({
    required this.durationSeconds,
    required this.visual,
    this.voiceover = '',
    this.onScreenText = '',
    this.brandAssetCues = const [],
  });

  factory AiScriptScene.fromJson(Map<String, dynamic> j) => AiScriptScene(
    durationSeconds: j['durationSeconds'] is num ? (j['durationSeconds'] as num).toDouble() : double.tryParse('${j['durationSeconds']}') ?? 0,
    visual: '${j['visual'] ?? ''}',
    voiceover: '${j['voiceover'] ?? ''}',
    onScreenText: '${j['onScreenText'] ?? ''}',
    brandAssetCues: _strings(j['brandAssetCues']),
  );
}

/// One AI action (or free hand-written script) in the creator's workspace.
class AiGeneration {
  final String id;
  final AiStage stage;

  /// GENERATE, REFINE, MANUAL_EDIT, EDIT, EXTEND or REAUDIO.
  final String operation;
  final int versionNumber;
  final String? parentId;
  final String instructions;

  /// The script an image set / video follows.
  final String? scriptId;

  /// RUNNING, COMPLETED, FAILED or CANCELLED.
  final String status;
  final String? error;
  final String scriptText;
  final List<AiScriptScene> scenes;

  /// The AI script's headline parts (empty for a hand-written script).
  final String scriptTitle;
  final String scriptHook;
  final String scriptCallToAction;

  /// The video length this version was made for (a script's target, a video's length).
  final int? durationSeconds;
  final List<String> imageUrls;

  /// Storyboard images: the script scene each image shows (parallel to [imageUrls]).
  final List<int> sceneIndexes;

  /// The images this version changed (0-based), when it came from "Change images".
  final List<int> editedImageIndexes;
  final String? videoUrl;
  final int quotedCredits;
  final int chargedCredits;

  /// HELD, SETTLED, REFUNDED or FREE.
  final String chargeState;
  final DateTime? createdAt;

  const AiGeneration({
    required this.id,
    required this.stage,
    required this.operation,
    required this.versionNumber,
    required this.status,
    this.parentId,
    this.instructions = '',
    this.scriptId,
    this.error,
    this.scriptText = '',
    this.scenes = const [],
    this.scriptTitle = '',
    this.scriptHook = '',
    this.scriptCallToAction = '',
    this.durationSeconds,
    this.imageUrls = const [],
    this.sceneIndexes = const [],
    this.editedImageIndexes = const [],
    this.videoUrl,
    this.quotedCredits = 0,
    this.chargedCredits = 0,
    this.chargeState = 'FREE',
    this.createdAt,
  });

  factory AiGeneration.fromJson(Map<String, dynamic> j) {
    final out = j['output'] is Map ? Map<String, dynamic>.from(j['output']) : const <String, dynamic>{};
    final script = out['script'] is Map ? Map<String, dynamic>.from(out['script']) : null;
    return AiGeneration(
      id: _id(j['_id']),
      stage: _stage('${j['stage']}'),
      operation: '${j['operation'] ?? ''}',
      versionNumber: _int(j['versionNumber']),
      parentId: j['parentId'] == null ? null : _id(j['parentId']),
      instructions: '${j['instructions'] ?? ''}',
      scriptId: j['scriptId'] == null ? null : _id(j['scriptId']),
      status: '${j['status'] ?? ''}',
      error: j['error'] as String?,
      scriptText: '${out['text'] ?? ''}',
      scenes: script == null ? const [] : _maps(script['scenes']).map(AiScriptScene.fromJson).toList(),
      scriptTitle: '${script?['title'] ?? ''}',
      scriptHook: '${script?['hook'] ?? ''}',
      scriptCallToAction: '${script?['callToAction'] ?? ''}',
      durationSeconds: j['settings'] is Map && (j['settings'] as Map)['durationSeconds'] is num
          ? ((j['settings'] as Map)['durationSeconds'] as num).toInt()
          : null,
      imageUrls: _strings(out['imageUrls']),
      editedImageIndexes: j['settings'] is Map && (j['settings'] as Map)['editedImageIndexes'] is List
          ? [for (final v in (j['settings'] as Map)['editedImageIndexes'] as List) _int(v)]
          : const [],
      sceneIndexes: out['sceneIndexes'] is List ? [for (final v in out['sceneIndexes'] as List) _int(v)] : const [],
      videoUrl: out['videoUrl'] as String?,
      quotedCredits: _int(j['quotedCredits']),
      chargedCredits: _int(j['chargedCredits']),
      chargeState: '${j['chargeState'] ?? 'FREE'}',
      createdAt: _date(j['createdAt']),
    );
  }

  bool get isRunning => status == 'RUNNING';
  bool get isDone => status == 'COMPLETED';
  bool get wasRefunded => chargeState == 'REFUNDED';
  String get label => '${switch (stage) {
    AiStage.script => 'Script',
    AiStage.image => 'Images',
    AiStage.video => 'Video',
  }} v$versionNumber';
}

/// Free AI evaluations in this campaign (the platform pays for them).
class AiFreeEvaluations {
  final int limit;
  final int used;
  final int left;

  const AiFreeEvaluations({this.limit = 0, this.used = 0, this.left = 0});

  factory AiFreeEvaluations.fromJson(dynamic j) => j is Map
      ? AiFreeEvaluations(limit: _int(j['limit']), used: _int(j['used']), left: _int(j['left']))
      : const AiFreeEvaluations();
}

class AiWorkspace {
  final String campaignStatus;
  final DateTime? deadline;
  final AiAdFormat format;
  final int creditsLeft;
  final int allocatedCredits;
  final AiPrices prices;
  final AiFreeEvaluations freeEvaluations;
  final List<AiGeneration> generations;

  /// A new video may always be this short, even below the brand's minimum (0 = not offered).
  final int shortClipSeconds;

  const AiWorkspace({
    required this.campaignStatus,
    required this.format,
    required this.creditsLeft,
    required this.allocatedCredits,
    required this.prices,
    required this.generations,
    this.freeEvaluations = const AiFreeEvaluations(),
    this.deadline,
    this.shortClipSeconds = 0,
  });

  factory AiWorkspace.fromJson(Map<String, dynamic> j) {
    final c = j['campaign'] is Map ? Map<String, dynamic>.from(j['campaign']) : const <String, dynamic>{};
    return AiWorkspace(
      campaignStatus: '${c['status'] ?? ''}',
      deadline: _date(c['deadline']),
      format: AiAdFormat.fromJson(c['format'] as Map<String, dynamic>?),
      creditsLeft: _int(j['creditsLeft']),
      allocatedCredits: _int(j['allocatedCredits']),
      prices: AiPrices.fromJson(j['prices'] as Map<String, dynamic>?),
      freeEvaluations: AiFreeEvaluations.fromJson(j['freeEvaluations']),
      generations: _maps(j['generations']).map(AiGeneration.fromJson).toList(),
      shortClipSeconds: _int(j['shortClipSeconds']),
    );
  }

  List<AiGeneration> of(AiStage stage) => generations.where((g) => g.stage == stage).toList();
}

/// One AI action to price and run.
class AiAction {
  final AiStage stage;

  /// GENERATE, REFINE, EDIT, EXTEND or REAUDIO.
  final String operation;
  final String? parentId;
  final String? instructions;
  final String? scriptId;
  final int? sceneIndex;
  final int? imageCount;

  /// IMAGE: a storyboard — one keyframe per scene of the script.
  final bool perScene;

  /// IMAGE REFINE: change these images (0-based), each with its own instruction.
  final List<({int imageIndex, String instructions})> edits;

  /// IMAGE REFINE: the image the creator has in each slot (any version) — what edits start from.
  final List<({String generationId, int index})> slotSources;

  /// Keyframes for a video: image generation id + which of its images.
  final List<({String generationId, int index})> keyframes;
  final String? resolution;
  final int? durationSeconds;

  const AiAction({
    required this.stage,
    this.operation = 'GENERATE',
    this.parentId,
    this.instructions,
    this.scriptId,
    this.sceneIndex,
    this.imageCount,
    this.perScene = false,
    this.edits = const [],
    this.slotSources = const [],
    this.keyframes = const [],
    this.resolution,
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
    'stage': _stageName(stage),
    'operation': operation,
    if (parentId != null) 'parentId': parentId,
    if (instructions != null && instructions!.trim().isNotEmpty) 'instructions': instructions!.trim(),
    if (scriptId != null) 'scriptId': scriptId,
    if (sceneIndex != null) 'sceneIndex': sceneIndex,
    if (imageCount != null) 'imageCount': imageCount,
    if (perScene) 'perScene': true,
    if (edits.isNotEmpty) 'edits': [for (final e in edits) {'imageIndex': e.imageIndex, 'instructions': e.instructions.trim()}],
    if (slotSources.isNotEmpty) 'slotSources': [for (final s in slotSources) {'generationId': s.generationId, 'index': s.index}],
    if (keyframes.isNotEmpty) 'keyframes': [for (final k in keyframes) {'generationId': k.generationId, 'index': k.index}],
    if (resolution != null || durationSeconds != null)
      'settings': {
        if (resolution != null) 'resolution': resolution,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
      },
  };
}

class AiQuote {
  final int credits;
  final int creditsLeft;
  final bool canAfford;
  final String note;

  /// Evaluation quotes: free, how many free evaluations are left, and why it
  /// can't run when [canAfford] is false (used up / already judged).
  final bool free;
  final AiFreeEvaluations? freeEvaluations;
  final String? reason;

  const AiQuote({
    required this.credits,
    required this.creditsLeft,
    required this.canAfford,
    this.note = '',
    this.free = false,
    this.freeEvaluations,
    this.reason,
  });

  factory AiQuote.fromJson(Map<String, dynamic> j) {
    final b = j['breakdown'] is Map ? Map<String, dynamic>.from(j['breakdown']) : const <String, dynamic>{};
    return AiQuote(
      credits: _int(j['credits']),
      creditsLeft: _int(j['creditsLeft']),
      canAfford: j['canAfford'] == true,
      note: '${b['note'] ?? ''}',
      free: j['free'] == true,
      freeEvaluations: j['freeEvaluations'] is Map ? AiFreeEvaluations.fromJson(j['freeEvaluations']) : null,
      reason: j['reason'] as String?,
    );
  }
}

// ─── Evaluation ───────────────────────────────────────────────────────────────

class AiCriterionScore {
  final String name;
  final int weight;
  final double score;
  final String reason;

  const AiCriterionScore({required this.name, required this.weight, required this.score, this.reason = ''});

  factory AiCriterionScore.fromJson(Map<String, dynamic> j) => AiCriterionScore(
    name: '${j['name'] ?? ''}',
    weight: _int(j['weight']),
    score: j['score'] is num ? (j['score'] as num).toDouble() : 0,
    reason: '${j['reason'] ?? ''}',
  );
}

class AiEvaluation {
  final String id;
  final String videoGenerationId;

  /// QUEUED, RUNNING, COMPLETED or FAILED.
  final String status;
  final String? error;
  final int? overallScore;
  final List<AiCriterionScore> criteria;
  final List<({String handle, bool present, String note})> mandatoryAssets;
  final bool? mandatoryPass;
  final List<String> forbiddenClaimViolations;
  final List<String> safetyIssues;
  final List<({double? atSeconds, String note})> feedback;
  final List<String> suggestions;
  final String summary;
  final String? composedVideoUrl;
  final int quotedCredits;
  final int chargedCredits;
  final DateTime? createdAt;

  const AiEvaluation({
    required this.id,
    required this.videoGenerationId,
    required this.status,
    this.error,
    this.overallScore,
    this.criteria = const [],
    this.mandatoryAssets = const [],
    this.mandatoryPass,
    this.forbiddenClaimViolations = const [],
    this.safetyIssues = const [],
    this.feedback = const [],
    this.suggestions = const [],
    this.summary = '',
    this.composedVideoUrl,
    this.quotedCredits = 0,
    this.chargedCredits = 0,
    this.createdAt,
  });

  factory AiEvaluation.fromJson(Map<String, dynamic> j) => AiEvaluation(
    id: _id(j['_id']),
    videoGenerationId: _id(j['videoGenerationId']),
    status: '${j['status'] ?? ''}',
    error: j['error'] as String?,
    overallScore: _intOrNull(j['overallScore']),
    criteria: _maps(j['criteria']).map(AiCriterionScore.fromJson).toList(),
    mandatoryAssets: [
      for (final m in _maps(j['mandatoryAssets']))
        (handle: '${m['handle'] ?? ''}', present: m['present'] == true, note: '${m['note'] ?? ''}'),
    ],
    mandatoryPass: j['mandatoryPass'] as bool?,
    forbiddenClaimViolations: _strings(j['forbiddenClaimViolations']),
    safetyIssues: _strings(j['safetyIssues']),
    feedback: [
      for (final f in _maps(j['feedback']))
        (atSeconds: f['atSeconds'] is num ? (f['atSeconds'] as num).toDouble() : null, note: '${f['note'] ?? ''}'),
    ],
    suggestions: _strings(j['suggestions']),
    summary: '${j['summary'] ?? ''}',
    composedVideoUrl: j['composedVideoUrl'] as String?,
    quotedCredits: _int(j['quotedCredits']),
    chargedCredits: _int(j['chargedCredits']),
    createdAt: _date(j['createdAt']),
  );

  bool get isPending => status == 'QUEUED' || status == 'RUNNING';
  bool get isDone => status == 'COMPLETED';
}

class AiCreditRequest {
  final String id;
  final int requestedCredits;
  final int? approvedCredits;

  /// PENDING, APPROVED, REJECTED or CANCELLED.
  final String status;
  final String reason;
  final String brandNote;

  const AiCreditRequest({
    required this.id,
    required this.requestedCredits,
    required this.status,
    this.approvedCredits,
    this.reason = '',
    this.brandNote = '',
  });

  factory AiCreditRequest.fromJson(Map<String, dynamic> j) => AiCreditRequest(
    id: _id(j['_id']),
    requestedCredits: _int(j['requestedCredits']),
    approvedCredits: _intOrNull(j['approvedCredits']),
    status: '${j['status'] ?? ''}',
    reason: '${j['reason'] ?? ''}',
    brandNote: '${j['brandNote'] ?? ''}',
  );
}

class AiReward {
  final String id;
  final String campaignTitle;

  /// PRODUCT, MONEY, COUPON or OTHER.
  final String type;
  final String title;
  final String description;
  final num? value;
  final String currency;
  final String couponCode;

  /// GRANTED, FULFILLED, RECEIVED or CANCELLED.
  final String status;

  const AiReward({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    this.campaignTitle = '',
    this.description = '',
    this.value,
    this.currency = '',
    this.couponCode = '',
  });

  factory AiReward.fromJson(Map<String, dynamic> j) => AiReward(
    id: _id(j['_id']),
    campaignTitle: j['campaignId'] is Map ? '${j['campaignId']['title'] ?? ''}' : '',
    type: '${j['type'] ?? 'OTHER'}',
    title: '${j['title'] ?? ''}',
    description: '${j['description'] ?? ''}',
    value: j['value'] as num?,
    currency: '${j['currency'] ?? ''}',
    couponCode: '${j['couponCode'] ?? ''}',
    status: '${j['status'] ?? ''}',
  );

  bool get canConfirm => status == 'GRANTED' || status == 'FULFILLED';
}

// ─── Service ──────────────────────────────────────────────────────────────────

class AiAdsService {
  AiAdsService._();
  static final AiAdsService _instance = AiAdsService._();
  factory AiAdsService() => _instance;

  final _client = ApiClient();

  // Script and image generation finish inside the request (≈10–60s).
  static const _aiTimeout = Duration(seconds: 120);

  Future<dynamic> _call(String method, String path, {Map<String, dynamic>? body, Duration? timeout}) async {
    final res = await _client.send(method, path, body: body, timeout: timeout);
    if (res.ok) return res.data;
    if (res.statusCode == 402) throw OutOfAiCreditsException(res.message);
    if (res.statusCode == 409 && res.message.toLowerCase().contains('price changed')) {
      throw AiPriceChangedException(res.message);
    }
    throw AiAdsException(res.statusCode, res.message);
  }

  String _campaign(String id) => '/creator/ai-campaigns/$id';

  // Campaigns + joining

  /// Live campaigns this creator can see — optionally only one brand's.
  Future<List<AiCampaignSummary>> listCampaigns({String? brandId}) async {
    final data = await _call('GET', '/creator/ai-campaigns?limit=50${brandId == null ? '' : '&brandId=$brandId'}');
    return _maps((data as Map)['responses']).map(AiCampaignSummary.fromJson).toList();
  }

  /// My invites, requests and campaigns (with the campaign title).
  Future<List<({AiParticipation participation, String campaignId, String title})>> myCampaigns() async {
    final data = await _call('GET', '/creator/ai-campaigns/mine?limit=50');
    return [
      for (final p in _maps((data as Map)['responses']))
        (
          participation: AiParticipation.fromJson(p),
          campaignId: _id(p['campaignId']),
          title: p['campaignId'] is Map ? '${p['campaignId']['title'] ?? ''}' : '',
        ),
    ];
  }

  Future<AiCampaign> fetchCampaign(String id) async =>
      AiCampaign.fromJson(Map<String, dynamic>.from(await _call('GET', _campaign(id)) as Map));

  /// Ask to join an open campaign. The creator has accepted the terms in the UI.
  Future<void> requestToJoin(String id, {String? message}) => _call('POST', '${_campaign(id)}/request', body: {
    'acceptTerms': true,
    if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
  });

  Future<void> respondToInvite(String participationId, {required bool accept}) =>
      _call('POST', '/creator/ai-campaign-invites/$participationId/respond', body: {
        'accept': accept,
        if (accept) 'acceptTerms': true,
      });

  Future<void> withdraw(String id) => _call('POST', '${_campaign(id)}/withdraw');

  // Workspace

  Future<AiWorkspace> fetchWorkspace(String id) async =>
      AiWorkspace.fromJson(Map<String, dynamic>.from(await _call('GET', '${_campaign(id)}/workspace') as Map));

  Future<AiQuote> quote(String id, AiAction action) async =>
      AiQuote.fromJson(Map<String, dynamic>.from(await _call('POST', '${_campaign(id)}/workspace/quote', body: action.toJson()) as Map));

  /// Run [action] at the price the creator saw ([expectedCredits]). Scripts and
  /// images come back finished; videos come back RUNNING — poll [fetchGeneration].
  Future<AiGeneration> generate(String id, AiAction action, {required int expectedCredits}) async =>
      AiGeneration.fromJson(Map<String, dynamic>.from(await _call(
        'POST',
        '${_campaign(id)}/workspace/generations',
        body: {...action.toJson(), 'expectedCredits': expectedCredits},
        timeout: _aiTimeout,
      ) as Map));

  /// A script the creator wrote themselves — free.
  Future<AiGeneration> createOwnScript(String id, String text) async => AiGeneration.fromJson(
    Map<String, dynamic>.from(await _call('POST', '${_campaign(id)}/workspace/scripts', body: {'text': text}) as Map),
  );

  /// A hand-edit of an existing script — free, a new version.
  Future<AiGeneration> editScript(String id, String scriptId, String text) async => AiGeneration.fromJson(
    Map<String, dynamic>.from(
      await _call('POST', '${_campaign(id)}/workspace/generations/$scriptId/script', body: {'text': text}) as Map,
    ),
  );

  Future<AiGeneration> fetchGeneration(String id, String generationId) async => AiGeneration.fromJson(
    Map<String, dynamic>.from(await _call('GET', '${_campaign(id)}/workspace/generations/$generationId') as Map),
  );

  Future<AiGeneration> cancelVideo(String id, String generationId) async => AiGeneration.fromJson(
    Map<String, dynamic>.from(await _call('POST', '${_campaign(id)}/workspace/generations/$generationId/cancel') as Map),
  );

  // Evaluation + final submission

  Future<AiQuote> quoteEvaluation(String id, String videoGenerationId) async => AiQuote.fromJson(
    Map<String, dynamic>.from(
      await _call('POST', '${_campaign(id)}/workspace/generations/$videoGenerationId/evaluate/quote') as Map,
    ),
  );

  /// Judging is free (the platform pays) — up to a number per creator.
  Future<AiEvaluation> requestEvaluation(String id, String videoGenerationId) async => AiEvaluation.fromJson(
    Map<String, dynamic>.from(
      await _call('POST', '${_campaign(id)}/workspace/generations/$videoGenerationId/evaluate') as Map,
    ),
  );

  Future<List<AiEvaluation>> fetchEvaluations(String id) async {
    final data = await _call('GET', '${_campaign(id)}/workspace/evaluations');
    return _maps(data).map(AiEvaluation.fromJson).toList();
  }

  Future<AiEvaluation> fetchEvaluation(String id, String evaluationId) async => AiEvaluation.fromJson(
    Map<String, dynamic>.from(await _call('GET', '${_campaign(id)}/workspace/evaluations/$evaluationId') as Map),
  );

  /// Pick a judged video as the final ad (free; changeable until the deadline).
  Future<AiParticipation> submitFinal(String id, String videoGenerationId) async => AiParticipation.fromJson(
    Map<String, dynamic>.from(
      await _call('POST', '${_campaign(id)}/workspace/generations/$videoGenerationId/submit') as Map,
    ),
  );

  // Credits + rewards

  Future<AiCreditRequest> requestCredits(String id, int credits, {String? reason}) async =>
      AiCreditRequest.fromJson(Map<String, dynamic>.from(await _call('POST', '${_campaign(id)}/credit-requests', body: {
        'credits': credits,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }) as Map));

  Future<List<AiCreditRequest>> myCreditRequests(String id) async =>
      _maps(await _call('GET', '${_campaign(id)}/credit-requests')).map(AiCreditRequest.fromJson).toList();

  Future<List<AiReward>> myRewards() async => _maps(await _call('GET', '/creator/ai-rewards')).map(AiReward.fromJson).toList();

  Future<AiReward> confirmRewardReceived(String rewardId) async =>
      AiReward.fromJson(Map<String, dynamic>.from(await _call('POST', '/creator/ai-rewards/$rewardId/received') as Map));
}
