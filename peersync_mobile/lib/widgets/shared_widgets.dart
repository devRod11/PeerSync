import 'package:flutter/material.dart';

import '../core/a11y/status_presentation.dart';
import '../core/responsive/responsive.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Shared, accessible building blocks used across every PeerSync screen.
///
/// The visual language is unchanged (flat cards, 6–8px radii, navy on light
/// background). Each widget now also:
/// * exposes a coherent semantic label instead of a scatter of fragments;
/// * keeps interactive targets at or above 48 x 48 logical pixels;
/// * uses readable minimum font sizes so 200% text scaling reflows;
/// * never relies on color alone to convey status.

const double _minTapTarget = AppTheme.minTapTarget;

class PageBody extends StatelessWidget {
  final List<Widget> children;

  /// Optional override for the reading column width.
  final double? maxWidth;

  const PageBody({super.key, required this.children, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final windowSize = windowSizeOf(context);
    final horizontal = Breakpoints.pagePadding(windowSize);

    // On a phone the column fills the screen. On a tablet or desktop it is
    // capped so text lines stay readable instead of stretching to 2000px.
    final width = maxWidth ??
        (windowSize.isCompact ? double.infinity : Breakpoints.readingMax);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 28),
          children: children
              .map(
                (widget) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: widget,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class ScreenHeading extends StatelessWidget {
  final String title;
  final String? detail;
  final String? eyebrow;

  const ScreenHeading({
    super.key,
    required this.title,
    this.detail,
    this.eyebrow,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(eyebrow!, style: tinyCaps),
            ),
          Semantics(
            header: true,
            child: Text(title, style: headlineStyle),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(detail!, style: subStyle),
            ),
        ],
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;

  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 5),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? action;

  const SectionHeading(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 1),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (action != null)
            Text(
              action!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                decoration: TextDecoration.underline,
              ),
            ),
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final Widget child;

  const InfoCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: card,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

/// Compact status/label pill.
///
/// [dark] renders a navy pill with white text (15.77:1); [danger] renders a
/// red-tinted pill with dark red text (5.53:1). Both are readable and both
/// carry a text label, so color is never the only signal.
class BadgeX extends StatelessWidget {
  final String text;
  final bool dark;
  final bool danger;

  /// Optional screen-reader label when the visible text is abbreviated.
  final String? semanticLabel;

  /// Optional leading icon. Purely decorative; excluded from semantics.
  final IconData? icon;

  const BadgeX(
    this.text, {
    super.key,
    this.dark = false,
    this.danger = false,
    this.semanticLabel,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = dark
        ? Colors.white
        : danger
            ? AppColors.danger
            : AppColors.textSecondary;
    final background = dark
        ? AppColors.primary
        : danger
            ? AppColors.dangerSurface
            : AppColors.neutralSurface;
    final borderColor = dark
        ? AppColors.primary
        : danger
            ? AppColors.danger
            : AppColors.borderStrong;

    return Semantics(
      label: semanticLabel ?? text,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              ExcludeSemantics(
                child: Icon(icon, size: 13, color: foreground),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: .2,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status pill that always pairs an icon, a text label, and a tone color.
class StatusChip extends StatelessWidget {
  final StatusPresentation presentation;

  /// Optional prefix, e.g. "My submission".
  final String? prefix;

  const StatusChip({
    super.key,
    required this.presentation,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final label = prefix == null
        ? presentation.label
        : '$prefix: ${presentation.label}';

    return Semantics(
      label: 'Status: $label',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: presentation.background,
          border: Border.all(color: presentation.foreground),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                presentation.icon,
                size: 14,
                color: presentation.foreground,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: presentation.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  final double value;

  /// Optional label, e.g. "Task completion".
  final String? label;

  const ProgressBar({super.key, required this.value, this.label});

  @override
  Widget build(BuildContext context) {
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();

    return Semantics(
      label: label ?? 'Progress',
      value: '$percent%',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 6,
            backgroundColor: AppColors.border,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String number;
  final String label;
  final bool highlighted;

  const StatTile(
    this.number,
    this.label, {
    super.key,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $number',
      container: true,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.neutralSurface : card,
          border: Border.all(color: line),
        ),
        child: ExcludeSemantics(
          child: Column(
            children: [
              Text(
                number,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MetricsRow extends StatelessWidget {
  final List<(String, String)> items;

  const MetricsRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items.map((entry) {
        return Expanded(
          child: Semantics(
            label: '${entry.$2}: ${entry.$1}',
            container: true,
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Text(
                    entry.$1,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    entry.$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class DataRowTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? leading;
  final String? trailing;
  final IconData? icon;
  final VoidCallback? onTap;

  const DataRowTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: _minTapTarget),
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: card,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          if (leading != null)
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.neutralSurface,
                border: Border.all(color: line),
                shape: BoxShape.circle,
              ),
              child: Text(
                leading!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          if (icon != null)
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.neutralSurface,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
          if (leading != null || icon != null) const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: subStyle,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                trailing!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const ExcludeSemantics(
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.softIcon,
              ),
            ),
        ],
      ),
    );

    final semanticsLabel = [
      title,
      ?subtitle,
      ?trailing,
    ].join('. ');

    if (onTap == null) {
      return MergeSemantics(child: row);
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// When false the button is rendered disabled (and removed from the
  /// accessibility focus order) instead of silently doing nothing.
  final bool enabled;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // `minHeight` (not a fixed `height`) so a label that wraps to two lines
    // grows the button instead of being clipped. The 48px floor still
    // satisfies WCAG 2.2 SC 2.5.8.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTapTarget),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: enabled ? onPressed : null,
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class OutlineButtonX extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// Mirrors [PrimaryButton.enabled] so loading states can disable the action
  /// rather than silently swallowing the tap.
  final bool enabled;

  const OutlineButtonX({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // See PrimaryButton: a minimum height, never a fixed one, so wrapped
    // labels are fully visible.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTapTarget),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            side: const BorderSide(color: AppColors.borderStrong),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: enabled ? onPressed : null,
          child: Text(
            label,
            softWrap: true,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const SearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: hint,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const ExcludeSemantics(
            child: Icon(Icons.search, size: 20),
          ),
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}

class ChoiceChipsX extends StatelessWidget {
  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelect;

  const ChoiceChipsX({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: values.map((value) {
        final isSelected = selected == value;
        return ChoiceChip(
          label: Text(value),
          selected: isSelected,
          onSelected: (_) => onSelect(value),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          side: BorderSide(
            color: isSelected ? ink : AppColors.borderStrong,
          ),
          selectedColor: AppColors.infoSurface,
          backgroundColor: card,
        );
      }).toList(),
    );
  }
}

class TimelineEntry extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? state;
  final String? tag;

  const TimelineEntry(
    this.title,
    this.subtitle, {
    super.key,
    this.state,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = state == 'done';
    final isLate = state == 'late';
    final stateLabel = isDone
        ? 'Completed'
        : isLate
            ? 'Overdue'
            : state == 'active'
                ? 'Active'
                : 'Pending';

    return MergeSemantics(
      child: Semantics(
        label: '$title. $subtitle. $stateLabel',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone ? ink : paper,
                    border: Border.all(
                      color: isDone ? ink : AppColors.borderStrong,
                    ),
                  ),
                  child: Icon(
                    isDone
                        ? Icons.check
                        : isLate
                            ? Icons.priority_high
                            : Icons.circle,
                    size: 13,
                    color: isDone ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(subtitle, style: subStyle),
                  ],
                ),
              ),
              if (tag != null)
                BadgeX(tag!, danger: isLate, dark: state == 'active'),
            ],
          ),
        ),
      ),
    );
  }
}

class DropdownField extends StatelessWidget {
  final List<String> items;
  final String? label;

  const DropdownField({super.key, required this.items, this.label});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: items.isEmpty ? null : items.first,
      isExpanded: true,
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: (_) {},
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

class AttachmentTile extends StatelessWidget {
  final String label;

  const AttachmentTile({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        label: 'Attachment: $label',
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 7),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              const ExcludeSemantics(
                child: Icon(Icons.attach_file, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          constraints: const BoxConstraints(minHeight: _minTapTarget),
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: card,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(5),
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuickTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const QuickTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $subtitle',
      container: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: _minTapTarget),
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: card,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(5),
        ),
        child: ExcludeSemantics(
          child: Column(
            children: [
              Icon(icon, size: 19, color: AppColors.primary),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeadlineCard extends StatelessWidget {
  final String day;
  final String label;
  final String title;
  final String subtitle;
  final bool urgent;

  /// Optional month abbreviation, e.g. "Mar". Omitted when not supplied so
  /// the card never shows a hard-coded month.
  final String? month;

  const DeadlineCard({
    super.key,
    required this.day,
    required this.label,
    required this.title,
    required this.subtitle,
    this.urgent = false,
    this.month,
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        label: '$label. $title. $subtitle',
        child: InfoCard(
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.neutralSurface,
                  ),
                  child: Column(
                    children: [
                      Text(
                        day,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (month != null)
                        Text(
                          month!.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BadgeX(
                      label,
                      danger: urgent,
                      semanticLabel: 'Deadline: $label',
                    ),
                    const SizedBox(height: 5),
                    Text(title, style: titleStyle),
                    Text(subtitle, style: subStyle),
                  ],
                ),
              ),
              const ExcludeSemantics(
                child: Icon(
                  Icons.chevron_right,
                  color: AppColors.softIcon,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SwitchTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const SwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  State<SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<SwitchTile> {
  bool enabled = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: _minTapTarget),
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: card,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(widget.subtitle, style: subStyle),
              ],
            ),
          ),
          widget.trailing ??
              Semantics(
                label: widget.title,
                toggled: enabled,
                child: Switch(
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
              ),
        ],
      ),
    );
  }
}

class DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const DetailLine(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        label: '$label: $value',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: subStyle)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Consistent loading state with a screen-reader announcement.
class LoadingView extends StatelessWidget {
  final String message;

  const LoadingView({super.key, this.message = 'Loading…'});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const ExcludeSemantics(
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 12),
            Text(message, style: subStyle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Consistent empty state.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message == null ? title : '$title. $message',
      child: InfoCard(
        child: Column(
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: 40,
                color: AppColors.softIcon,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: titleStyle,
            ),
            if (message != null) ...[
              const SizedBox(height: 5),
              Text(
                message!,
                style: subStyle,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent error state with a retry action.
///
/// The message is a friendly sentence produced by
/// `friendlyErrorMessage`; raw exception text must not be passed here.
class ErrorStateView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Error. $message',
      child: InfoCard(
        child: Column(
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                size: 36,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlineButtonX(
                  label: retryLabel,
                  onPressed: onRetry!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Accessible confirmation dialog for destructive actions.
///
/// Returns `true` only when the user explicitly confirms. The cancel action
/// receives initial focus so an accidental Enter/Space does not destroy data.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );

  return result ?? false;
}

const headlineStyle = TextStyle(
  fontSize: 23,
  fontWeight: FontWeight.w700,
  letterSpacing: -.6,
  color: AppColors.textPrimary,
  height: 1.25,
);

const titleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w700,
  color: AppColors.textPrimary,
  height: 1.35,
);

const subStyle = TextStyle(
  fontSize: 12,
  color: AppColors.textSecondary,
  height: 1.4,
);

const tinyCaps = TextStyle(
  fontSize: 11,
  color: AppColors.textSecondary,
  letterSpacing: 1,
  fontWeight: FontWeight.w700,
);
