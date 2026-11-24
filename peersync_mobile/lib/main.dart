import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable, ValueNotifier;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/cache/offline_cache.dart';
import 'core/push/push_notification_service.dart';
import 'core/responsive/responsive.dart';
import 'core/utils/error_messages.dart';
import 'firebase_options.dart';
import 'models/authenticated_user.dart';
import 'pages/activities_page.dart';
import 'pages/announcements_management_page.dart';
import 'pages/class_management_page.dart';
import 'pages/login_page.dart';
import 'pages/my_classes_page.dart';
import 'pages/notifications_page.dart';
import 'pages/professor_dashboard_page.dart';
import 'pages/profile_page.dart';
import 'pages/progress_monitoring_page.dart';
import 'pages/student_announcements_page.dart';
import 'pages/student_dashboard_page.dart';
import 'services/api_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/shared_widgets.dart';

/// Lets the push layer show a banner from outside the widget tree.
final GlobalKey<ScaffoldMessengerState> peersyncMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Background/terminated push messages. On web the Firebase SDK delivers
  // these through `firebase-messaging-sw.js`, so the Dart handler is only
  // registered on mobile (the web platform throws for this API).
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(peersyncBackgroundMessageHandler);
  }

  // Drop cache entries older than three days before the first request runs.
  unawaited(OfflineCache.pruneExpired());

  runApp(const PeerSyncApp());
}

class PeerSyncApp extends StatelessWidget {
  const PeerSyncApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PeerSync',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        scaffoldMessengerKey: peersyncMessengerKey,
        home: const AuthGate(),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _authStateChanges;
  late final Future<void> _sessionInitialization;

  String? _profileUid;
  bool _isLoginInProgress = false;
  bool _loginAttemptFailed = false;
  Future<AuthenticatedUser?>? _profileFuture;

  @override
  void initState() {
    super.initState();
    // Create the auth stream once. Recreating it in build() can cause
    // StreamBuilder to resubscribe during login-triggered rebuilds.
    _authStateChanges = FirebaseAuth.instance.authStateChanges();
    _sessionInitialization = _prepareSession();
  }

