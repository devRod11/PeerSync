import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Base URLs for the PeerSync FastAPI backend.
///
/// The host differs per platform:
///  * Android emulator reaches the host machine through `10.0.2.2`.
///  * iOS simulator and desktop builds use `localhost`.
///  * A browser build cannot use `10.0.2.2`, and a deployed PWA must call a
///    real HTTPS host.
///
/// Override the default for any target without editing code:
///
/// ```
/// flutter run -d chrome --dart-define=PEERSYNC_API_BASE_URL=https://api.example.com
/// flutter build web --dart-define=PEERSYNC_API_BASE_URL=https://api.example.com
/// ```
class ApiConfig {
  const ApiConfig._();

  /// Compile-time override supplied with `--dart-define`.
  static const String _override = String.fromEnvironment(
    'PEERSYNC_API_BASE_URL',
  );

  /// Android emulator loopback alias for the host machine.
  static const String _androidEmulatorHost = 'http://10.0.2.2:8000';

  /// Loopback used by the iOS simulator, desktop builds and browsers.
  static const String _localHost = 'http://localhost:8000';

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return _localHost;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidEmulatorHost,
      _ => _localHost,
    };
  }

  static String get authMe => '$baseUrl/auth/me';
  static String get studentCheck => '$baseUrl/auth/student-check';
  static String get professorCheck => '$baseUrl/auth/professor-check';

  static String get projects => '$baseUrl/projects/';
  static String get groups => '$baseUrl/groups/';
  static String get milestones => '$baseUrl/milestones/';
  static String get tasks => '$baseUrl/tasks/';
  static String get submissions => '$baseUrl/submissions/';
  static String get announcements => '$baseUrl/announcements/';
  static String get notifications => '$baseUrl/notifications/';

  /// Device-token registration for push notifications.
  static String get pushDevices => '$baseUrl/notifications/devices';
}
