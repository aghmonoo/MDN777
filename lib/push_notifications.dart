
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

/// Handles background/terminated messages. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // The system tray notification is drawn by FCM itself; nothing to do here.
}

/// Push notifications for announcements, chat messages and payslips.
///
/// Device tokens live in `users/{uid}.fcmTokens`. They are added when a user
/// signs in and removed when they sign out, so a shared device never keeps
/// delivering to the previous account.
class PushNotifications {
  /// Firebase Console -> Project settings -> Cloud Messaging ->
  /// Web configuration -> Web Push certificates -> Key pair.
  static const String vapidKey =
      'BBpqg_36hZiZqjDljsCgYvABPsX-qj9RBHAleGU6p44p0p5m4zvVohkKHQ-K3nxMMEdEgh-0tz-CTehB_k0A4uk';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'staff_connect_high',
    'Staff Connect',
    description: 'Announcements, messages and payslips',
    importance: Importance.high,
  );

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool _wired = false;
  static String? _currentToken;

  static bool get _supported => kIsWeb || Platform.isAndroid || Platform.isIOS;

  /// Registered once in main(), before runApp.
  static void registerBackgroundHandler() {
    if (kIsWeb) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  /// Called once after sign-in.
  ///
  /// Each step is guarded on its own: a browser that never answers the
  /// permission prompt must not stop the token from being registered.
  static Future<void> start() async {
    if (!_supported) return;
    debugPrint('[push] start()');

    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 20));
      debugPrint('[push] permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[push] permission step skipped: $e');
    }

    try {
      await _setUpLocalNotifications();
    } catch (e) {
      debugPrint('[push] local notifications unavailable: $e');
    }

    try {
      await _wireListeners();
    } catch (e) {
      debugPrint('[push] listeners not wired: $e');
    }

    try {
      await _saveToken().timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('[push] token step failed: $e');
    }
  }

  /// Called just before sign-out.
  static Future<void> stop() async {
    if (!_supported) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _currentToken;
    _currentToken = null;
    if (uid == null || token == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (_) {
      // Nothing useful to do if the profile is already gone.
    }
  }

  /// Asks the backend to fan out a notification for something just written.
  ///
  /// Fire-and-forget: a failure here must never block the user's action.
  static Future<void> notify(Map<String, dynamic> payload) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('notify')
          .call<Map<String, dynamic>>(payload);
    } catch (e) {
      debugPrint('Notification not sent: $e');
    }
  }

  static Future<void> _setUpLocalNotifications() async {
    if (kIsWeb) return;

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  static Future<void> _wireListeners() async {
    if (_wired) return;
    _wired = true;

    FirebaseMessaging.onMessage.listen(_showForeground);

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      _currentToken = token;
      await _writeToken(token);
    });
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    if (kIsWeb) return;
    final notification = message.notification;
    if (notification == null) return;

    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> _saveToken() async {
    String? token;
    if (kIsWeb) {
      token = await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
    } else {
      token = await FirebaseMessaging.instance.getToken();
    }
    debugPrint('[push] token: ${token == null ? "NULL" : "${token.substring(0, 12)}..."}');
    if (token == null) return;
    _currentToken = token;
    await _writeToken(token);
  }

  static Future<void> _writeToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
      debugPrint('[push] token stored on users/$uid');
    } catch (e) {
      debugPrint('[push] could not store token: $e');
    }
  }
}
