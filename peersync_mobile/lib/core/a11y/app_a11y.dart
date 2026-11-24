import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Central accessibility helpers.
///
/// Everything here uses Flutter's built-in semantics support; no additional
/// package is required.
class AppA11y {
  const AppA11y._();

  /// Minimum interactive target, mirroring [AppTheme.minTapTarget].
  static const double minTapTarget = 48.0;

  /// True when the platform asks the app to reduce motion
  /// (Android "Remove animations", iOS "Reduce Motion").
  static bool reduceMotion(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations ?? false;
  }

  /// A duration that collapses to zero when reduced motion is requested.
  static Duration motion(
    BuildContext context,
    Duration duration,
  ) {
    return reduceMotion(context) ? Duration.zero : duration;
  }

  /// Announces a short status message to the active screen reader.
  ///
  /// Use sparingly, for state changes that are not already announced by a
  /// focus move (e.g. "Submission sent", "Revision requested").
  static void announce(BuildContext context, String message) {
    if (message.trim().isEmpty) return;

    // `SemanticsService.announce` was deprecated in Flutter 3.35 in favour of
    // the view-scoped `sendAnnouncement`, which is safe with multiple windows.
    final view = View.maybeOf(context);
    if (view == null) return;

    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        message,
        Directionality.maybeOf(context) ?? TextDirection.ltr,
      ),
    );
  }

  /// Human-readable date, e.g. "12 Mar 2026".
  static String formatDate(DateTime? date) {
    if (date == null) return 'Date unavailable';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final local = date.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  /// Human-readable date and time, e.g. "12 Mar 2026, 2:05 PM".
  static String formatDateTime(DateTime? date) {
    if (date == null) return 'Date unavailable';

    final local = date.toLocal();
    final hour24 = local.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour24 < 12 ? 'AM' : 'PM';

    return '${formatDate(local)}, $hour12:$minute $period';
  }

  /// Relative time used by notification and activity feeds.
  static String relativeTime(DateTime? date) {
    if (date == null) return 'Date unavailable';

    final local = date.toLocal();
    final difference = DateTime.now().difference(local);

    if (difference.isNegative) {
      return formatDate(local);
    }

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hr ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';

    return formatDate(local);
  }

  /// Turns a raw task/submission status token into readable text.
  static String humanizeStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'in_progress':
        return 'In progress';
      case 'revision_required':
        return 'Revision required';
      case 'pending':
        return 'Pending review';
      case 'approved':
        return 'Approved';
      case 'completed':
        return 'Completed';
      case 'active':
        return 'Active';
      case 'late':
        return 'Overdue';
      default:
        final normalized = status.replaceAll('_', ' ').trim();
        if (normalized.isEmpty) return 'Unknown';
        return normalized[0].toUpperCase() + normalized.substring(1);
    }
  }
}
