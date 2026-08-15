import 'package:flutter/material.dart';

// Single source of truth for the app's dark palette. Every screen used to
// re-declare its own private `_accent = Color(0xFF7B2CBF)` (50+ files) and
// pick its own alpha value for "muted" secondary text (white38/54/60/70,
// alpha 0.30/0.35/0.45 — six-plus different values for the same semantic
// role across 72 files). `accentLight` formalizes a second color that was
// already in de-facto use across 26 files as an icon/badge/highlight tint,
// distinct from `accent` — not a replacement for it.
class AppColors {
  AppColors._();

  static const background = Color(0xFF080810);
  static const accent = Color(0xFF7B2CBF);
  static const accentLight = Color(0xFFD4A8FF);
  static const textPrimary = Colors.white;

  // white @ 60% — secondary/subtitle/description text that still needs to
  // read comfortably.
  static const textMuted = Color(0x99FFFFFF);

  // white @ 35% — de-emphasized hints/timestamps/barely-there annotations.
  static const textFaint = Color(0x59FFFFFF);
}
