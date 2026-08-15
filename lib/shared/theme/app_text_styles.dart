import 'package:flutter/material.dart';
import 'app_colors.dart';

// Single source of truth for the app's type scale. Before this, every one of
// ~30 screens hand-rolled its own inline TextStyle for what were structurally
// the same roles (page title, section header, eyebrow label, body text) —
// title sizes alone ranged 17-38px with weights from the Material default
// all the way to w900. `pubspec.yaml` only registers weights up to 700 (Bold)
// for both ClashDisplay and SpaceGrotesk, so every w800/w900 call site in the
// old code was being synthetically faux-bolded by the renderer on top of
// whatever size was requested — not a deliberate heavier design, a rendering
// artifact. Every tier here is capped at the real w700 face.
//
// Color is intentionally baked in as AppColors.textPrimary (white) on every
// tier — callers needing an accent-colored or muted variant use
// `.copyWith(color: ...)` rather than this file growing a color parameter
// per tier.
class AppTextStyles {
  AppTextStyles._();

  // Big, non-AppBar detail headers (Challenge Detail, Arcade). Was 32-38px
  // at w800/w900 — collapsed to one size, real-weight bold.
  static const heroTitle = TextStyle(
    fontFamily: 'ClashDisplay',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  // Onboarding step titles (Setup, City/Interests, Profile Setup, Phone
  // Auth, Rules, Trust Setup). Was 28-30px at w800/w900.
  static const compactTitle = TextStyle(
    fontFamily: 'ClashDisplay',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  // The "AppBar-equivalent" tier — every ordinary screen title, whether
  // rendered via a real AppBar or a custom back-button+title row. Was
  // 17-22px, ranging from an unstyled Material default up to w800.
  static const screenTitle = TextStyle(
    fontFamily: 'ClashDisplay',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  // Mid-screen section labels ("Details :", "Rewards :", "MY REWARDS", etc).
  // Was 18-20px across w700/bold/w800.
  static const sectionHeader = TextStyle(
    fontFamily: 'ClashDisplay',
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: AppColors.textPrimary,
  );

  // Small tracked-out micro-labels (FEATURED, LEVEL, PAUSED, and Arcade's
  // eyebrow). Was inconsistently 9px/w800/spacing-0.5 in some places and
  // 12px/w900/spacing-3 in others.
  static const eyebrow = TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: AppColors.textPrimary,
  );

  // Baseline body/caption pair. Secondary/faint variants are composed via
  // `.copyWith(color: AppColors.textMuted / AppColors.textFaint)` rather
  // than adding more constants here.
  static const body = TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const caption = TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  // The "first letter of a name in a circle" avatar pattern also drifted
  // (20/w800, 22/bold across 5 files, 26/w800) — folded in here since it's
  // the same "same component, different constant" problem.
  static const avatarInitial = TextStyle(
    fontFamily: 'ClashDisplay',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}
