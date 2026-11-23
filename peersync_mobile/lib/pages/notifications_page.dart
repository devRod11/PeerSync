import 'package:flutter/material.dart';
import '../models/notification.dart';
import '../services/api_service.dart';
import '../widgets/shared_widgets.dart';

class NotificationsPage extends StatefulWidget {
    final ValueChanged<int>? onUnreadCountChanged;
    final VoidCallback? onBack;

    const NotificationsPage({
      super.key,
      this.onUnreadCountChanged,
      this.onBack
    });

    @override
    State<NotificationsPage> createState() =>
        _NotificationsPageState();
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

  void _notifyUnreadCountChanged() { widget.onUnreadCountChanged?.call(_unreadCount); }

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
        _errorMessage = e.toString();
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

              return collection == 'tasks' ||
                  collection == 'submissions';
            })
            .toList();

      default:
        return _notifications;
    }
  }

  int get _unreadCount {
    return _notifications
        .where((notification) => !notification.isRead)
        .length;
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

  String _formatTime(DateTime? date) {
    if (date == null) return 'Date unavailable';

    final localDate = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDate);

    if (difference.inMinutes < 1 && !difference.isNegative) {
      return 'Just now';
    }

    if (difference.inMinutes < 60 && !difference.isNegative) {
      return '${difference.inMinutes} minutes ago';
    }

    if (difference.inHours < 24 && !difference.isNegative) {
      return '${difference.inHours} hours ago';
    }

    if (difference.inDays < 7 && !difference.isNegative) {
      return '${difference.inDays} days ago';
    }

    return '${localDate.day}/${localDate.month}/${localDate.year}';
  }

  bool _isToday(DateTime? date) {
    if (date == null) return false;

    final localDate = date.toLocal();
    final now = DateTime.now();

    return localDate.year == now.year &&
        localDate.month == now.month &&
        localDate.day == now.day;
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
          _notifications[index] =
              _notifications[index].copyWith(isRead: true);
        }
      });
      _notifyUnreadCountChanged();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update notification: $e'),
        ),
      );
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
            .map((notification) =>
                notification.copyWith(isRead: true))
            .toList();

        _isMarkingAllRead = false;
      });
      _notifyUnreadCountChanged();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isMarkingAllRead = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to mark all as read: $e'),
        ),
      );
    }
  }

  Future<void> _deleteNotification(
    AppNotification notification,
  ) async {
    try {
      await ApiService.deleteNotification(notification.id);

      if (!mounted) return;

      setState(() {
        _notifications.removeWhere(
          (item) => item.id == notification.id,
        );
      });
      _notifyUnreadCountChanged();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification deleted.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to delete notification: $e'),
        ),
      );
    }
  }

  Widget _buildNotificationCard(
    AppNotification notification,
  ) {
    return InfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _notificationIcon(notification),
            size: 25,
            color: notification.isRead
                ? Colors.grey
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _markAsRead(notification),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: notification.isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.description,
                    style: subStyle,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _formatTime(notification.createdAt),
                    style: subStyle,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete notification',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
            ),
            onPressed: () => _deleteNotification(notification),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    final notifications = _filteredNotifications;

    if (notifications.isEmpty) {
      return InfoCard(
        child: Column(
          children: [
            const Icon(
              Icons.notifications_none,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              filter == 'All'
                  ? 'No notifications yet.'
                  : 'No $filter notifications.',
              style: titleStyle,
            ),
            const SizedBox(height: 5),
            const Text(
              'New notifications will appear here.',
              style: subStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final todayNotifications = notifications
        .where((notification) =>
            _isToday(notification.createdAt))
        .toList();

    final earlierNotifications = notifications
        .where((notification) =>
            !_isToday(notification.createdAt))
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 24),
              tooltip: 'Back to Dashboard',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
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
            Text(
              '$_unreadCount unread',
              style: subStyle,
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Refresh notifications',
                  onPressed: _isLoading
                      ? null
                      : _loadNotifications,
                  icon: const Icon(Icons.refresh),
                ),
                TextButton(
                  onPressed: _unreadCount == 0 ||
                          _isMarkingAllRead
                      ? null
                      : _markAllAsRead,
                  child: _isMarkingAllRead
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Mark all as read',
                          style: TextStyle(fontSize: 10),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (_errorMessage != null)
          InfoCard(
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 38,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Unable to load notifications.',
                  style: titleStyle,
                ),
                const SizedBox(height: 6),
                Text(
                  _errorMessage!,
                  style: subStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _loadNotifications,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          )
        else
          _buildNotificationList(),
      ],
    );
  }
}