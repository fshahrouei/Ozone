// lib/main.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'flutter_gen/gen_l10n/app_localizations.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_routes.dart';
import 'core/widgets/internet_floating_button.dart';
import 'core/utils/guest_user_manager.dart';

// === Firebase + Notifications ===
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

// === Push tap wiring ===
import 'core/services/push_navigation_service.dart'; // wire FCM/local taps to this service

// === TTS (only service bootstrap; no settings/provider here) ===
import 'core/tts/tts_service.dart';

/// Background handler must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // You can log or process data here if needed
  // debugPrint('BG message: ${message.messageId}  data=${message.data}');
}

/// Local notifications helper (foreground display + click callback)
class LocalNotif {
  static final _plugin = FlutterLocalNotificationsPlugin();

  // Must match AndroidManifest meta-data channel id
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications.',
    importance: Importance.max,
  );

  static Future<void> init() async {
    // Click handlers for local notifications (foreground or background)
    const androidInit = AndroidInitializationSettings(
      // If you created a monochrome status icon named ic_stat_push
      '@drawable/ic_stat_push',
    );
    const iosInit = DarwinInitializationSettings();

    // v17+: use onDidReceiveNotificationResponse to handle taps
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Forward the payload into PushNavigationService so MainNavigation can show the dialog
        final payload = response.payload;
        PushNavigationService.I.setFromLocalTapPayload(payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }
  }

  /// Background click callback (Android). Must be a top-level function.
  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse response) {
    final payload = response.payload;
    // We cannot do UI here; just stash the payload so UI shows it after app comes to foreground.
    PushNavigationService.I.setFromLocalTapPayload(payload);
  }

  static Future<void> show(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;

    // Pass data map as JSON payload so we can reconstruct it on tap
    final payload = m.data.isEmpty ? null : jsonEncode(m.data);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        channelDescription: 'Used for important notifications.',
        priority: Priority.high,
        importance: Importance.max,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      n.hashCode,
      n.title,
      n.body,
      details,
      payload: payload,
    );
  }
}

/// Determine initial route for the app (your existing code)
Future<String> _getInitialRoute() async {
  if (FORCE_SHOW_ONBOARDING) return AppRoutes.onboarding;
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getBool('onboarding_seen') ?? false;
  if (!seen) return AppRoutes.onboarding;
  if (FORCE_SHOW_LOGIN) return AppRoutes.login;
  return AppRoutes.main;
}

/// Initialize Firebase + FCM + foreground notifications + push tap wiring
Future<void> _initFirebaseAndPush() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register background handler once (before runApp is okay)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Local notifications for foreground (and tap callback wiring)
  await LocalNotif.init();

  // Request notification permission (Android 13+ shows system dialog itself)
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(
    alert: true, badge: true, sound: true, announcement: false,
    carPlay: false, criticalAlert: false, provisional: false,
  );

  // Get FCM token (send to your Laravel later)
  final token = await fcm.getToken();
  debugPrint('FCM TOKEN: $token');

  // Foreground messages → show with local notifications
  FirebaseMessaging.onMessage.listen((m) async {
    await LocalNotif.show(m);
  });

  // App opened via notification tap (from background)
  FirebaseMessaging.onMessageOpenedApp.listen((m) {
    // Normalize and forward to PushNavigationService
    final n = m.notification;
    PushNavigationService.I.setPending(
      title: n?.title,
      body: n?.body,
      data: m.data,
      source: PushSource.fcmTap,
    );
  });

  // App launched from terminated state via notification
  final initialMsg = await fcm.getInitialMessage();
  if (initialMsg != null) {
    final n = initialMsg.notification;
    PushNavigationService.I.setPending(
      title: n?.title,
      body: n?.body,
      data: initialMsg.data,
      source: PushSource.initialMessage,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init Firebase + Messaging + push tap wiring
  await _initFirebaseAndPush();

  // Initialize guest user id (your existing logic)
  final guestId = await GuestUserManager.getOrCreateUserId();
  debugPrint("Guest User ID: $guestId");

  // === TTS bootstrap (only service init; no auto-speak here) ===
  await TtsService.instance.init(language: 'en-US');

  // Decide initial route
  final initialRoute = await _getInitialRoute();

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Climate Wise',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: IS_DARK_THEME ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(APP_LOCALE),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: initialRoute,
      routes: AppRoutes.routes,
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => const Scaffold(
          body: Center(child: Text('Page not found')),
        ),
      ),
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            const InternetFloatingButton(),
          ],
        );
      },
    );
  }
}
