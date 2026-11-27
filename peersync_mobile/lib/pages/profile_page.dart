import 'package:firebase_auth/firebase_auth.dart';
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


  String? _calendarError;

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

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  // ------------------------------------------------------------
  // PASSWORD & SECURITY
  // ------------------------------------------------------------

  String _getPasswordErrorMessage(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Your current password is incorrect.';

      case 'weak-password':
        return 'Your new password is too weak. Use a stronger password.';

      case 'requires-recent-login':
        return 'Your session has expired. Please sign out and sign in again before changing your password.';

      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';

      case 'too-many-requests':
        return 'Too many attempts. Please wait before trying again.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'user-not-found':
        return 'The authenticated account could not be found.';

      default:
        return 'Unable to change your password. Please try again.';
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final formKey = GlobalKey<FormState>();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool loading = false;
    String? errorMessage;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitPasswordChange() async {
              if (loading) return;

              if (!formKey.currentState!.validate()) {
                return;
              }

              final currentPassword =
                  currentPasswordController.text;
              final newPassword = newPasswordController.text;

              setDialogState(() {
                loading = true;
                errorMessage = null;
              });

              try {
                final firebaseUser =
                    FirebaseAuth.instance.currentUser;

                if (firebaseUser == null ||
                    firebaseUser.email == null) {
                  throw FirebaseAuthException(
                    code: 'user-not-found',
                  );
                }

                final hasPasswordProvider = firebaseUser
                    .providerData
                    .any((provider) => provider.providerId == 'password');

                if (!hasPasswordProvider) {
                  throw FirebaseAuthException(
                    code: 'provider-not-supported',
                  );
                }

                final credential =
                    EmailAuthProvider.credential(
                  email: firebaseUser.email!,
                  password: currentPassword,
                );

                // Verify the current password first.
                await firebaseUser.reauthenticateWithCredential(
                  credential,
                );

                // Update the password in Firebase Authentication.
                await firebaseUser.updatePassword(newPassword);

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } on FirebaseAuthException catch (error) {
                String message;

                if (error.code == 'provider-not-supported') {
                  message =
                      'This account does not use email and password authentication.';
                } else {
                  message = _getPasswordErrorMessage(error.code);
                }

                setDialogState(() {
                  errorMessage = message;
                  loading = false;
                });
              } catch (_) {
                setDialogState(() {
                  errorMessage =
                      'An unexpected error occurred. Please try again.';
                  loading = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter your current password and choose a new password for your account.',
                      ),

                      const SizedBox(height: 16),

                      const FieldLabel('Current password'),

                      TextFormField(
                        controller: currentPasswordController,
                        obscureText: obscureCurrent,
                        enabled: !loading,
                        decoration: InputDecoration(
                          hintText: 'Enter current password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: obscureCurrent
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setDialogState(() {
                                obscureCurrent = !obscureCurrent;
                              });
                            },
                            icon: Icon(
                              obscureCurrent
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your current password.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      const FieldLabel('New password'),

                      TextFormField(
                        controller: newPasswordController,
                        obscureText: obscureNew,
                        enabled: !loading,
                        decoration: InputDecoration(
                          hintText: 'Enter new password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: obscureNew
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setDialogState(() {
                                obscureNew = !obscureNew;
                              });
                            },
                            icon: Icon(
                              obscureNew
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter a new password.';
                          }

                          if (value.length < 6) {
                            return 'Use at least 6 characters.';
                          }

                          if (value == currentPasswordController.text) {
                            return 'Your new password must be different.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      const FieldLabel('Confirm new password'),

                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: obscureConfirm,
                        enabled: !loading,
                        decoration: InputDecoration(
                          hintText: 'Confirm new password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: obscureConfirm
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setDialogState(() {
                                obscureConfirm = !obscureConfirm;
                              });
                            },
                            icon: Icon(
                              obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Confirm your new password.';
                          }

                          if (value != newPasswordController.text) {
                            return 'Passwords do not match.';
                          }

                          return null;
                        },
                      ),

                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      const Text(
                        'Your password is securely managed by Firebase Authentication.',
                        style: subStyle,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: loading ? null : submitPasswordChange,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Update Password'),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();

    if (changed == true && mounted) {
      _showMessage('Your password has been updated successfully.');
    }
  }

  // ------------------------------------------------------------
  // GOOGLE CALENDAR
  // ------------------------------------------------------------

  Future<void> _refreshCalendarStatus({
    bool showMessage = false,
  }) async {
    if (_calendarLoading) return;

    setState(() {
      _calendarLoading = true;
      _calendarError = null;
    });

    try {
      final response = await ApiService.getGoogleCalendarStatus();

      if (!mounted) return;

      setState(() {
        _calendarConnected = response['connected'] == true;
        _calendarStatusLoaded = true;
      });

      if (_calendarConnected && showMessage) {
        _showMessage('Google Calendar is connected.');
        await _syncCalendar();
      } else if (showMessage) {
        _showMessage('Google Calendar is not connected yet.');
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _calendarError = error.toString();
      });

      if (showMessage) {
        _showMessage(
          'Unable to check Google Calendar status.',
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

  Future<void> _connectCalendar() async {
    setState(() {
      _calendarLoading = true;
      _calendarError = null;
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
        setState(() {
          _calendarError = error.toString();
        });

        _showMessage('Unable to connect Google Calendar.');
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
      _calendarError = null;
    });

    try {
      final response = await ApiService.syncGoogleCalendar();

      if (!mounted) return;

      final message = response['message']?.toString() ??
          'Calendar synchronization request completed.';

      _showMessage(message);
    } catch (error) {
      if (mounted) {
        setState(() {
          _calendarError = error.toString();
        });

        _showMessage('Calendar synchronization failed.');
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
      _calendarError = null;
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
        setState(() {
          _calendarError = error.toString();
        });

        _showMessage('Unable to disconnect Google Calendar.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _calendarLoading = false;
        });
      }
    }
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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

              if (_calendarError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _calendarError!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],

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
                    onPressed: () => _refreshCalendarStatus(
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
                    onPressed: () => _refreshCalendarStatus(),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _disconnectCalendar,
                    child: const Text(
                      'Disconnect Google Calendar',
                      style: TextStyle(color: Colors.red),
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

  // ------------------------------------------------------------
  // PROFILE SCREEN
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final student = _isStudent;

    final displayName =
        widget.user.displayName?.trim().isNotEmpty == true
            ? widget.user.displayName!.trim()
            : 'User';

    final accountRole = student ? 'Student' : 'Professor';

    return PageBody(
      children: [
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

        const InfoCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: ink,
                size: 28,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification delivery',
                      style: titleStyle,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'PeerSync delivers supported in-app, push, '
                      'and email notifications based on project '
                      'activity and account role. Notification '
                      'preferences are not configurable from '
                      'this screen.',
                      style: subStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SectionHeading('Account'),

        InfoCard(
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.lock_outline,
                color: ink,
              ),
              title: const Text(
                'Password & security',
                style: titleStyle,
              ),
              subtitle: const Text(
                'Change your account password',
                style: subStyle,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showChangePasswordDialog,
            ),
          ),
        ),
      ],
    );
  }
}