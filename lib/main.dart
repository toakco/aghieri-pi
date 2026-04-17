import 'package:firebase_core/firebase_core.dart';
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
import 'services/voice_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use clean path URLs (no #) so OAuth redirect URIs work as registered.
  usePathUrlStrategy();

  // Initialize Firebase + anonymous auth
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AuthService.instance.init();

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

  // Load saved API keys + device IP
  await VoiceService.instance.init();

  // Start alarm service (checks every 30s)
  await AlarmService.instance.init();

  // Music service
  await MusicService.instance.init();

  InteractionTracker.instance.track(InteractionType.appOpened);

  runApp(const AghieriApp());
}
