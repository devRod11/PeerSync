
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/authenticated_user.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class ProfilePage extends StatefulWidget {
  final AuthenticatedUser user;

  const ProfilePage({
    super.key,
    required this.user,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _calendarConnected = false;
  bool _calendarLoading = false;
  bool _calendarStatusLoaded = false;

  bool get _isStudent =>
      widget.user.role.toLowerCase() == 'student';

  @override
  void initState() {
    super.initState();

    if (_isStudent) {
      _refreshCalendarStatus();
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'U';
    }

    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _refreshCalendarStatus({
    bool showMessage = false,
  }) async {
    if (_calendarLoading) return;

    setState(() {
      _calendarLoading = true;
    });

    try {
      final response =
          await ApiService.getGoogleCalendarStatus();

      if (!mounted) return;

      setState(() {
        _calendarConnected = response['connected'] == true;
        _calendarStatusLoaded = true;
      });

      if (_calendarConnected && showMessage) {
        _showMessage('Google Calendar is connected.');

        // Perform initial synchronization after OAuth is completed.
        await _syncCalendar();
      } else if (showMessage) {
        _showMessage(
          'Google Calendar is not connected yet.',
        );
      }
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        'Unable to check Google Calendar status: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _calendarLoading = false;
        });
      }
    }
  }

  Future<void> _connectCalendar() async {
    setState(() {
      _calendarLoading = true;
    });

    try {
      final authorizationUrl =
          await ApiService.getGoogleCalendarAuthorizationUrl();

      final uri = Uri.parse(authorizationUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception(
          'Could not open the Google authorization page.',
        );
      }

      if (!mounted) return;

      _showMessage(
        'Complete Google authorization in your browser. '
        'Return here and tap Refresh Status.',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Unable to connect Google Calendar: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _calendarLoading = false;
        });
      }
    }
  }

  Future<void> _syncCalendar() async {
    if (!_calendarConnected) {
      _showMessage(
        'Connect Google Calendar before synchronizing deadlines.',
      );
      return;
    }

    setState(() {
      _calendarLoading = true;
    });

    try {
      final response =
          await ApiService.syncGoogleCalendar();

      if (!mounted) return;

      final message = response['message']?.toString() ??
          'Calendar synchronization request completed.';

      _showMessage(message);
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Calendar synchronization failed: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _calendarLoading = false;
        });
      }
    }
  }

  Future<void> _disconnectCalendar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect Google Calendar?'),
        content: const Text(
          'PeerSync will no longer be able to access or '
          'synchronize your Google Calendar. Existing '
          'calendar events may remain in your Google account.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _calendarLoading = true;
    });

    try {
      await ApiService.disconnectGoogleCalendar();

      if (!mounted) return;

      setState(() {
        _calendarConnected = false;
        _calendarStatusLoaded = true;
      });

      _showMessage('Google Calendar disconnected.');
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Unable to disconnect Google Calendar: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _calendarLoading = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  Widget _buildCalendarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Google Calendar'),

        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    size: 30,
                    color: ink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Deadline synchronization',
                          style: titleStyle,
                        ),
                        Text(
                          _calendarConnected
                              ? 'Your Google Calendar is connected.'
                              : 'Connect your Google account to '
                                  'synchronize project deadlines.',
                          style: subStyle,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _calendarConnected
                        ? Icons.check_circle
                        : Icons.info_outline,
                    color: _calendarConnected
                        ? Colors.green
                        : Colors.orange,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                !_calendarStatusLoaded
                    ? 'Checking connection status...'
                    : _calendarConnected
                        ? 'Status: Connected'
                        : 'Status: Not connected',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 12),

              if (_calendarLoading)
                const Center(
                  child: CircularProgressIndicator(),
                )
              else if (!_calendarConnected) ...[
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Connect Google Calendar',
                    onPressed: _connectCalendar,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlineButtonX(
                    label: 'Refresh Status',
                    onPressed: () =>
                        _refreshCalendarStatus(
                      showMessage: true,
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Sync Deadlines',
                    onPressed: _syncCalendar,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlineButtonX(
                    label: 'Refresh Status',
                    onPressed: () =>
                        _refreshCalendarStatus(),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _disconnectCalendar,
                    child: const Text(
                      'Disconnect Google Calendar',
                      style: TextStyle(
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final student = _isStudent;

    final displayName =
        widget.user.displayName?.trim().isNotEmpty == true
            ? widget.user.displayName!.trim()
            : 'User';

    final accountRole = student ? 'Student' : 'Professor';

    return PageBody(children: [
      const ScreenHeading(
        title: 'Profile & settings',
        detail: 'Manage your account and preferences.',
      ),

      InfoCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFDCE5F2),
              child: Text(
                _getInitials(widget.user.displayName),
                style: const TextStyle(
                  color: ink,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: titleStyle),
                  Text(
                    widget.user.email ?? 'No email available',
                    style: subStyle,
                  ),
                  Text(accountRole, style: subStyle),
                ],
              ),
            ),
          ],
        ),
      ),

      const SectionHeading('Account information'),

      InfoCard(
        child: Column(
          children: [
            DetailLine('Display name', displayName),
            DetailLine(
              'Email address',
              widget.user.email ?? 'Not available',
            ),
            DetailLine('Account role', accountRole),
            DetailLine(
              'Account status',
              widget.user.isActive ? 'Active' : 'Inactive',
            ),
          ],
        ),
      ),

      if (student) _buildCalendarSection(),

      const SectionHeading('Notifications'),

      const SwitchTile(
        title: 'In-app notifications',
        subtitle: 'Announcements, deadlines, and feedback',
      ),

      const SwitchTile(
        title: 'Email notifications',
        subtitle: 'Daily summary and urgent updates',
      ),

      SwitchTile(
        title: student
            ? 'Deadline reminders'
            : 'Pending review reminders',
        subtitle: student
            ? 'Notify me 3 days before'
            : 'Send a daily summary',
        trailing: const Icon(Icons.chevron_right),
      ),

      const SectionHeading('Account'),

      const DataRowTile(
        title: 'Password & security',
        subtitle: 'Manage your account security',
        icon: Icons.lock_outline,
      ),

      DataRowTile(
        title: student ? 'My classes & groups' : 'Class management',
        subtitle: student
            ? 'View your enrolled classes and group'
            : 'Manage your classes and student groups',
        icon: Icons.menu_book_outlined,
      ),

      Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Save changes',
              enabled: false,
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlineButtonX(
              label: 'Cancel',
              onPressed: () =>
                  Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    ]);
  }
}
