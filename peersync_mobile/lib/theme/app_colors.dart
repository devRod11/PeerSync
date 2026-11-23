import 'package:flutter/material.dart';

/// PeerSync's centralized color palette.
class AppColors {
  static const Color primary = Color(0xFF0A2342);
  static const Color background = Color(0xFFF2F5FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFD8E1F0);
  static const Color softIcon = Color(0xFF8291A8);
  static const Color avatar = Color(0xFFDCE5F2);
}

// Backwards-compatible names used by the existing screen widgets.
const ink = AppColors.primary;
const muted = AppColors.muted;
const line = AppColors.border;
const paper = AppColors.background;
const card = AppColors.surface;
