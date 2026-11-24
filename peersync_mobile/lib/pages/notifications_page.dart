import 'package:flutter/material.dart';

import '../core/a11y/app_a11y.dart';
import '../core/a11y/status_presentation.dart';
import '../core/utils/error_messages.dart';
import '../models/notification.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class NotificationsPage extends StatefulWidget {
  final ValueChanged<int>? onUnreadCountChanged;
  final VoidCallback? onBack;

  const NotificationsPage({
    super.key,
    this.onUnreadCountChanged,
    this.onBack,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String filter = 'All';

  List<AppNotification> _notifications = [];

  bool _isLoading = true;
  bool _isMarkingAllRead = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  void _notifyUnreadCountChanged() {
    widget.onUnreadCountChanged?.call(_unreadCount);
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final notifications = await ApiService.getNotifications();

      if (!mounted) return;

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });

      _notifyUnreadCountChanged();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  List<AppNotification> get _filteredNotifications {
    switch (filter) {
      case 'Unread':
        return _notifications
            .where((notification) => !notification.isRead)
            .toList();

      case 'Announcements':
        return _notifications
            .where(
              (notification) =>
                  notification.relatedCollections.toLowerCase() ==
                  'announcements',
            )
            .toList();

      case 'Activities':
        return _notifications
            .where((notification) {
              final collection =
                  notification.relatedCollections.toLowerCase();

              return collection == 'tasks' || collection == 'submissions';
            })
            .toList();

      default:
        return _notifications;
    }
  }

  int get _unreadCount {
    return _notifications.where((notification) => !notification.isRead).length;
  }

  IconData _notificationIcon(AppNotification notification) {
    switch (notification.relatedCollections.toLowerCase()) {
      case 'announcements':
        return Icons.campaign_outlined;

      case 'tasks':
        return Icons.assignment_outlined;

      case 'submissions':
        return Icons.description_outlined;

      default:
        return Icons.notifications_outlined;
    }
  }

  bool _isToday(DateTime? date) {
    if (date == null) return false;

    final localDate = date.toLocal();
    final now = DateTime.now();

    return localDate.year == now.year &&
        localDate.month == now.month &&
        localDate.day == now.day;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    AppA11y.announce(context, message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _markAsRead(AppNotification notification) async {
    if (notification.isRead) return;

    try {
      await ApiService.updateNotificationReadStatus(
        notificationId: notification.id,
        isRead: true,
      );

      if (!mounted) return;

      setState(() {
        final index = _notifications.indexWhere(
          (item) => item.id == notification.id,
        );

        if (index != -1) {
          _notifications[index] = _notifications[index].copyWith(isRead: true);
        }
      });
      _notifyUnreadCountChanged();
      _showSnack('Notification marked as read.');
    } catch (e) {
      _showSnack(friendlyErrorMessage(e));
    }
  }

  Future<void> _markAllAsRead() async {
    if (_unreadCount == 0 || _isMarkingAllRead) return;

    setState(() {
      _isMarkingAllRead = true;
    });

    try {
      await ApiService.markAllNotificationsAsRead();

      if (!mounted) return;

      setState(() {
        _notifications = _notifications
            .map((notification) => notification.copyWith(isRead: true))
            .toList();

        _isMarkingAllRead = false;
      });
      _notifyUnreadCountChanged();

      _showSnack('All notifications marked as read.');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isMarkingAllRead = false;
      });

      _showSnack(friendlyErrorMessage(e));
    }
  }

  Future<void> _deleteNotification(AppNotification notification) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete notification?',
      message: '"${notification.title}" will be permanently removed.',
    );

    if (!confirmed) return;

    try {
      await ApiService.deleteNotification(notification.id);

      if (!mounted) return;

      setState(() {
        _notifications.removeWhere((item) => item.id == notification.id);
      });
      _notifyUnreadCountChanged();

      _showSnack('Notification deleted.');
    } catch (e) {
      _showSnack(friendlyErrorMessage(e));
    }
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final isUnread = !notification.isRead;
    final timeLabel = AppA11y.relativeTime(notification.createdAt);

    return InfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              _notificationIcon(notification),
              size: 25,
              color: isUnread ? AppColors.info : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              button: true,
              label: [
                if (isUnread) 'Unread notification',
                notification.title,
                notification.description,
                timeLabel,
                if (isUnread) 'Double tap to mark as read',
              ].join('. '),
              child: InkWell(
                onTap: () => _markAsRead(notification),
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: 8),
                            const StatusChip(
                              presentation: StatusPresentation(
                                label: 'Unread',
                                icon: Icons.circle,
                                tone: StatusTone.info,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(notification.description, style: subStyle),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(timeLabel, style: subStyle),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete notification: ${notification.title}',
            icon: const Icon(Icons.delete_outline, size: 22),
            onPressed: () => _deleteNotification(notification),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    final notifications = _filteredNotifications;

    if (notifications.isEmpty) {
      return EmptyStateView(
        icon: Icons.notifications_none,
        title: filter == 'All'
            ? 'No notifications yet'
            : 'No $filter notifications',
        message: filter == 'All'
            ? 'New notifications will appear here.'
            : 'Try a different filter to see other notifications.',
      );
    }

    final todayNotifications = notifications
        .where((notification) => _isToday(notification.createdAt))
        .toList();

    final earlierNotifications = notifications
        .where((notification) => !_isToday(notification.createdAt))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (todayNotifications.isNotEmpty) ...[
          const SectionHeading('Today'),
          ...todayNotifications.map(_buildNotificationCard),
        ],
        if (earlierNotifications.isNotEmpty) ...[
          const SectionHeading('Earlier'),
          ...earlierNotifications.map(_buildNotificationCard),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 22),
              tooltip: 'Back to Dashboard',
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: ScreenHeading(
                title: 'Notifications',
                detail: 'Stay updated across your academic work.',
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                _unreadCount == 1
                    ? '1 unread notification'
                    : '$_unreadCount unread notifications',
                style: subStyle,
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Refresh notifications',
                  onPressed: _isLoading ? null : _loadNotifications,
                  icon: const Icon(Icons.refresh),
                ),
                TextButton(
                  onPressed: _unreadCount == 0 || _isMarkingAllRead
                      ? null
                      : _markAllAsRead,
                  child: _isMarkingAllRead
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Mark all as read',
                          style: TextStyle(fontSize: 13),
                        ),
                ),
              ],
            ),
          ],
        ),

        ChoiceChipsX(
          values: const [
            'All',
            'Unread',
            'Announcements',
            'Activities',
          ],
          selected: filter,
          onSelect: (value) {
            setState(() {
              filter = value;
            });
          },
        ),

        const SizedBox(height: 12),

        if (_isLoading)
          const LoadingView(message: 'Loading notifications…')
        else if (_errorMessage != null)
          ErrorStateView(
            message: _errorMessage!,
            onRetry: _loadNotifications,
          )
        else
          _buildNotificationList(),
      ],
    );
  }
}
