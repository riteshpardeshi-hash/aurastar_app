import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../core/services/ai_ads_service.dart';
import 'ai_ui.dart';

/// Picks a video from the gallery. Tests pass their own.
typedef AiDemoVideoPicker = Future<File?> Function();

Future<File?> _galleryPicker() async {
  final picked = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 90));
  return picked == null ? null : File(picked.path);
}

/// The join-request form (backend ADR 131): the creator's pitch, links to their channels, an
/// optional demo video, and the ownership terms. Returns true when the request was sent.
Future<bool> showJoinRequestSheet(
  BuildContext context, {
  required AiCampaign campaign,
  AiDemoVideoPicker pickVideo = _galleryPicker,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AiUi.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _JoinRequestBody(campaign: campaign, pickVideo: pickVideo),
  );
  return sent == true;
}

const _maxBytes = 100 * 1024 * 1024;
const _pitchMax = 1000;

// Each link field: key sent to the backend, label, and a hint showing what's accepted.
const _linkFields = [
  ('instagram', 'Instagram', '@handle or instagram.com/…'),
  ('youtube', 'YouTube', '@channel or youtube.com/…'),
  ('x', 'X (Twitter)', '@handle or x.com/…'),
  ('facebook', 'Facebook', 'facebook.com/…'),
  ('linkedin', 'LinkedIn', 'linkedin.com/in/…'),
  ('website', 'Website / portfolio', 'yoursite.com'),
];

String _contentTypeFor(String path) => switch (path.split('.').last.toLowerCase()) {
  'mov' => 'video/quicktime',
  'webm' => 'video/webm',
  _ => 'video/mp4',
};

String _size(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

// Controllers live in the State so they outlive the sheet's closing animation.
class _JoinRequestBody extends StatefulWidget {
  final AiCampaign campaign;
  final AiDemoVideoPicker pickVideo;

  const _JoinRequestBody({required this.campaign, required this.pickVideo});

  @override
  State<_JoinRequestBody> createState() => _JoinRequestBodyState();
}

class _JoinRequestBodyState extends State<_JoinRequestBody> {
  final _pitch = TextEditingController();
  late final Map<String, TextEditingController> _links = {
    for (final (key, _, _) in _linkFields) key: TextEditingController(text: widget.campaign.suggestedLinks[key] ?? ''),
  };
  File? _video;
  int _videoBytes = 0;
  bool _agreed = false;
  bool _sending = false;
  double? _progress;
  String? _error;

  @override
  void dispose() {
    _pitch.dispose();
    for (final c in _links.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseVideo() async {
    final file = await widget.pickVideo();
    if (file == null || !mounted) return;
    final bytes = await file.length();
    if (bytes > _maxBytes) {
      setState(() => _error = 'That video is ${_size(bytes)} — keep it under 100 MB.');
      return;
    }
    setState(() {
      _video = file;
      _videoBytes = bytes;
      _error = null;
    });
  }

  Future<void> _send() async {
    final links = {for (final e in _links.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()};
    if (links.isEmpty) {
      setState(() => _error = 'Add at least one link to your work so the brand can see what you make.');
      return;
    }
    if (!_agreed) {
      setState(() => _error = 'Please agree to the campaign terms.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final service = AiAdsService();
    try {
      String? key;
      final video = _video;
      if (video != null) {
        final type = _contentTypeFor(video.path);
        final upload = await service.presignDemoVideo(widget.campaign.id, contentType: type, sizeBytes: _videoBytes);
        setState(() => _progress = 0);
        await service.uploadDemoVideo(upload.uploadUrl, video, type, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
        key = upload.key;
      }
      await service.requestToJoin(widget.campaign.id, message: _pitch.text, links: links, demoVideoKey: key);
      if (mounted) Navigator.pop(context, true);
    } on AiAdsException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
          _error = "Couldn't send your request. Check your connection and try again.";
        });
      }
    }
  }

  InputDecoration _decoration(String hint, {String? label}) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textFaint),
    filled: true,
    fillColor: AiUi.bg,
    isDense: true,
    counterStyle: const TextStyle(color: AppColors.textFaint, fontSize: 11),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
  );

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apply to "${widget.campaign.title}"',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'The brand reviews every request. Show them your work and why you’re the right creator for this ad.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
              ),
              _heading('Your pitch'),
              TextField(
                key: const Key('ai-join-pitch'),
                controller: _pitch,
                maxLines: 5,
                minLines: 3,
                maxLength: _pitchMax,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('Why are you the best fit? Your style, past brand work, your idea for this ad…'),
              ),
              _heading('Your channels (at least one)'),
              for (final (key, label, hint) in _linkFields) ...[
                TextField(
                  key: Key('ai-join-link-$key'),
                  controller: _links[key],
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration(hint, label: label),
                ),
                const SizedBox(height: 8),
              ],
              _heading('Demo video (optional)'),
              if (video == null)
                OutlinedButton.icon(
                  key: const Key('ai-join-add-video'),
                  onPressed: _sending ? null : _chooseVideo,
                  icon: const Icon(Icons.video_library_outlined, size: 18),
                  label: const Text('Add a sample of your work · up to 90s, 100 MB'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AiUi.accent,
                    side: const BorderSide(color: AiUi.accent),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AiUi.bg, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.movie_outlined, color: AiUi.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${video.path.split('/').last} · ${_size(_videoBytes)}',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!_sending)
                        IconButton(
                          key: const Key('ai-join-remove-video'),
                          tooltip: 'Remove video',
                          onPressed: () => setState(() => _video = null),
                          icon: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                        ),
                    ],
                  ),
                ),
              if (_progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress, color: AiUi.accent, backgroundColor: AiUi.bg),
                const SizedBox(height: 4),
                Text('Uploading video… ${((_progress ?? 0) * 100).round()}%',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              InkWell(
                key: const Key('ai-join-terms'),
                onTap: _sending ? null : () => setState(() => _agreed = !_agreed),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _agreed,
                      onChanged: _sending ? null : (v) => setState(() => _agreed = v ?? false),
                      activeColor: AiUi.accent,
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'I agree that everything I create in this campaign — scripts, images and videos — belongs to the brand.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, key: const Key('ai-join-error'), style: const TextStyle(color: AiUi.danger, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('ai-join-send'),
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AiUi.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_sending ? 'Sending…' : 'Send request', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
