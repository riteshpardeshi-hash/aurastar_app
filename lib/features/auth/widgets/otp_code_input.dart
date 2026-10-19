import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Six boxes for the SMS code, backed by one real (invisible) text field so
/// typing, backspace, paste and keyboard autofill (iOS QuickType, Android
/// autofill) all behave natively. Calls [onCompleted] once all six digits are
/// in. Shakes whenever [shakeTrigger] changes.
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    this.onChanged,
    this.shakeTrigger = 0,
    this.hasError = false,
    this.enabled = true,
    this.length = 6,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final int shakeTrigger;
  final bool hasError;
  final bool enabled;
  final int length;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput> with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF9B30FF);
  static const _error = Color(0xFFFF5C7A);

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    widget.focusNode.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(OtpCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shakeTrigger != widget.shakeTrigger) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    widget.focusNode.removeListener(_rebuild);
    _shake.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted(value);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final focused = widget.focusNode.hasFocus;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Damped sine: a quick left-right wobble that settles.
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Stack(
        children: [
          // Flexible boxes so six fit on a 320 px-wide phone.
          Row(
            children: [
              for (var i = 0; i < widget.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _box(
                      index: i,
                      digit: i < code.length ? code[i] : '',
                      active: focused &&
                          widget.enabled &&
                          (i == code.length || (i == widget.length - 1 && code.length == widget.length)),
                    ),
                  ),
                ),
            ],
          ),
          // The real input sits on top, invisible, so a tap anywhere on the
          // boxes focuses it and long-press offers Paste.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                key: const Key('otp-code-field'),
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                showCursor: false,
                enableInteractiveSelection: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box({required int index, required String digit, required bool active}) {
    final filled = digit.isNotEmpty;
    final borderColor = widget.hasError
        ? _error
        : active
            ? _accent
            : filled
                ? _accent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.14);
    return AnimatedContainer(
      key: Key('otp-box-$index'),
      duration: const Duration(milliseconds: 160),
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? _accent.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: active || widget.hasError ? 1.8 : 1.2),
        boxShadow: active
            ? [BoxShadow(color: _accent.withValues(alpha: 0.30), blurRadius: 14, spreadRadius: 0.5)]
            : null,
      ),
      child: filled
          ? Text(
              digit,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFamily: 'SpaceGrotesk',
              ),
            )
          : active
              ? const _BlinkingCaret()
              : null,
    );
  }
}

class _BlinkingCaret extends StatefulWidget {
  const _BlinkingCaret();

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _blink,
        child: Container(width: 2, height: 24, color: const Color(0xFF9B30FF)),
      );
}
