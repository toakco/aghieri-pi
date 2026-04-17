import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'services/profile_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/terms_screen.dart';
import 'features/home/home_screen.dart';
import 'features/focus/focus_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/news/news_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/aquarium/aquarium_screen.dart';
import 'features/alarms/alarms_screen.dart';
import 'features/integrations/integrations_screen.dart';
import 'features/integrations/oauth_callback_screen.dart';
import 'features/device/device_home_screen.dart';
import 'features/device/device_focus_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/portfolio/portfolio_screen.dart';
import 'features/settings/settings_screen.dart';
import 'core/theme/app_theme.dart';

// Shared transition: fade + subtle upward rise (natural, not mechanical)
Page<void> _fadePage(BuildContext context, GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
      final fade   = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final slide  = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      final fadeOut = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeIn);
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(fade),
        child: SlideTransition(
          position: slide,
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.85).animate(fadeOut),
            child: child,
          ),
        ),
      );
    },
  );
}

// Full-screen overlay transition: used for focus + aquarium
Page<void> _overlayPage(BuildContext context, GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 600),
    reverseTransitionDuration: const Duration(milliseconds: 400),
    transitionsBuilder: (ctx, animation, _, child) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(curve),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
          child: child,
        ),
      );
    },
  );
}

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final loc = state.matchedLocation;
    final onboarded = await ProfileService.instance.isOnboarded();
    if (!onboarded && loc != '/onboarding') {
      return '/onboarding';
    }
    if (onboarded && loc == '/onboarding') {
      return '/home';
    }
    // ToS guard: onboarded users who haven't accepted ToS
    if (onboarded && loc != '/terms') {
      final tosAccepted = await ProfileService.instance.hasTosAccepted();
      if (!tosAccepted) return '/terms';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', redirect: (_, __) => '/home'),
    GoRoute(
      path: '/onboarding',
      pageBuilder: (c, s) => _fadePage(c, s, const OnboardingScreen()),
    ),
    GoRoute(
      path: '/terms',
      pageBuilder: (c, s) => _fadePage(c, s, const TermsScreen()),
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (c, s) => _fadePage(c, s, const HomeScreen()),
    ),
    GoRoute(
      path: '/focus/:id',
      pageBuilder: (c, s) => _overlayPage(
          c, s, FocusScreen(taskId: s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/tasks',
      pageBuilder: (c, s) => _fadePage(c, s, const TasksScreen()),
    ),
    GoRoute(
      path: '/tasks/new',
      pageBuilder: (c, s) => _fadePage(c, s, const TasksScreen(openNew: true)),
    ),
    GoRoute(
      path: '/news',
      pageBuilder: (c, s) => _fadePage(c, s, const NewsScreen()),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (c, s) => _fadePage(c, s, const ProfileScreen()),
    ),
    GoRoute(
      path: '/aquarium',
      pageBuilder: (c, s) => _overlayPage(c, s, const AquariumScreen()),
    ),
    GoRoute(
      path: '/integrations',
      pageBuilder: (c, s) => _fadePage(c, s, const IntegrationsScreen()),
    ),
    GoRoute(
      path: '/auth/spotify/callback',
      pageBuilder: (c, s) => _fadePage(
        c, s,
        OAuthCallbackScreen(
          provider: 'spotify',
          code:  s.uri.queryParameters['code'],
          state: s.uri.queryParameters['state'],
          error: s.uri.queryParameters['error'],
        ),
      ),
    ),
    GoRoute(
      path: '/auth/notion/callback',
      pageBuilder: (c, s) => _fadePage(
        c, s,
        OAuthCallbackScreen(
          provider: 'notion',
          code:  s.uri.queryParameters['code'],
          state: s.uri.queryParameters['state'],
          error: s.uri.queryParameters['error'],
        ),
      ),
    ),
    GoRoute(
      path: '/alarms',
      pageBuilder: (c, s) => _fadePage(c, s, const AlarmsScreen()),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (c, s) => _fadePage(c, s, const SettingsScreen()),
    ),
    GoRoute(
      path: '/portfolio',
      pageBuilder: (c, s) => _fadePage(c, s, const PortfolioScreen()),
    ),
    GoRoute(
      path: '/sign-in',
      pageBuilder: (c, s) => _fadePage(c, s, const SignInScreen()),
    ),
    GoRoute(
      path: '/device',
      pageBuilder: (c, s) => _fadePage(c, s, const DeviceHomeScreen()),
    ),
    GoRoute(
      path: '/device/focus/:id',
      pageBuilder: (c, s) => _overlayPage(
          c, s, DeviceFocusScreen(taskId: s.pathParameters['id']!)),
    ),
  ],
);

class AghieriApp extends StatelessWidget {
  const AghieriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Aghieri',
      theme: AghieriTheme.dark,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
