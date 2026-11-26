import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/a11y/app_a11y.dart';
import '../core/utils/error_messages.dart';
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

/*
Future<void> _printAuthenticatedIdToken(String role) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    debugPrint('No authenticated user found.');
    return;
  }

  final idToken = await user.getIdToken(true);

  if (idToken == null || idToken.isEmpty) {
    debugPrint('Firebase ID token is empty.');
    return;
  }

  final parts = idToken.split('.');

  debugPrint('$role Firebase ID Token retrieved.');
  debugPrint('Token length: ${idToken.length}');
  debugPrint('JWT sections: ${parts.length}');
  debugPrint('Token complete: ${parts.length == 3}');

  try {
    await Clipboard.setData(
      ClipboardData(text: idToken),
    );

    debugPrint('$role Firebase ID token copied to clipboard.');
  } on PlatformException catch (e) {
    debugPrint('Clipboard access failed: ${e.message}');
  }
}*/

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordFocusNode = FocusNode();

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
    passwordFocusNode.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    AppA11y.announce(context, message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Please enter your email and password.';
      });
      AppA11y.announce(context, 'Please enter your email and password.');
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
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = credential.user;
      authenticatedUser = firebaseUser;

      if (firebaseUser == null) {
        throw Exception('Unable to retrieve authenticated user.');
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
        throw Exception(
          'Your account is inactive. Contact your administrator.',
        );
      }

      // 4. Verify the actual Firestore role.
      final accountRole = (userData['role'] as String? ?? '')
          .trim()
          .toLowerCase();

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
      final authenticatedRole = accountRole == 'professor'
          ? 'Professor'
          : 'Student';

      //await _printAuthenticatedIdToken(authenticatedRole);

      loginSucceeded = true;
      widget.onLogin(authenticatedRole);
    } on FirebaseAuthException catch (e) {
      if (authenticatedUser != null && !loginSucceeded) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {
          // Preserve the original authentication error for the user.
        }
      }

      if (!mounted) return;

      final message = switch (e.code) {
        'invalid-email' => 'Please enter a valid email address.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' => 'Invalid email or password.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'network-request-failed' =>
          'Network error. Check your internet connection.',
        _ => friendlyErrorMessage(e),
      };

      setState(() {
        errorMessage = message;
      });
      AppA11y.announce(context, message);
    } catch (e) {
      if (authenticatedUser != null && !loginSucceeded) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {
          // Preserve the original profile or validation error.
        }
      }

      if (!mounted) return;

      final message = friendlyErrorMessage(e);
      setState(() {
        errorMessage = message;
      });
      AppA11y.announce(context, message);
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
  Widget build(BuildContext context) {
    final emailLabel = 'Email or ${role.toLowerCase()} ID';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 38, 26, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: const ExcludeSemantics(
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'PeerSync',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Learn together. Progress together.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 48),

              Semantics(
                header: true,
                child: const Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Sign in to continue to your workspace.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),

              const SizedBox(height: 23),

              const FieldLabel('Access as'),

              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Professor', label: Text('Professor')),
                  ButtonSegment(value: 'Student', label: Text('Student')),
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

              // The visible label above the field is excluded from the
              // semantics tree and re-attached to the field itself, so a
              // screen reader announces the label exactly once.
              ExcludeSemantics(child: FieldLabel(emailLabel)),

              Semantics(
                label: emailLabel,
                child: TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  enabled: !isLoading,
                  onSubmitted: (_) => passwordFocusNode.requestFocus(),
                  decoration: const InputDecoration(
                    hintText: 'name@school.edu',
                  ),
                ),
              ),

              const SizedBox(height: 13),

              const ExcludeSemantics(child: FieldLabel('Password')),

              Semantics(
                label: 'Password',
                child: TextField(
                  controller: passwordController,
                  focusNode: passwordFocusNode,
                  obscureText: !showPassword,
                  enabled: !isLoading,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!isLoading) _signIn();
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter password',
                    suffixIcon: IconButton(
                      tooltip: showPassword ? 'Hide password' : 'Show password',
                      onPressed: () {
                        setState(() {
                          showPassword = !showPassword;
                        });
                      },
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  MergeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: remember,
                          onChanged: (v) {
                            setState(() {
                              remember = v ?? false;
                            });
                          },
                        ),
                        const ExcludeSemantics(
                          child: Text(
                            'Remember me',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => _showMessage(
                            'Password reset is not available in this version. '
                            'Please contact your administrator.',
                          ),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  label: 'Error: $errorMessage',
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 18,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              PrimaryButton(
                label: isLoading ? 'Signing in…' : 'Sign in as $role',
                enabled: !isLoading,
                onPressed: _signIn,
              ),

              const SizedBox(height: 13),

              Center(
                child: TextButton(
                  onPressed: isLoading
                      ? null
                      : () => _showMessage(
                          role == 'Student'
                              ? 'Ask your professor for a class join code. '
                                    'Self-service joining is not available yet.'
                              : 'Accounts are created by your institution. '
                                    'Please contact your administrator.',
                        ),
                  child: Text(
                    role == 'Student' ? 'Join a class' : 'Create account',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              const Center(
                child: Text(
                  'PeerSync Academic Workspace · v1.0',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
