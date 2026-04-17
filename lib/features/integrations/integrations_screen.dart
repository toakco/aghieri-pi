import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/oauth_service.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  bool _calendarConnected = false;
  bool _notionConnected   = false;
  bool _spotifyConnected  = false;
  bool _loading = true;
  bool _calendarLoading = false;
  bool _spotifyLoading = false;
  bool _notionLoading = false;
  String? _spotifyDisplay;
  String? _notionDisplay;
  List<_CalendarEvent> _upcomingEvents = [];

  static const _calendarPrefKey = 'aghieri_calendar_connected';
  static const _notionPrefKey   = 'aghieri_notion_connected';
  static const _spotifyPrefKey  = 'aghieri_spotify_connected';

  final _googleSignIn = GoogleSignIn(
    scopes: [gcal.CalendarApi.calendarReadonlyScope],
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _calendarConnected = prefs.getBool(_calendarPrefKey) ?? false;

    // Real Spotify/Notion connection state lives in Firestore now.
    final spotify = await OAuthService.instance.readIntegration('spotify');
    final notion  = await OAuthService.instance.readIntegration('notion');
    _spotifyConnected = spotify != null;
    _notionConnected  = notion  != null;
    _spotifyDisplay = spotify?['profile']?['display_name'] as String?
        ?? spotify?['profile']?['id'] as String?;
    _notionDisplay  = notion?['workspace_name'] as String?;
    await prefs.setBool(_spotifyPrefKey, _spotifyConnected);
    await prefs.setBool(_notionPrefKey, _notionConnected);

    // Try silent Google sign-in so real events render if prior auth exists
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        _calendarConnected = true;
        await prefs.setBool(_calendarPrefKey, true);
        _fetchCalendarEvents();
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connectSpotify() async {
    setState(() => _spotifyLoading = true);
    final url = await OAuthService.instance.startAuth('spotify');
    if (url == null) {
      if (mounted) {
        setState(() => _spotifyLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Couldn't start Spotify auth. Try again.",
              style: AghieriTextStyles.body(size: 14)),
          backgroundColor: AghieriColors.surface,
        ));
      }
      return;
    }
    await OAuthService.instance.openAuthUrl(url);
  }

  Future<void> _disconnectSpotify() async {
    await OAuthService.instance.disconnect('spotify');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_spotifyPrefKey, false);
    if (mounted) {
      setState(() {
        _spotifyConnected = false;
        _spotifyDisplay = null;
      });
    }
  }

  Future<void> _connectNotionReal() async {
    setState(() => _notionLoading = true);
    final url = await OAuthService.instance.startAuth('notion');
    if (url == null) {
      if (mounted) {
        setState(() => _notionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Couldn't start Notion auth. Try again.",
              style: AghieriTextStyles.body(size: 14)),
          backgroundColor: AghieriColors.surface,
        ));
      }
      return;
    }
    await OAuthService.instance.openAuthUrl(url);
  }

  Future<void> _disconnectNotion() async {
    await OAuthService.instance.disconnect('notion');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notionPrefKey, false);
    if (mounted) {
      setState(() {
        _notionConnected = false;
        _notionDisplay = null;
      });
    }
  }

  Future<void> _connectCalendar() async {
    setState(() => _calendarLoading = true);
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_calendarPrefKey, true);
        if (mounted) setState(() => _calendarConnected = true);
        await _fetchCalendarEvents();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calendar connection failed. Try again.',
                style: AghieriTextStyles.body(size: 14)),
            backgroundColor: AghieriColors.surface,
          ),
        );
      }
    }
    if (mounted) setState(() => _calendarLoading = false);
  }

  Future<void> _disconnectCalendar() async {
    await _googleSignIn.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_calendarPrefKey, false);
    if (mounted) {
      setState(() {
        _calendarConnected = false;
        _upcomingEvents = [];
      });
    }
  }

  Future<void> _fetchCalendarEvents() async {
    try {
      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) return;

      final calendarApi = gcal.CalendarApi(httpClient);
      final now = DateTime.now();
      final endOfWeek = now.add(const Duration(days: 7));

      final events = await calendarApi.events.list(
        'primary',
        timeMin: now.toUtc(),
        timeMax: endOfWeek.toUtc(),
        maxResults: 10,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (mounted) {
        setState(() {
          _upcomingEvents = (events.items ?? []).map((e) {
            final start = e.start?.dateTime ?? e.start?.date;
            return _CalendarEvent(
              title: e.summary ?? 'Untitled',
              time: start != null ? _formatEventTime(start) : '',
              date: start != null ? _formatEventDate(start) : '',
            );
          }).toList();
        });
      }

      httpClient.close();
    } catch (e) {
      debugPrint('[Integrations] Calendar fetch error: $e');
    }
  }

  String _formatEventTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String _formatEventDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      appBar: AppBar(
        backgroundColor: AghieriColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AghieriColors.textSecondary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Connections', style: AghieriTextStyles.heading(size: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AghieriColors.accent))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('INTEGRATIONS', style: AghieriTextStyles.label(size: 12))
                    .animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 12),

                // Google Calendar
                _IntegrationTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Google Calendar',
                  subtitle: _calendarConnected
                      ? 'Connected — showing upcoming events'
                      : 'See your schedule alongside tasks',
                  connected: _calendarConnected,
                  loading: _calendarLoading,
                  onConnect: _connectCalendar,
                  onDisconnect: _disconnectCalendar,
                ).animate().fadeIn(delay: 100.ms, duration: 300.ms),

                // Upcoming events
                if (_calendarConnected && _upcomingEvents.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AghieriColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('THIS WEEK', style: AghieriTextStyles.label(size: 10)),
                        const SizedBox(height: 10),
                        ..._upcomingEvents.map((event) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 3, height: 32,
                                decoration: BoxDecoration(
                                  color: AghieriColors.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(event.title,
                                        style: AghieriTextStyles.body(size: 14, weight: FontWeight.w500)),
                                    Text('${event.date} ${event.time}',
                                        style: AghieriTextStyles.caption(size: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                ],

                if (_calendarConnected && _upcomingEvents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AghieriColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('No events this week.',
                          style: AghieriTextStyles.caption()),
                    ),
                  ),

                const SizedBox(height: 16),

                // Notion
                _IntegrationTile(
                  icon: Icons.article_outlined,
                  label: 'Notion',
                  subtitle: _notionConnected
                      ? (_notionDisplay != null
                          ? 'Connected — workspace: $_notionDisplay'
                          : 'Connected — tasks sync with your workspace')
                      : 'Pull tasks from a Notion workspace',
                  connected: _notionConnected,
                  loading: _notionLoading,
                  onConnect: _connectNotionReal,
                  onDisconnect: _disconnectNotion,
                ).animate().fadeIn(delay: 200.ms, duration: 300.ms),

                const SizedBox(height: 16),

                // Spotify
                _IntegrationTile(
                  icon: Icons.headphones_outlined,
                  label: 'Spotify',
                  subtitle: _spotifyConnected
                      ? (_spotifyDisplay != null
                          ? 'Connected as $_spotifyDisplay'
                          : 'Connected — ambient focus ready')
                      : 'Ambient focus music during sessions',
                  connected: _spotifyConnected,
                  loading: _spotifyLoading,
                  onConnect: _connectSpotify,
                  onDisconnect: _disconnectSpotify,
                ).animate().fadeIn(delay: 300.ms, duration: 300.ms),

                const SizedBox(height: 32),

                // Privacy note
                Text('PRIVACY', style: AghieriTextStyles.label(size: 12))
                    .animate().fadeIn(delay: 300.ms, duration: 300.ms),
                const SizedBox(height: 8),
                Text(
                  'Aghieri only reads what you authorize. '
                  'Calendar access is read-only — used to suggest reschedule times '
                  'and show events alongside your tasks. '
                  'Notion access pulls tasks you\'ve already written. '
                  'Nothing is shared externally. No data leaves your device.',
                  style: AghieriTextStyles.caption(),
                ).animate().fadeIn(delay: 350.ms, duration: 300.ms),
              ],
            ),
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool connected;
  final bool loading;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _IntegrationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.connected,
    this.loading = false,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AghieriColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected
              ? AghieriColors.accent.withOpacity(0.3)
              : AghieriColors.surfaceHigh,
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              color: connected ? AghieriColors.accent : AghieriColors.textSecondary,
              size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AghieriTextStyles.body(
                        size: 14, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: AghieriTextStyles.caption()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loading)
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: AghieriColors.accent),
            )
          else
            TextButton(
              onPressed: connected ? onDisconnect : onConnect,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: Text(
                connected ? 'Disconnect' : 'Connect',
                style: AghieriTextStyles.caption(
                    color: connected
                        ? AghieriColors.textSecondary
                        : AghieriColors.accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarEvent {
  final String title;
  final String time;
  final String date;
  const _CalendarEvent({required this.title, required this.time, required this.date});
}
