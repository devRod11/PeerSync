import 'package:flutter/material.dart';

/// Layout breakpoints used across PeerSync.
///
/// The values follow Material 3's window size classes so the same screen works
/// on a phone, a tablet in split view, a laptop and a large desktop monitor.
enum WindowSize {
  /// Phones in portrait, and narrow browser windows. Bottom navigation.
  compact,

  /// Tablets, foldables and small laptop windows. Navigation rail.
  medium,

  /// Desktop browsers and tablets in landscape. Extended rail + two columns.
  expanded,
}

/// Window size classes and their pixel boundaries.
class Breakpoints {
  const Breakpoints._();

  /// Below this width the layout is [WindowSize.compact].
  static const double compactMax = 600;

  /// Below this width the layout is [WindowSize.medium].
  static const double mediumMax = 1024;

  /// Maximum width of a single reading column. Wider than this and text lines
  /// become hard to track, so content is centred instead of stretched.
  static const double readingMax = 720;

  /// Maximum width of a two-column content area.
  static const double contentMax = 1180;

  /// Horizontal page padding for each window size.
  static double pagePadding(WindowSize size) => switch (size) {
        WindowSize.compact => 16,
        WindowSize.medium => 24,
        WindowSize.expanded => 32,
      };
}

/// Resolves the current [WindowSize] from the nearest [MediaQuery].
WindowSize windowSizeOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;

  if (width < Breakpoints.compactMax) return WindowSize.compact;
  if (width < Breakpoints.mediumMax) return WindowSize.medium;
  return WindowSize.expanded;
}

/// Convenience extension for readable call sites.
extension WindowSizeX on WindowSize {
  bool get isCompact => this == WindowSize.compact;
  bool get isMedium => this == WindowSize.medium;
  bool get isExpanded => this == WindowSize.expanded;

  /// True when a persistent side navigation should be shown instead of the
  /// bottom navigation bar.
  bool get usesSideNavigation => this != WindowSize.compact;

  /// Number of columns a dashboard-style grid should use.
  int get gridColumns => switch (this) {
        WindowSize.compact => 1,
        WindowSize.medium => 2,
        WindowSize.expanded => 3,
      };
}

/// Rebuilds [builder] when the window size class changes.
///
/// Using this instead of raw [LayoutBuilder] means a page only rebuilds when it
/// actually crosses a breakpoint, not on every pixel of a window resize.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, WindowSize size) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = switch (constraints.maxWidth) {
          < Breakpoints.compactMax => WindowSize.compact,
          < Breakpoints.mediumMax => WindowSize.medium,
          _ => WindowSize.expanded,
        };

        return builder(context, size);
      },
    );
  }
}

/// Centres and caps the width of page content.
///
/// On a 2560px monitor an unconstrained [ListView] stretches text lines to an
/// unreadable length; this keeps the measure comfortable while still letting
/// wide layouts use more room.
class ResponsiveContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentMax,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// Lays children out in [columns] equal-width columns when the window is wide
/// enough, and stacks them vertically otherwise.
///
/// Unlike a [GridView] this keeps natural heights, which matters for cards of
/// varying length (announcement bodies, submission feedback).
class ResponsiveColumns extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double spacing;

  const ResponsiveColumns({
    super.key,
    required this.children,
    this.columns = 2,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (columns <= 1 || children.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }

    // Distribute children into `columns` buckets, row by row, so reading order
    // stays left-to-right / top-to-bottom for screen readers.
    final rows = <Widget>[];

    for (var index = 0; index < children.length; index += columns) {
      final slice = children.skip(index).take(columns).toList();

      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) SizedBox(width: spacing),
                Expanded(
                  child: column < slice.length
                      ? slice[column]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
