import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'models/authenticated_user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'pages/login_page.dart';
import 'pages/professor_dashboard_page.dart';
import 'pages/class_management_page.dart';
import 'pages/progress_monitoring_page.dart';
import 'pages/announcements_management_page.dart';
import 'pages/activities_page.dart';
import 'pages/student_dashboard_page.dart';
import 'pages/my_classes_page.dart';
import 'pages/student_announcements_page.dart';
import 'pages/notifications_page.dart';
import 'pages/profile_page.dart';
import 'services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const PeerSyncApp());
}

class PeerSyncApp extends StatelessWidget {
  const PeerSyncApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PeerSync',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
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
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (initializationSnapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Unable to initialize your login session.'),
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
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (authSnapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Unable to check your login session.'),
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
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (profileSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Unable to retrieve your account profile.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _retryProfileCheck,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final authenticatedUser = profileSnapshot.data;

            // Invalid or rejected profile: sign-out will trigger authStateChanges().
            if (authenticatedUser == null) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
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

class _PeerSyncShellState extends State<PeerSyncShell> {
  late int current;
  late String role;
  int _unreadNotificationCount = 0;

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

  @override
  void initState() {
    super.initState();

    role = widget.role;
    current = role == 'Student' ? 6 : 1;

    _refreshUnreadNotificationCount();
  }

  void go(int index) {
    setState(() {
      current = index.clamp(0, 11).toInt();
    });

    if (index == 10) {
      _refreshUnreadNotificationCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = current == 6 || current == 7 || current == 8 || current == 9 ||
        (current == 11 && role == 'Student');
    final screenRole = current == 0 || current == 10 || current == 11
        ? (current == 11 ? role : 'Shared')
        : (isStudent ? 'Student' : 'Professor');
    final activeLabel = current == 11 ? 'Profile' : current == 10 ? '' :
      (isStudent ? (current == 7 ? 'My Classes' : current == 8 ? 'Activities' :
      current == 9 ? 'Announcements' : 'Dashboard') :
      (current == 2 ? 'Classes' : current == 3 ? 'Progress' :
      current == 4 ? 'Announcements' : current == 5 ? 'Classes' : 'Dashboard'));

    return Scaffold(
      appBar: current == 0 ? null : AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(children: [
          Container(
            width: 27, height: 27,
            decoration: BoxDecoration(border: Border.all(color: ink, width: 1.5), borderRadius: const BorderRadius.only(topLeft: Radius.circular(7), topRight: Radius.circular(7), bottomRight: Radius.circular(7), bottomLeft: Radius.circular(2))),
            alignment: Alignment.center,
            child: const Text('P', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          const Text('PeerSync', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => go(10),
            icon: Stack(
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
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _unreadNotificationCount > 99
                            ? '99+'
                            : '$_unreadNotificationCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(tooltip: 'Logout', onPressed: () async { await FirebaseAuth.instance.signOut(); },
            icon: const Icon( Icons.logout, color: ink, ),
          ),   
        ],
      ),
      body: SafeArea(
        child: _page(
          current,
          role,
          go,
          (r) => setState(() => role = r),
          widget.user,
          _setUnreadNotificationCount,
        ),
      ),
      bottomNavigationBar: current == 0 ? null : (current == 10 ? null : _bottomNav(screenRole, activeLabel, go)),
    );
  }

  Widget _bottomNav(String role, String active, ValueChanged<int> go) {
    final student = role == 'Student';
    final items = student
      ? const [('Dashboard', Icons.home_outlined, 6), ('My Classes', Icons.menu_book_outlined, 7), ('Activities', Icons.description_outlined, 8), ('Updates', Icons.campaign_outlined, 9), ('Profile', Icons.person_outline, 11)]
      : const [('Dashboard', Icons.home_outlined, 1), ('Classes', Icons.menu_book_outlined, 2), ('Progress', Icons.bar_chart, 3), ('Updates', Icons.campaign_outlined, 4), ('Profile', Icons.person_outline, 11)];
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF2F5FF), border: Border(top: BorderSide(color: line))),
      child: SafeArea(top: false, child: SizedBox(height: 59, child: Row(
        children: items.map((item) {
          final selected = active == item.$1 || (active == 'Announcements' && item.$1 == 'Updates');
          return Expanded(child: InkWell(
            onTap: () => go(item.$3),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(item.$2, size: 19, color: selected ? ink : const Color(0xFF8291A8)),
              const SizedBox(height: 3),
              Text(item.$1, style: TextStyle(fontSize: 9, color: selected ? ink : muted, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
              if (selected) Container(width: 14, height: 2, margin: const EdgeInsets.only(top: 2), color: ink),
            ]),
          ));
        }).toList(),
      ))),
    );
  }
}

Widget _page(int index, String role, ValueChanged<int> go, ValueChanged<String> setRole, AuthenticatedUser user,ValueChanged<int> onUnreadCountChanged,) {
  switch (index) {
    case 1: return ProfessorDashboard(go: go, user: user,);
    case 2: return ClassManagement();
    case 3: return ProgressMonitoring();
    case 4: return AnnouncementsManagement();
    case 5: return ActivitiesPage(user: user);
    case 6: return StudentDashboard(go: go, user: user);
    case 7: return MyClassesPage();
    case 8: return ActivitiesPage(user: user);
    case 9: return StudentAnnouncementsPage();
    case 10: return NotificationsPage(onUnreadCountChanged: onUnreadCountChanged, onBack: () => go(role == 'Professor' ? 1 : 6),);
    case 11: return ProfilePage(user: user);
    default: return const SizedBox.shrink();
  }
}