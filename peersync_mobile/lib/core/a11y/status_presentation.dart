import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'app_a11y.dart';

/// Visual tone of a status indicator. Always paired with an icon and a text
/// label so status is never conveyed by color alone (WCAG 1.4.1).
enum StatusTone { neutral, info, success, warning, danger }

/// Presentation data for one status value.
class StatusPresentation {
  final String label;
  final IconData icon;
  final StatusTone tone;

  const StatusPresentation({
    required this.label,
    required this.icon,
    required this.tone,
  });

  Color get foreground {
    switch (tone) {
      case StatusTone.success:
        return AppColors.success;
      case StatusTone.warning:
        return AppColors.warning;
      case StatusTone.danger:
        return AppColors.danger;
      case StatusTone.info:
        return AppColors.info;
      case StatusTone.neutral:
        return AppColors.neutral;
    }
  }

  Color get background {
    switch (tone) {
      case StatusTone.success:
        return AppColors.successSurface;
      case StatusTone.warning:
        return AppColors.warningSurface;
      case StatusTone.danger:
        return AppColors.dangerSurface;
      case StatusTone.info:
        return AppColors.infoSurface;
      case StatusTone.neutral:
        return AppColors.neutralSurface;
    }
  }

  /// Theme-aware foreground color for status indicators.
  Color foregroundFor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (tone) {
      case StatusTone.success:
        return isDark ? AppColors.darkSuccess : AppColors.success;
      case StatusTone.warning:
        return isDark ? AppColors.darkWarning : AppColors.warning;
      case StatusTone.danger:
        return isDark ? AppColors.darkDanger : AppColors.danger;
      case StatusTone.info:
        return isDark ? AppColors.darkInfo : AppColors.info;
      case StatusTone.neutral:
        return isDark ? AppColors.darkNeutral : AppColors.neutral;
    }
  }

  /// Theme-aware background color for status indicators.
  Color backgroundFor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (tone) {
      case StatusTone.success:
        return isDark
            ? AppColors.darkSuccessSurface
            : AppColors.successSurface;
      case StatusTone.warning:
        return isDark
            ? AppColors.darkWarningSurface
            : AppColors.warningSurface;
      case StatusTone.danger:
        return isDark
            ? AppColors.darkDangerSurface
            : AppColors.dangerSurface;
      case StatusTone.info:
        return isDark
            ? AppColors.darkInfoSurface
            : AppColors.infoSurface;
      case StatusTone.neutral:
        return isDark
            ? AppColors.darkNeutralSurface
            : AppColors.neutralSurface;
    }
  }


  /// Aggregate task status: pending / in_progress / completed.
  factory StatusPresentation.forTask(String status) {
    switch (status.trim().toLowerCase()) {
      case 'completed':
        return const StatusPresentation(
          label: 'Completed',
          icon: Icons.check_circle_outline,
          tone: StatusTone.success,
        );
      case 'in_progress':
        return const StatusPresentation(
          label: 'In progress',
          icon: Icons.timelapse,
          tone: StatusTone.info,
        );
      case 'pending':
      default:
        return const StatusPresentation(
          label: 'Pending',
          icon: Icons.schedule,
          tone: StatusTone.neutral,
        );
    }
  }

  /// Individual submission status: pending / approved / revision_required.
  factory StatusPresentation.forSubmission(String status) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
        return const StatusPresentation(
          label: 'Approved',
          icon: Icons.verified_outlined,
          tone: StatusTone.success,
        );
      case 'revision_required':
        return const StatusPresentation(
          label: 'Revision required',
          icon: Icons.edit_note,
          tone: StatusTone.warning,
        );
      case 'pending':
        return const StatusPresentation(
          label: 'Pending review',
          icon: Icons.hourglass_empty,
          tone: StatusTone.info,
        );
      default:
        return StatusPresentation(
          label: AppA11y.humanizeStatus(status),
          icon: Icons.info_outline,
          tone: StatusTone.neutral,
        );
    }
  }

  /// Milestone status. Note: this is the status of the shared milestone
  /// definition, not a per-group completion state.
  factory StatusPresentation.forMilestone(String status) {
    switch (status.trim().toLowerCase().replaceAll(' ', '_')) {
      case 'completed':
        return const StatusPresentation(
          label: 'Completed',
          icon: Icons.check_circle_outline,
          tone: StatusTone.success,
        );
      case 'in_progress':
        return const StatusPresentation(
          label: 'In progress',
          icon: Icons.timelapse,
          tone: StatusTone.info,
        );
      case 'overdue':
      case 'late':
        return const StatusPresentation(
          label: 'Overdue',
          icon: Icons.error_outline,
          tone: StatusTone.danger,
        );
      case 'pending':
      default:
        return const StatusPresentation(
          label: 'Pending',
          icon: Icons.schedule,
          tone: StatusTone.neutral,
        );
    }
  }

  /// Priority values used by tasks.
  factory StatusPresentation.forPriority(String priority) {
    switch (priority.trim().toLowerCase()) {
      case 'high':
        return const StatusPresentation(
          label: 'High priority',
          icon: Icons.keyboard_double_arrow_up,
          tone: StatusTone.danger,
        );
      case 'low':
        return const StatusPresentation(
          label: 'Low priority',
          icon: Icons.keyboard_arrow_down,
          tone: StatusTone.neutral,
        );
      case 'medium':
      default:
        return const StatusPresentation(
          label: 'Medium priority',
          icon: Icons.drag_handle,
          tone: StatusTone.info,
        );
    }
  }
}
