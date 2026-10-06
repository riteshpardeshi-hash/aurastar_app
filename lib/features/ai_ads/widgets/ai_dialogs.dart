import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import 'ai_ui.dart';

/// The ownership terms every creator accepts before joining. Returns true when accepted.
Future<bool> showAiTermsDialog(BuildContext context, {required String campaignTitle}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AiUi.card,
      title: const Text('Before you join', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: Text(
        'Everything you create in "$campaignTitle" — scripts, images and videos — belongs to the brand. '
        'The brand gives you credits to make your ad with our AI tools, and picks the winners.',
        style: const TextStyle(color: AppColors.textMuted, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        TextButton(
          key: const Key('ai-terms-accept'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('I agree', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return accepted == true;
}

/// Ask the brand for more credits. Returns true when the request was sent.
Future<bool> showRequestCreditsSheet(BuildContext context, {required String campaignId, int suggested = 50}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AiUi.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _RequestCreditsBody(campaignId: campaignId, suggested: suggested),
  );
  return sent == true;
}

// Controllers live in the State (not the caller) so they outlive the sheet's
// closing animation — disposing them on pop throws "used after disposed".
class _RequestCreditsBody extends StatefulWidget {
  final String campaignId;
  final int suggested;

  const _RequestCreditsBody({required this.campaignId, required this.suggested});

  @override
  State<_RequestCreditsBody> createState() => _RequestCreditsBodyState();
}

class _RequestCreditsBodyState extends State<_RequestCreditsBody> {
  late final _amount = TextEditingController(text: '${widget.suggested}');
  final _reason = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final credits = int.tryParse(_amount.text.trim()) ?? 0;
    if (credits < 1) {
      setState(() => _error = 'Enter how many credits you need.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await AiAdsService().requestCredits(widget.campaignId, credits, reason: _reason.text);
      if (mounted) Navigator.pop(context, true);
    } on AiAdsException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.textFaint),
    filled: true,
    fillColor: AiUi.bg,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ask the brand for more credits',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'The brand sees everything you made so far before deciding. They may give you less than you ask for.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('ai-credit-amount'),
            controller: _amount,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('Credits'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('Why? (e.g. two more video tries)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AiUi.danger, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          AiPrimaryButton(label: 'Send request', onPressed: _send, busy: _sending),
        ],
      ),
    );
  }
}

/// Hand-edit a script (free). Returns the new text, or null when cancelled.
Future<String?> showEditScriptDialog(BuildContext context, {required String text}) =>
    showDialog<String>(context: context, builder: (_) => _EditScriptDialog(text: text));

class _EditScriptDialog extends StatefulWidget {
  final String text;

  const _EditScriptDialog({required this.text});

  @override
  State<_EditScriptDialog> createState() => _EditScriptDialogState();
}

class _EditScriptDialogState extends State<_EditScriptDialog> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AiUi.card,
      title: const Text('Edit the script', style: TextStyle(color: Colors.white)),
      content: TextField(
        key: const Key('ai-edit-script'),
        controller: _controller,
        maxLines: 12,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Save (free)')),
      ],
    );
  }
}