  // Apply Remember Me before routing an existing Firebase session.
  // If disabled, sign out on the next cold app launch.
  Future<void> _prepareSession() async {
    final preferences = await SharedPreferences.getInstance();
    final rememberMe = preferences.getBool('peersync_remember_me') ?? true;

    if (!rememberMe && FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<AuthenticatedUser?> _getUserProfile(User user) {
    // Reuse the same Future while the authenticated UID remains unchanged.
    if (_profileUid != user.uid || _profileFuture == null) {
      _profileUid = user.uid;
      _profileFuture = _loadUserProfile();
    }

    return _profileFuture!;
  }

  Future<AuthenticatedUser?> _loadUserProfile() async {
    try {
      final authenticatedUser =
          await ApiService.getAuthenticatedUser();

      // Ensure the backend returned the profile belonging
      // to the currently authenticated Firebase account.
      if (authenticatedUser.uid != FirebaseAuth.instance.currentUser?.uid) {
        await FirebaseAuth.instance.signOut();
        return null;
      }

      if (!authenticatedUser.isActive) {
        await FirebaseAuth.instance.signOut();
        return null;
      }

      return authenticatedUser;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await FirebaseAuth.instance.signOut();
        return null;
      }

      rethrow;
    }
  }

  void _retryProfileCheck() {
    setState(() {
      _profileUid = null;
      _profileFuture = null;
    });
  }

  void _handleLoginAttemptStarted() {
    if (!mounted) return;
    setState(() {
      _isLoginInProgress = true;
      _loginAttemptFailed = false;
    });
  }

  void _handleLoginAttemptFinished(bool succeeded) {
    if (!mounted) return;
    setState(() {
      _isLoginInProgress = false;
      _loginAttemptFailed = !succeeded;
    });
  }

  Widget _loginPage() {
    return Scaffold(
      body: SafeArea(
        child: LoginPage(
          key: const ValueKey('peersync-login-page'),
          onLogin: (_) {},
          onLoginAttemptStarted: _handleLoginAttemptStarted,
          onLoginAttemptFinished: _handleLoginAttemptFinished,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _sessionInitialization,
      builder: (context, initializationSnapshot) {
        if (initializationSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: LoadingView(message: 'Starting PeerSync…'),
          );
        }

        if (initializationSnapshot.hasError) {
          return const Scaffold(
            body: ErrorStateView(
              message: 'Unable to initialize your login session. '
                  'Please restart the app and try again.',
            ),
          );
        }

        return _buildAuthStream();
      },
    );
  }

  Widget _buildAuthStream() {
    return StreamBuilder<User?>(
      stream: _authStateChanges,
      builder: (context, authSnapshot) {
        // Keep the existing LoginPage mounted while a login attempt is
        // underway, even if the stream is temporarily waiting.
        if (_isLoginInProgress) {
          return _loginPage();
        }

        // Firebase is checking the current authentication session.
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: LoadingView(message: 'Checking your session…'),
          );
        }

        if (authSnapshot.hasError) {
          return const Scaffold(
            body: ErrorStateView(
              message: 'Unable to check your login session. '
                  'Please check your connection and try again.',
            ),
          );
        }

        final user = authSnapshot.data;

        // Keep the LoginPage mounted while credentials and the Firestore
        // profile are being validated. This prevents authStateChanges() from
        // replacing the page and clearing role-mismatch/error messages.
        // A failed attempt may briefly leave a stale non-null stream value;
        // keep showing LoginPage until Firebase publishes the sign-out state.
        if (_loginAttemptFailed && user != null) {
          return _loginPage();
        }

        // No authenticated user: display Login Page.
        if (user == null) {
          _profileUid = null;
          _profileFuture = null;
          return _loginPage();
        }

        // An authenticated user must also have a valid backend-verified profile.
        return FutureBuilder<AuthenticatedUser?>(
          key: ValueKey(user.uid),
          future: _getUserProfile(user),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Scaffold(
                body: LoadingView(message: 'Loading your account…'),
              );
            }

            if (profileSnapshot.hasError) {
              return Scaffold(
                body: ErrorStateView(
                  message: friendlyErrorMessage(profileSnapshot.error!),
                  onRetry: _retryProfileCheck,
                ),
              );
            }

            final authenticatedUser = profileSnapshot.data;

            // Invalid or rejected profile: sign-out will trigger authStateChanges().
            if (authenticatedUser == null) {
              return const Scaffold(
                body: LoadingView(message: 'Signing you out…'),
              );
            }

            final accountRole = authenticatedUser.role.trim().toLowerCase();

            return PeerSyncShell(
              role: accountRole == 'professor' ? 'Professor' : 'Student',
              user: authenticatedUser,
            );
          },
        );
      },
    );
  }

}

class PeerSyncShell extends StatefulWidget {
  final String role;
  final AuthenticatedUser user;

  const PeerSyncShell({
    super.key,
    required this.role,
    required this.user,
  });

  @override
  State<PeerSyncShell> createState() => _PeerSyncShellState();
}

