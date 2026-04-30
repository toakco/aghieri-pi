import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FCM-backed notification service.
/// Handles permission, token registration, and incoming message routing.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled by the OS notification tray.
  // No app code needed — FCM displays the notification automatically.
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const _tokenKey = 'fcm_token';

  String? _token;
  String? get token => _token;

  Future<void> init() async {
    // Web doesn't support FCM token in the same way on mobile
    if (kIsWeb) return;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    // Request permission (iOS prompts user; Android 13+ also prompts)
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Get and cache FCM token
    _token = await messaging.getToken();
    if (_token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
    }

    // Token refresh
    messaging.onTokenRefresh.listen((newToken) async {
      _token = newToken;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, newToken);
    });

    // Foreground message handling
    FirebaseMessaging.onMessage.listen(_handleForeground);

    // App opened from a notification tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  }

  void _handleForeground(RemoteMessage message) {
    // Foreground: show an in-app banner (alarm, stats, task reminder).
    // Routing happens via the notification data payload.
    debugPrint('[FCM] Foreground: ${message.notification?.title}');
  }

  void _handleTap(RemoteMessage message) {
    // User tapped the notification — route based on data.type
    final type = message.data['type'] as String?;
    final id = message.data['id'] as String?;
    debugPrint('[FCM] Tapped: type=$type id=$id');
    // Routing is picked up by app.dart nav guard on next frame via stored prefs.
    _storePendingRoute(type, id);
  }

  void _storePendingRoute(String? type, String? id) async {
    if (type == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_notification', jsonEncode({'type': type, 'id': id}));
  }

  /// Retrieve and clear any pending notification route set from a tap.
  Future<Map<String, dynamic>?> consumePendingRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pending_notification');
    if (raw == null) return null;
    await prefs.remove('pending_notification');
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
