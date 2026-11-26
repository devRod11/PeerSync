import 'package:flutter/material.dart';

/// PeerSync's centralized color palette.
///
/// The brand identity is unchanged: navy [primary] (`#0A2342`) on the light
/// [background] (`#F2F5FF`). What changed in this revision is the *shade
/// selection* for secondary text, borders, and status indicators, so that
/// every pair meets WCAG 2.2 Level AA contrast:
///
/// * normal text  >= 4.5:1
/// * large text   >= 3:1
/// * UI component boundaries / meaningful graphics >= 3:1
///
/// Measured ratios (WCAG relative-luminance formula) against `#F2F5FF`:
///   primary       14.47:1
///   textSecondary  6.91:1
///   textMuted      5.41:1
///   borderStrong   4.37:1
///   success        6.55:1   warning 6.51:1   danger 5.94:1   info 8.01:1
///
/// The previous `muted` value (`#64748B`) measured 4.37:1 on the app
/// background and therefore failed AA for normal text; it has been darkened
/// to [textSecondary]. The previous `border` value (`#D8E1F0`, 1.21:1) is
/// retained only for purely decorative dividers — anything that forms the
/// only visual boundary of an input or control uses [borderStrong].
class AppColors {
  // ---------------------------------------------------------------------
  // Brand identity (unchanged)
  // ---------------------------------------------------------------------
  static const Color primary = Color(0xFF0A2342);
  static const Color background = Color(0xFFF2F5FF);
  static const Color surface = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------
  // Text tiers (contrast-verified)
  // ---------------------------------------------------------------------
  static const Color textPrimary = primary;
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textMuted = Color(0xFF5A6577);

  /// Legacy alias kept for existing screen code. Now points at the
  /// contrast-safe secondary tier instead of the failing `#64748B`.
  static const Color muted = textSecondary;

  /// Decorative icon tint only. Never the sole carrier of meaning.
  static const Color softIcon = Color(0xFF64748B);

  // ---------------------------------------------------------------------
  // Boundaries
  // ---------------------------------------------------------------------
  /// Decorative dividers and card fills only (1.21:1 — not a boundary).
  static const Color border = Color(0xFFD8E1F0);

  /// Any border that is the only visual boundary of a control (4.37:1).
  static const Color borderStrong = Color(0xFF64748B);

  static const Color avatar = Color(0xFFDCE5F2);

  /// Focus ring. Navy on the light background is 14.47:1.
  static const Color focus = primary;

  // ---------------------------------------------------------------------
  // Status palette — always paired with an icon and a text label so that
  // meaning is never communicated by color alone (WCAG 1.4.1).
  // ---------------------------------------------------------------------
  static const Color success = Color(0xFF166534);
  static const Color successSurface = Color(0xFFE6F2E9);

  static const Color warning = Color(0xFF92400E);
  static const Color warningSurface = Color(0xFFFDF1DF);

  static const Color danger = Color(0xFFB91C1C);
  static const Color dangerSurface = Color(0xFFFBE9E9);

  static const Color info = Color(0xFF1E40AF);
  static const Color infoSurface = Color(0xFFE8EEFB);

  static const Color neutral = Color(0xFF4A5568);
  static const Color neutralSurface = Color(0xFFEDF1F8);
}

// Backwards-compatible names used by the existing screen widgets.
const ink = AppColors.primary;
const muted = AppColors.muted;
const line = AppColors.border;
const paper = AppColors.background;
const card = AppColors.surface;
