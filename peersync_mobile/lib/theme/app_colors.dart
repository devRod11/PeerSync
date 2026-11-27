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
  static const Color muted = textSecondary;
  static const Color softIcon = Color(0xFF64748B);

  // ---------------------------------------------------------------------
  // Boundaries
  // ---------------------------------------------------------------------
  /// Decorative dividers and card fills only (1.21:1 — not a boundary).
  static const Color border = Color(0xFFD8E1F0);
  static const Color borderStrong = Color(0xFF64748B);
  static const Color avatar = Color(0xFFDCE5F2);
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

  // ---------------------------------------------------------------------
  // Dark theme — comfortable navy/charcoal palette
  // ---------------------------------------------------------------------
  static const Color darkBackground = Color(0xFF111827);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceElevated = Color(0xFF273449);

  static const Color darkTextPrimary = Color(0xFFE5EAF3);
  static const Color darkTextSecondary = Color(0xFFB0BDCF);
  static const Color darkTextMuted = Color(0xFF94A3B8);

  static const Color darkBorder = Color(0xFF334155);
  static const Color darkBorderStrong = Color(0xFF64748B);

  static const Color darkPrimary = Color(0xFF8FB8F0);
  static const Color darkFocus = Color(0xFF93C5FD);

  static const Color darkSuccess = Color(0xFF86EFAC);
  static const Color darkSuccessSurface = Color(0xFF173A2A);

  static const Color darkWarning = Color(0xFFFCD38D);
  static const Color darkWarningSurface = Color(0xFF49351B);

  static const Color darkDanger = Color(0xFFFCA5A5);
  static const Color darkDangerSurface = Color(0xFF482323);

  static const Color darkInfo = Color(0xFF93C5FD);
  static const Color darkInfoSurface = Color(0xFF1E3655);

  static const Color darkNeutral = Color(0xFFCBD5E1);
  static const Color darkNeutralSurface = Color(0xFF334155);
}

// Backwards-compatible names used by the existing screen widgets.
const ink = AppColors.primary;
const muted = AppColors.muted;
const line = AppColors.border;
const paper = AppColors.background;
const card = AppColors.surface;