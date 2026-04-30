import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/alarm_service.dart';
import 'services/auth_service.dart';
import 'services/interaction_tracker.dart';
import 'services/music_service.dart';
import 'services/notification_service.dart';
import 'services/voice_service.dart';
import 'services/weather_service.dart';

bool get _isLinuxDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!_isLinuxDesktop) {
    usePathUrlStrategy();
  }

  if (!_isLinuxDesktop) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.deviceCheck,
      webProvider: ReCaptchaV3Provider('6LeIxAcTAAAAAJcZVRqyHh71UMIEGNQ_MXjiZKhI'),
    );
  }

  if (!_isLinuxDesktop) {
    await AuthService.instance.init();
  }

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Edge-to-edge immersive
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0F),
  ));

  // Load typography mode before first frame
  final prefs = await SharedPreferences.getInstance();
  AghieriTextStyles.setMode(prefs.getString('typography_mode') ?? 'default');

  if (!_isLinuxDesktop) {
    await VoiceService.instance.init();
    await AlarmService.instance.init();
    await NotificationService.instance.init();
    await MusicService.instance.init();
    await WeatherService.instance.init();
    InteractionTracker.instance.track(InteractionType.appOpened);
  }

  runApp(const AghieriApp());
}
