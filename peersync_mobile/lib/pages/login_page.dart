import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_test.dart';

import '../theme/app_colors.dart';
import '../widgets/shared_widgets.dart';

class LoginPage extends StatefulWidget {
  final ValueChanged<String> onLogin;
  final VoidCallback? onLoginAttemptStarted;
  final ValueChanged<bool>? onLoginAttemptFinished;

  const LoginPage({
    super.key,
    required this.onLogin,
    this.onLoginAttemptStarted,
    this.onLoginAttemptFinished,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String role = 'Professor';
  bool remember = true;
  bool showPassword = false;
  bool isLoading = false;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String? errorMessage;
  late final Future<void> _rememberPreferenceFuture;

  @override
  void initState() {
    super.initState();
    _rememberPreferenceFuture = _loadRememberPreference();
  }

  Future<void> _loadRememberPreference() async {
    final preferences = await SharedPreferences.getInstance();
    final savedValue = preferences.getBool('peersync_remember_me');

    if (mounted && savedValue != null) {
      setState(() {
        remember = savedValue;
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Please enter your email and password.';
      });
      return;
    }

    widget.onLoginAttemptStarted?.call();

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    var loginSucceeded = false;
    User? authenticatedUser;

    try {
      // Save this device's Remember Me preference before authenticating.
      await _rememberPreferenceFuture;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('peersync_remember_me', remember);

      // 1. Authenticate through Firebase Authentication.
      final credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = credential.user;
      authenticatedUser = firebaseUser;

      if (firebaseUser == null) {
        throw Exception('Unable to retrieve authenticated user.');
      }

      // TEMPORARY: Retrieve Firebase ID token for Swagger testing.
      debugPrint('TOKEN TEST: Reached token retrieval.');

      try {
        final idToken = await firebaseUser.getIdToken(true);

        if (idToken == null) {
          debugPrint('TOKEN ERROR: Firebase returned a null token.');
        } else {
          debugPrint('TOKEN TEST: Token retrieved successfully.');
          debugPrint('TOKEN LENGTH: ${idToken.length}');
          debugPrint('========== FIREBASE ID TOKEN START ==========');

          for (var i = 0; i < idToken.length; i += 500) {
            final end = (i + 500 < idToken.length)
                ? i + 500
                : idToken.length;

            debugPrint(idToken.substring(i, end));
          }

          debugPrint('========== FIREBASE ID TOKEN END ==========');
        }
      } catch (e) {
        debugPrint('TOKEN RETRIEVAL ERROR: $e');
      }

      // 2. Retrieve the corresponding Firestore user document.
      final userDocument = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();

      if (!userDocument.exists) {
        await FirebaseAuth.instance.signOut();
        throw Exception('User profile not found in PeerSync.');
      }

      final userData = userDocument.data()!;

      // 3. Check whether the account is active.
      if (userData['isActive'] != true) {
        await FirebaseAuth.instance.signOut();
        throw Exception('Your account is inactive. Contact your administrator.');
      }

      // 4. Verify the actual Firestore role.
      final accountRole =
          (userData['role'] as String? ?? '').trim().toLowerCase();

      final selectedRole = role.toLowerCase();

      if (accountRole != selectedRole) {
        await FirebaseAuth.instance.signOut();

        throw Exception(
          'The credentials provided could not be verified. '
          'Please check your login information and try again.',
        );
      }

      if (!mounted) return;

      // Professor OTP is intentionally postponed during this development stage.
      // Both valid roles can proceed after Firebase and Firestore validation.
      final authenticatedRole =
          accountRole == 'professor' ? 'Professor' : 'Student';

      loginSucceeded = true;
      widget.onLogin(authenticatedRole);
      await ApiTest.testConnection();

    } on FirebaseAuthException catch (e) {
      if (authenticatedUser != null && !loginSucceeded) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {
          // Preserve the original authentication error for the user.
        }
      }

      if (!mounted) return;

      setState(() {
        switch (e.code) {
          case 'invalid-email':
            errorMessage = 'Please enter a valid email address.';
            break;
          case 'user-not-found':
          case 'wrong-password':
          case 'invalid-credential':
            errorMessage = 'Invalid email or password.';
            break;
          case 'user-disabled':
            errorMessage = 'This account has been disabled.';
            break;
          case 'too-many-requests':
            errorMessage = 'Too many attempts. Please try again later.';
            break;
          case 'network-request-failed':
            errorMessage = 'Network error. Check your internet connection.';
            break;
          default:
            errorMessage = 'Authentication failed: ${e.message}';
        }
      });
    } catch (e) {
      if (authenticatedUser != null && !loginSucceeded) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {
          // Preserve the original profile or validation error.
        }
      }

      if (!mounted) return;

      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        widget.onLoginAttemptFinished?.call(loginSucceeded);
      }
    }
  }

  

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(26, 38, 26, 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),

          Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: const Text(
                'P',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'PeerSync',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text(
              'Learn together. Progress together.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ]),

          const SizedBox(height: 55),

          const Text(
            'Welcome back',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          const Text(
            'Sign in to continue to your workspace.',
            style: TextStyle(color: muted, fontSize: 12),
          ),

          const SizedBox(height: 23),

          const FieldLabel('Access as'),

          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'Professor',
                label: Text('Professor'),
              ),
              ButtonSegment(
                value: 'Student',
                label: Text('Student'),
              ),
            ],
            selected: {role},
            onSelectionChanged: (v) {
              setState(() {
                role = v.first;
                errorMessage = null;
              });
            },
            showSelectedIcon: false,
          ),

          const SizedBox(height: 16),

          FieldLabel('Email or ${role.toLowerCase()} ID'),

          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'name@school.edu',
            ),
          ),

          const SizedBox(height: 13),

          const FieldLabel('Password'),

          TextField(
            controller: passwordController,
            obscureText: !showPassword,
            onSubmitted: (_) => isLoading ? null : _signIn(),
            decoration: InputDecoration(
              hintText: 'Enter password',
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    showPassword = !showPassword;
                  });
                },
                icon: Icon(
                  showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Row(children: [
            Checkbox(
              value: remember,
              onChanged: (v) {
                setState(() {
                  remember = v ?? false;
                });
              },
              visualDensity: VisualDensity.compact,
            ),
            const Text(
              'Remember me',
              style: TextStyle(fontSize: 11),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {},
              child: const Text(
                'Forgot password?',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ]),

          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          PrimaryButton(
            label: isLoading ? 'Signing in...' : 'Sign in as $role',
            onPressed: isLoading ? () {} : _signIn,
          ),

          const SizedBox(height: 13),

          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                role == 'Student' ? 'Join a class' : 'Create account',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),

          const SizedBox(height: 48),

          const Center(
            child: Text(
              'PeerSync Academic Workspace · v1.0',
              style: TextStyle(color: muted, fontSize: 9),
            ),
          ),
        ],
      ),
    ),
  );
}
