import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_ui.dart';

/// The brand's assets as tiles. Mandatory ones are starred; tapping shows how
/// the brand wants them used (the AI is told the same thing).
class AiBrandAssetsRow extends StatelessWidget {
  final List<AiBrandAsset> assets;

  const AiBrandAssetsRow({super.key, required this.assets});

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return const Text('No brand assets.', style: TextStyle(color: AppColors.textFaint, fontSize: 12));
    }
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: assets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _tile(context, assets[i]),
      ),
    );
  }

  Widget _tile(BuildContext context, AiBrandAsset asset) {
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AiUi.card,
          title: Text('${asset.name}${asset.mandatory ? ' · must be used' : ''}',
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            asset.usageRule.isEmpty ? 'Use it clearly in your ad.' : asset.usageRule,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      ),
      child: Container(
        width: 104,
        decoration: AiUi.cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset.imageUrl.isNotEmpty)
              Image.network(asset.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
            else
              Center(
                child: Icon(
                  asset.kind == 'audio' ? Icons.music_note_rounded : asset.kind == 'video' ? Icons.movie_outlined : Icons.image_outlined,
                  color: Colors.white24,
                  size: 32,
                ),
              ),
            if (asset.mandatory)
              const Positioned(top: 6, right: 6, child: Icon(Icons.star_rounded, color: AiUi.warning, size: 18)),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                asset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
