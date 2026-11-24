import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../config/api_config.dart';
import '../../firebase_options.dart';
import '../../services/api_service.dart';

/// A push message normalised for the UI layer.
class PushMessage {
  final String title;
  final String body;

  /// In-app destination the message should open: `dashboard`, `activities`,
  /// `announcements` or `notifications`.
  final String destination;
  final Map<String, dynamic> data;

  const PushMessage({
    required this.title,
    required this.body,
    required this.destination,
    this.data = const {},
  });
}

/// Handles messages that arrive while the app is terminated or backgrounded.
///
/// Must be a top-level function so the Flutter engine can call it in a separate
/// isolate. On Android and iOS a message that contains a `notification` block
/// is displayed by the system automatically; this handler exists so that a
/// data-only message still wakes the app and so Firebase is initialised in the
/// background isolate.
@pragma('vm:entry-point')
Future<void> peersyncBackgroundMessageHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

/// Registers the device (or browser) with Firebase Cloud Messaging and forwards
/// incoming messages to the UI.
///
/// Works on Android, iOS and web. On web the browser needs a VAPID key pair
/// from the Firebase console (Cloud Messaging → Web Push certificates); pass it
/// at build time:
///
/// ```
/// flutter build web --dart-define=PEERSYNC_WEB_VAPID_KEY=<key>
/// ```
///
/// Registration uses `register()` and `onRegistered` rather than the
/// `getToken()` / `onTokenRefresh` pair, which firebase_messaging 17 deprecates.
/// The identifier that arrives is the FCM registration token, or the Firebase
/// Installation ID when the project has opted into FID mode; either way it is
/// the value the backend needs in order to target this device.
class PushNotificationService {
  const PushNotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final List<StreamSubscription<dynamic>> _subscriptions = [];

  static const String _vapidKey = String.fromEnvironment(
    'PEERSYNC_WEB_VAPID_KEY',
  );

  /// How long to wait for the identifier after calling `register()`.
  static const Duration _registrationTimeout = Duration(seconds: 20);

  static void Function(PushMessage message)? _messageHandler;

  static bool _initialised = false;
  static String? _token;

  /// The current registration identifier, once registration has succeeded.
  static String? get token => _token;

  /// True when the user has granted notification permission.
  static bool get isEnabled => _initialised;

  /// Registers the callback that receives foreground messages and notification
  /// taps. A plain callback rather than a stream, so the shell does not have to
  /// own a [StreamSubscription] it must remember to cancel.
  static void setMessageHandler(void Function(PushMessage message)? handler) {
    _messageHandler = handler;
  }

  /// Requests permission, registers the device with the backend and starts
  /// listening for messages.
  ///
  /// [role] is used to subscribe to the matching topic so a Professor never
  /// receives a student-only announcement push.
  static Future<void> initialize({required String role}) async {
    if (_initialised) return;

    try {
      await _requestPermission();
      await _subscribeToTopics(role);

      // A previous session may have left listeners attached (sign-out resets
      // `_initialised` but not the native streams), and attaching twice would
      // show every banner twice.
      await _detachListeners();

      // Attach the listeners before registering: `onRegistered` is a broadcast
      // stream fed by a native callback, so it does not replay an event that
      // fired before anyone was listening.
      _subscriptions.add(
        _messaging.onRegistered.listen(_handleRegistered),
      );

      _subscriptions.add(
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage),
      );

      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen(_handleForegroundMessage),
      );

      await _register();

      // A notification tapped while the app was terminated.
      final initialMessage = await _messaging.getInitialMessage();

      if (initialMessage != null) {
        _handleForegroundMessage(initialMessage);
      }

      _initialised = true;
    } catch (error, stackTrace) {
      // Push is an enhancement: a browser without a VAPID key, a denied
      // permission or an offline device must never block sign-in.
      debugPrint('PeerSync push setup skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> _requestPermission() async {
    // The defaults already request alert, badge and sound and skip provisional
    // authorisation, so passing them explicitly would only be noise.
    final settings = await _messaging.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      throw StateError('Notification permission was denied.');
    }
  }

  static Future<void> _subscribeToTopics(String role) async {
    if (kIsWeb) {
      debugPrint(
        'PeerSync: FCM topic subscriptions are skipped on web.',
      );
      return;
    }
    final isProfessor = role.trim().toLowerCase() == 'professor';

    await _messaging.subscribeToTopic('all_users');
    await _messaging.subscribeToTopic(
      isProfessor ? 'role_professors' : 'role_students',
    );
  }

  /// Starts registration and waits for the identifier to arrive.
  ///
  /// A timeout is not treated as a failure: the identifier may already be
  /// stored server-side from a previous launch, and a later `onRegistered`
  /// event still updates it.
  static Future<void> _register() async {
    final registered = _messaging.onRegistered
        .first
        .timeout(_registrationTimeout, onTimeout: () => '');

    await _messaging.register(
      vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
    );

    await registered;
  }

  /// Called on the first registration and on every later refresh.
  static void _handleRegistered(String identifier) {
    if (identifier.isEmpty) return;

    _token = identifier;
    unawaited(_sendTokenToBackend(identifier));
  }

  /// Persists the identifier server-side so the FastAPI backend can target this
  /// device when an announcement or task is published.
  static Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiService.post(
        ApiConfig.pushDevices,
        body: {
          'token': token,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        },
      );
    } catch (_) {
      // A failed registration is retried on the next launch or refresh.
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final push = _toPushMessage(message);

    if (push != null) {
      _messageHandler?.call(push);
    }
  }

  static PushMessage? _toPushMessage(RemoteMessage message) {
    final notification = message.notification;
    final data = Map<String, dynamic>.from(message.data);

    final title = notification?.title ?? data['title']?.toString();
    final body = notification?.body ??
        data['body']?.toString() ??
        data['description']?.toString();

    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return null;
    }

    return PushMessage(
      title: (title == null || title.isEmpty) ? 'PeerSync' : title,
      body: body ?? '',
      destination: _destinationFor(data),
      data: data,
    );
  }

  /// Maps a backend `type` to the screen that should open.
  static String _destinationFor(Map<String, dynamic> data) {
    final explicit = data['destination']?.toString();

    if (explicit != null && explicit.isNotEmpty) return explicit;

    return switch (data['type']?.toString()) {
      'announcement_created' || 'announcement_updated' => 'announcements',
      'task_assigned' || 'submission_reviewed' => 'activities',
      _ => 'notifications',
    };
  }
static Future<void> unregister({String? role}) async {
  try {
    final currentToken = _token;

    if (currentToken != null && currentToken.isNotEmpty) {
      await ApiService.delete('${ApiConfig.pushDevices}/$currentToken');
    }

    // FCM topic subscriptions are not supported on web.
    if (!kIsWeb) {
      final isProfessor = role?.trim().toLowerCase() == 'professor';

      await _messaging.unsubscribeFromTopic('all_users');
      await _messaging.unsubscribeFromTopic(
        isProfessor ? 'role_professors' : 'role_students',
      );
    }

    await _detachListeners();
    await _messaging.unregister();
  } catch (error) {
    debugPrint('PeerSync push unregister warning: $error');
  } finally {
    _token = null;
    _initialised = false;
    _messageHandler = null;
  }
}

  /// Cancels the native stream listeners so a new session can attach its own.
  static Future<void> _detachListeners() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    _subscriptions.clear();
  }

  /// Releases the native listeners. Mainly used by tests.
  static Future<void> dispose() async {
    await _detachListeners();
    _messageHandler = null;
  }
}
