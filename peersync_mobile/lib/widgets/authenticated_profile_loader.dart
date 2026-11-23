import 'package:flutter/material.dart';
import '../models/authenticated_user.dart';
import '../services/api_service.dart';

class AuthenticatedProfileLoader extends StatefulWidget {
  final Widget Function(AuthenticatedUser user) builder;

  const AuthenticatedProfileLoader({
    super.key,
    required this.builder,
  });

  @override
  State<AuthenticatedProfileLoader> createState() =>
      _AuthenticatedProfileLoaderState();
}

class _AuthenticatedProfileLoaderState
    extends State<AuthenticatedProfileLoader> {
  late Future<AuthenticatedUser> _profileFuture;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    _profileFuture = ApiService.getAuthenticatedUser();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthenticatedUser>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to load your account information.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(_loadProfile);
                      },
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: Text('No authenticated user information found.'),
            ),
          );
        }

        return widget.builder(snapshot.data!);
      },
    );
  }
}