class _PeerSyncShellState extends State<PeerSyncShell>
    with WidgetsBindingObserver {
    late int current;
    late String role;
    int _unreadNotificationCount = 0;

    // Signals NotificationsPage whenever a push message arrives.
    final ValueNotifier<int> _notificationRefreshSignal =
        ValueNotifier<int>(0);

    @override
    void initState() {
      super.initState();
      WidgetsBinding.instance.addObserver(this);

      role = widget.role;
      current = role == 'Student' ? 6 : 1;

      unawaited(_refreshUnreadNotificationCount());

      // Push is optional: a denied permission or an unsupported browser simply
      // leaves the in-app notification list as the source of truth.
      PushNotificationService.setMessageHandler(_handlePushMessage);
      unawaited(PushNotificationService.initialize(role: role));
    }

    @override
    void dispose() {
      PushNotificationService.setMessageHandler(null);

      _notificationRefreshSignal.dispose();
      WidgetsBinding.instance.removeObserver(this);

      super.dispose();
    }
    Future<void> _refreshUnreadNotificationCount() async {
      try {
        final notifications = await ApiService.getNotifications();

        if (!mounted) return;

        setState(() {
          _unreadNotificationCount =
              notifications.where((notification) => !notification.isRead).length;
        });
      } catch (_) {
        // Keep the current badge value if the request fails.
      }
    }

    void _setUnreadNotificationCount(int count) {
      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = count;
      });
    }

    /// Handles incoming push messages.
    ///
    /// A push is a signal to retrieve the latest notification records
    /// from the backend. It does not create notification records locally.
    void _handlePushMessage(PushMessage message) {
      if (!mounted) return;

      // Tell the Notifications page to fetch the latest notifications.
      _notificationRefreshSignal.value++;

      // Update the unread badge as well.
      unawaited(_refreshUnreadNotificationCount());

      final destination = _destinationIndex(message.destination);
      final messenger = ScaffoldMessenger.maybeOf(context);

      if (messenger == null) return;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Semantics(
              liveRegion: true,
              child: Text(
                message.body.isEmpty
                    ? message.title
                    : '${message.title}. ${message.body}',
              ),
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => go(destination),
            ),
          ),
        );
    }

    @override
    void didChangeAppLifecycleState(AppLifecycleState state) {
      if (state == AppLifecycleState.resumed && mounted) {
        _notificationRefreshSignal.value++;
        unawaited(_refreshUnreadNotificationCount());
      }
    }

    /// Maps a push destination to the shell's page index for the current role.
    int _destinationIndex(String destination) {
      final student = role == 'Student';

      return switch (destination) {
        'dashboard' => student ? 6 : 1,
        'activities' => student ? 8 : 5,
        'announcements' => student ? 9 : 4,
        'notifications' => 10,
        _ => student ? 6 : 1,
      };
    }

    List<(String, IconData, int)> _navItems(String navRole) {
      final student = navRole == 'Student';

      return student
          ? const [
              ('Dashboard', Icons.home_outlined, 6),
              ('My Classes', Icons.menu_book_outlined, 7),
              ('Activities', Icons.description_outlined, 8),
              ('Updates', Icons.campaign_outlined, 9),
              ('Profile', Icons.person_outline, 11),
            ]
          : const [
              ('Dashboard', Icons.home_outlined, 1),
              ('Classes', Icons.menu_book_outlined, 2),
              ('Progress', Icons.bar_chart, 3),
              ('Updates', Icons.campaign_outlined, 4),
              ('Profile', Icons.person_outline, 11),
            ];
    }

    void go(int index) {
      setState(() {
        current = index.clamp(0, 11).toInt();
      });

      if (index == 10) {
        unawaited(_refreshUnreadNotificationCount());
      }
    }

    @override
    Widget build(BuildContext context) {
      final isStudent = current == 6 ||
          current == 7 ||
          current == 8 ||
          current == 9 ||
          (current == 11 && role == 'Student');
      final screenRole = current == 0 || current == 10 || current == 11
          ? (current == 11 ? role : 'Shared')
          : (isStudent ? 'Student' : 'Professor');
      final activeLabel = current == 11
          ? 'Profile'
          : current == 10
              ? ''
              : (isStudent
                  ? (current == 7
                      ? 'My Classes'
                      : current == 8
                          ? 'Activities'
                          : current == 9
                              ? 'Announcements'
                              : 'Dashboard')
                  : (current == 2
                      ? 'Classes'
                      : current == 3
                          ? 'Progress'
                          : current == 4
                              ? 'Announcements'
                              : current == 5
                                  ? 'Classes'
                                  : 'Dashboard'));

      final windowSize = windowSizeOf(context);
      final items = _navItems(screenRole == 'Shared' ? role : screenRole);

      // Full-screen pages (login splash, notifications) keep the simple layout.
      final useSideNavigation = windowSize.usesSideNavigation &&
          current != 0 &&
          current != 10;

      final content = Column(
        children: [
          // Offline banner: announced politely so a screen reader user knows why
          // data may be stale, without interrupting what they are doing.
          ValueListenableBuilder<bool>(
            valueListenable: ApiService.offline,
            builder: (context, isOffline, _) => isOffline
                ? _OfflineBanner(onRetry: () => go(current))
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: SafeArea(
              child: _page(
                current,
                role,
                go,
                (r) => setState(() => role = r),
                widget.user,
                _setUnreadNotificationCount,
                _notificationRefreshSignal,
              ),
            ),
          ),
        ],
      );

      return Scaffold(
        appBar: current == 0
            ? null
            : AppBar(
                automaticallyImplyLeading: false,
                titleSpacing: 16,
                title: Semantics(
                  header: true,
                  label: 'PeerSync${activeLabel.isEmpty ? '' : ', $activeLabel'}',
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Container(
                          width: 27,
                          height: 27,
                          decoration: BoxDecoration(
                            border: Border.all(color: ink, width: 1.5),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(7),
                              topRight: Radius.circular(7),
                              bottomRight: Radius.circular(7),
                              bottomLeft: Radius.circular(2),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'P',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'PeerSync',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: _unreadNotificationCount > 0
                        ? 'Notifications, $_unreadNotificationCount unread'
                        : 'Notifications, none unread',
                    onPressed: () => go(10),
                    icon: ExcludeSemantics(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.notifications_none,
                            color: ink,
                          ),
                          if (_unreadNotificationCount > 0)
                            Positioned(
                              right: -6,
                              top: -5,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: const BoxDecoration(
                                  color: AppColors.danger,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _unreadNotificationCount > 99
                                      ? '99+'
                                      : '$_unreadNotificationCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: _confirmSignOut,
                    icon: const Icon(Icons.logout, color: ink),
                  ),
                ],
              ),
        body: useSideNavigation
            ? Row(
                children: [
                  _sideNavigation(items, windowSize),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(child: content),
                ],
              )
            : content,
        bottomNavigationBar: current == 0 || current == 10 || useSideNavigation
            ? null
            : _bottomNav(items, activeLabel, go),
      );
    }

    /// Persistent navigation for tablets and desktop browsers.
    Widget _sideNavigation(
      List<(String, IconData, int)> items,
      WindowSize windowSize,
    ) {
      final selectedIndex = items.indexWhere((item) => item.$3 == current);

      return NavigationRail(
        extended: windowSize.isExpanded,
        minExtendedWidth: 208,
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.infoSurface,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        labelType: windowSize.isExpanded
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.all,
        onDestinationSelected: (index) => go(items[index].$3),
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ExcludeSemantics(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                border: Border.all(color: ink, width: 1.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(9),
                  topRight: Radius.circular(9),
                  bottomRight: Radius.circular(9),
                  bottomLeft: Radius.circular(3),
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                'P',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
        ),
        destinations: [
          for (final item in items)
            NavigationRailDestination(
              icon: Icon(item.$2),
              selectedIcon: Icon(item.$2, color: ink),
              label: Text(item.$1),
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
        ],
      );
    }

    Future<void> _confirmSignOut() async {
      final shouldSignOut = await showConfirmDialog(
        context,
        title: 'Sign out of PeerSync?',
        message: 'You will need to enter your email and password to sign in again.',
        confirmLabel: 'Sign out',
        destructive: false,
      );

      if (!shouldSignOut) return;

      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Stop this device receiving the signed-out user's pushes, and remove
      // their cached data from a possibly shared machine.
      await PushNotificationService.unregister(role: role);
      await OfflineCache.clearForUser(uid);
      await FirebaseAuth.instance.signOut();
    }

    Widget _bottomNav(
      List<(String, IconData, int)> items,
      String active,
      ValueChanged<int> go,
    ) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            // Each destination is at least 56px tall so it clears the
            // WCAG 2.2 SC 2.5.8 minimum target size of 48x48.
            height: 64,
            child: Row(
              children: items.map((item) {
                final selected = active == item.$1 ||
                    (active == 'Announcements' && item.$1 == 'Updates');
                final color = selected ? ink : AppColors.textSecondary;

                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: item.$1,
                    child: InkWell(
                      onTap: () => go(item.$3),
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.$2, size: 22, color: color),
                            const SizedBox(height: 3),
                            Text(
                              item.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                            if (selected)
                              Container(
                                width: 14,
                                height: 2,
                                margin: const EdgeInsets.only(top: 2),
                                color: ink,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      );
    }
}

/// Shown when [ApiService] served a response from the three-day offline cache.
class _OfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _OfflineBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        color: AppColors.warningSurface,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Offline - showing saved data from the last 3 days.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.warning,
                minimumSize: const Size(48, 48),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _page(int index, String role, ValueChanged<int> go, ValueChanged<String> setRole, AuthenticatedUser user,ValueChanged<int> onUnreadCountChanged,ValueListenable<int> notificationRefreshSignal,) {
  switch (index) {
    case 1: return ProfessorDashboard(go: go, user: user,);
    case 2: return const ClassManagement();
    case 3: return const ProgressMonitoring();
    case 4: return const AnnouncementsManagement();
    case 5: return ActivitiesPage(user: user);
    case 6: return StudentDashboard(go: go, user: user);
    case 7: return const MyClassesPage();
    case 8: return ActivitiesPage(user: user);
    case 9: return const StudentAnnouncementsPage();
    case 10: return NotificationsPage(onUnreadCountChanged: onUnreadCountChanged, onBack: () => go(role == 'Professor' ? 1 : 6), refreshSignal: notificationRefreshSignal,);
    case 11: return ProfilePage(user: user);
    default: return const SizedBox.shrink();
  }
}