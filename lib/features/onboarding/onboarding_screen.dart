import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../services/alarm_service.dart';
import '../../services/profile_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/bionic_text.dart';

/// Onboarding flow — 9 pages, all centered.
/// Pages: Welcome → Name → Pronouns → Interests → ADHD → Wake/Sleep → Integrations → Voice → Done
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  int _page = 0;
  late final AnimationController _auroraCtrl;

  // Collected values
  String _name             = '';
  String _preferredName    = '';
  String _pronouns         = '';
  List<String> _interests  = [];
  String _adhdComfort      = 'prefer not to say';
  String _wakeTime         = '07:00';
  String _sleepTime        = '23:00';
  String _uiMode           = 'abstract';
  String _typographyMode   = 'adaptive';
  bool _connectCalendar    = false;
  bool _connectNotion      = false;

  static const _totalPages = 8; // Terms → Welcome → Name → Pronouns → Interests → ADHD → Wake/Sleep → Done
  bool _tosAccepted = false;

  @override
  void initState() {
    super.initState();
    _auroraCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
  }

  @override
  void dispose() {
    _auroraCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _totalPages - 1) {
      _controller.nextPage(duration: 500.ms, curve: Curves.easeInOutCubic);
      setState(() => _page++);
    } else {
      _complete();
    }
  }

  void _back() {
    if (_page > 0) {
      _controller.previousPage(duration: 400.ms, curve: Curves.easeInOutCubic);
      setState(() => _page--);
    }
  }

  Future<void> _complete() async {
    // Persist typography mode globally before navigating
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('typography_mode', _typographyMode);
    AghieriTextStyles.setMode(_typographyMode);

    final profile = UserProfile(
      name: _name,
      preferredName: _preferredName.isNotEmpty ? _preferredName : _name,
      pronouns: _pronouns.isNotEmpty ? _pronouns : null,
      interests: _interests,
      adhdComfort: _adhdComfort,
      wakeTime: _wakeTime,
      sleepTime: _sleepTime,
      voiceEnabled: true,
      onboardingComplete: true,
      uiMode: _uiMode,
      typographyMode: _typographyMode,
    );

    await ProfileService.instance.saveProfile(profile);
    await ProfileService.instance.markOnboarded();

    // Set wake alarm from onboarding times
    await AlarmService.instance.syncWakeAlarm(
      _wakeTime,
      profile.preferredName,
    );

    if (_connectCalendar || _connectNotion) {
      _setupIntegrations();
    }

    if (mounted) context.go('/home');
  }

  Future<void> _setupIntegrations() async {
    try {
      if (_connectCalendar) {
        await http.get(
          Uri.parse('http://192.168.1.100:8000/integrations/calendar/auth-url'),
        ).timeout(const Duration(seconds: 8));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Aurora animated background ────────────────────────────────────
          AnimatedBuilder(
            animation: _auroraCtrl,
            builder: (_, __) => RepaintBoundary(
              child: CustomPaint(
                painter: _AuroraPainter(_auroraCtrl.value),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // ── Page content ──────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Progress bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    children: List.generate(_totalPages, (i) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 2,
                        decoration: BoxDecoration(
                          color: i <= _page
                              ? AghieriColors.accent
                              : AghieriColors.surface.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    )),
                  ),
                ),

                // Pages
                Expanded(
                  child: PageView(
                    controller: _controller,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _TermsPage(
                        onAccept: () async {
                          _tosAccepted = true;
                          await ProfileService.instance.acceptTos();
                          _next();
                        },
                      ),
                      _WelcomePage(onNext: () {
                        // Auto-set typography to adaptive (ADHD-optimized)
                        _typographyMode = 'adaptive';
                        _next();
                      }),
                      _NamePage(
                        onNext: (name, preferred) {
                          _name = name;
                          _preferredName = preferred;
                          _next();
                        },
                      ),
                      _PronounsPage(onNext: (p) { _pronouns = p; _next(); }),
                      _InterestsPage(onNext: (list) { _interests = list; _next(); }),
                      _AdhdPage(onNext: (c) { _adhdComfort = c; _next(); }),
                      _WakeSleeePage(
                        onNext: (wake, sleep) {
                          _wakeTime = wake;
                          _sleepTime = sleep;
                          _next();
                        },
                      ),
                      _DonePage(
                        name: _preferredName.isNotEmpty ? _preferredName : _name,
                        onFinish: _complete,
                      ),
                    ],
                  ),
                ),

                // Back button
                if (_page > 0 && _page < _totalPages - 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextButton(
                      onPressed: _back,
                      child: Text('Back', style: AghieriTextStyles.caption()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page Wrapper ──────────────────────────────────────────────────────────────
class _OnboardingPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final String buttonLabel;
  final VoidCallback? onNext;
  final bool canProceed;
  final Widget? trailingAction; // e.g., mic button

  const _OnboardingPage({
    required this.title,
    this.subtitle,
    required this.content,
    this.buttonLabel = 'Continue',
    this.onNext,
    this.canProceed = true,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (trailingAction != null)
            Align(
              alignment: Alignment.centerRight,
              child: trailingAction!,
            ),
          Text(
            title,
            style: AghieriTextStyles.heading(size: 28),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Text(
              subtitle!,
              style: AghieriTextStyles.body(color: AghieriColors.textSecondary),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 100.ms),
          ],
          const SizedBox(height: 32),
          Expanded(child: content.animate().fadeIn(delay: 150.ms)),
          const SizedBox(height: 24),
          if (onNext != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canProceed ? onNext : null,
                child: Text(buttonLabel),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Voice mic button ──────────────────────────────────────────────────────────
class _MicButton extends StatefulWidget {
  final Future<void> Function() onListen;
  const _MicButton({required this.onListen});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (_active) return;
        setState(() => _active = true);
        try {
          await widget.onListen();
        } finally {
          if (mounted) setState(() => _active = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active
              ? AghieriColors.accent.withOpacity(0.2)
              : AghieriColors.surfaceHigh,
          border: Border.all(
            color: _active ? AghieriColors.accent : AghieriColors.surfaceHigh,
            width: 1.5,
          ),
        ),
        child: Icon(
          _active ? Icons.mic : Icons.mic_none_rounded,
          color: _active ? AghieriColors.accent : AghieriColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }
}

// ── Time parsing helpers ──────────────────────────────────────────────────────
TimeOfDay? _parseSpokenTime(String text) {
  final t = text.toLowerCase().trim();
  // Match "7am", "7 am", "7:30am", "7:30 am", "2pm", "14:00" etc.
  final re = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?');
  final m = re.firstMatch(t);
  if (m == null) return null;
  int hour = int.tryParse(m.group(1) ?? '') ?? -1;
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  final meridiem = m.group(3);
  if (hour < 0) return null;
  if (meridiem == 'pm' && hour < 12) hour += 12;
  if (meridiem == 'am' && hour == 12) hour = 0;
  return TimeOfDay(hour: hour.clamp(0, 23), minute: min.clamp(0, 59));
}

String _todToString(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// ── Individual Pages ──────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Aghieri',
            style: AghieriTextStyles.logo(size: 52, color: AghieriColors.accent),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2),
          const SizedBox(height: 16),
          Text(
            'Your productivity companion.',
            style: AghieriTextStyles.body(
              size: 17,
              color: AghieriColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 48),
          Text(
            'A guide through complexity.\nNot a judge of it.',
            style: AghieriTextStyles.heading(size: 22, weight: FontWeight.w300),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 600.ms),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: Text(
                'Get started',
                style: AghieriTextStyles.heading(
                  size: 22,
                  weight: FontWeight.w300,
                  color: AghieriColors.bg,
                ),
              ),
            ).animate().fadeIn(delay: 1000.ms),
          ),
        ],
      ),
    );
  }
}


class _NamePage extends StatefulWidget {
  final void Function(String name, String preferred) onNext;
  const _NamePage({required this.onNext});

  @override
  State<_NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<_NamePage> {
  final _nameCtrl = TextEditingController();
  final _prefCtrl = TextEditingController();

  Future<void> _listenForName() async {
    final result = await VoiceService.instance.listen();
    if (result.isNotEmpty && mounted) {
      // First word = name, rest may be preferred
      final parts = result.trim().split(' ');
      setState(() {
        _nameCtrl.text = parts.first;
        if (parts.length > 1) _prefCtrl.text = parts.sublist(1).join(' ');
      });
      if (_nameCtrl.text.isNotEmpty) {
        widget.onNext(_nameCtrl.text.trim(), _prefCtrl.text.trim());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: "What's your name?",
      subtitle: "Aghieri will use this when talking with you.",
      canProceed: _nameCtrl.text.isNotEmpty,
      onNext: () => widget.onNext(_nameCtrl.text.trim(), _prefCtrl.text.trim()),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: AghieriTextStyles.body(size: 18),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(hintText: 'Your name'),
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _prefCtrl,
            style: AghieriTextStyles.body(size: 18),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
                hintText: 'What should Aghieri call you? (optional)'),
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }
}


class _PronounsPage extends StatefulWidget {
  final void Function(String) onNext;
  const _PronounsPage({required this.onNext});

  @override
  State<_PronounsPage> createState() => _PronounsPageState();
}

class _PronounsPageState extends State<_PronounsPage> {
  String _selected = '';
  final _ctrl = TextEditingController();
  final _options = ['He/Him', 'She/Her', 'They/Them', 'Any'];

  Future<void> _listenForPronouns() async {
    final result = await VoiceService.instance.listen();
    if (result.isNotEmpty && mounted) {
      final lower = result.toLowerCase();
      String? match;
      if (lower.contains('he') || lower.contains('him')) match = 'He/Him';
      else if (lower.contains('she') || lower.contains('her')) match = 'She/Her';
      else if (lower.contains('they') || lower.contains('them')) match = 'They/Them';
      else if (lower.contains('any')) match = 'Any';

      if (match != null) {
        setState(() { _selected = match!; _ctrl.clear(); });
        widget.onNext(_selected);
      } else {
        setState(() { _ctrl.text = result; _selected = ''; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Your pronouns',
      subtitle: 'Optional — skip if you prefer.',
      onNext: () => widget.onNext(_ctrl.text.isNotEmpty ? _ctrl.text : _selected),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: _options.map((o) => _Chip(
              label: o,
              selected: _selected == o,
              onTap: () => setState(() { _selected = o; _ctrl.clear(); }),
            )).toList(),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ctrl,
            style: AghieriTextStyles.body(),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(hintText: 'Or type your own (optional)'),
            onChanged: (_) => setState(() => _selected = ''),
          ),
        ],
      ),
    );
  }
}


class _InterestsPage extends StatefulWidget {
  final void Function(List<String>) onNext;
  const _InterestsPage({required this.onNext});

  @override
  State<_InterestsPage> createState() => _InterestsPageState();
}

class _InterestsPageState extends State<_InterestsPage> {
  final _selected = <String>{};

  Future<void> _listenForInterests() async {
    final result = await VoiceService.instance.listen();
    if (result.isNotEmpty && mounted) {
      final lower = result.toLowerCase();
      for (final opt in kInterestOptions) {
        if (lower.contains(opt.toLowerCase())) {
          _selected.add(opt);
        }
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Your interests',
      subtitle: "Aghieri uses these to personalize your experience.",
      canProceed: true,
      onNext: () => widget.onNext(_selected.toList()),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: kInterestOptions.map((o) => _Chip(
            label: o,
            selected: _selected.contains(o),
            onTap: () => setState(() {
              _selected.contains(o) ? _selected.remove(o) : _selected.add(o);
            }),
          )).toList(),
        ),
      ),
    );
  }
}


class _AdhdPage extends StatelessWidget {
  final void Function(String) onNext;
  const _AdhdPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'How do you describe yourself?',
      subtitle: 'This shapes how Aghieri communicates. Totally optional.',
      canProceed: true,
      onNext: () => onNext('prefer not to say'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SelectOption('I have ADHD or suspect I do', () => onNext('adhd')),
          _SelectOption('I struggle with focus sometimes',
              () => onNext('focus_challenges')),
          _SelectOption(
            "I'm neurotypical — just want to stay organized",
            () => onNext('neurotypical'),
          ),
          _SelectOption('Prefer not to say', () => onNext('prefer not to say')),
        ],
      ),
    );
  }
}


class _WakeSleeePage extends StatefulWidget {
  final void Function(String wake, String sleep) onNext;
  const _WakeSleeePage({required this.onNext});

  @override
  State<_WakeSleeePage> createState() => _WakeSleeePageState();
}

class _WakeSleeePageState extends State<_WakeSleeePage> {
  TimeOfDay _wake  = const TimeOfDay(hour: 7,  minute: 0);
  TimeOfDay _sleep = const TimeOfDay(hour: 23, minute: 0);

  Future<void> _pickWake() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _wake,
      helpText: 'Wake up time',
      builder: (ctx, child) => _timePickerTheme(ctx, child),
    );
    if (picked != null) setState(() => _wake = picked);
  }

  Future<void> _pickSleep() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _sleep,
      helpText: 'Sleep time',
      builder: (ctx, child) => _timePickerTheme(ctx, child),
    );
    if (picked != null) setState(() => _sleep = picked);
  }

  Widget _timePickerTheme(BuildContext ctx, Widget? child) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AghieriColors.accent,
          surface: AghieriColors.surface,
          onSurface: AghieriColors.textPrimary,
        ),
        timePickerTheme: const TimePickerThemeData(
          backgroundColor: AghieriColors.surfaceHigh,
        ),
      ),
      child: child!,
    );
  }

  Future<void> _listenForTimes() async {
    final result = await VoiceService.instance.listen();
    if (result.isEmpty || !mounted) return;

    // Try to find two times in the speech
    final lower = result.toLowerCase();
    final times = <TimeOfDay>[];
    final re = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?');
    for (final m in re.allMatches(lower)) {
      int h = int.tryParse(m.group(1) ?? '') ?? -1;
      final min = int.tryParse(m.group(2) ?? '0') ?? 0;
      final mer = m.group(3);
      if (h < 0) continue;
      if (mer == 'pm' && h < 12) h += 12;
      if (mer == 'am' && h == 12) h = 0;
      times.add(TimeOfDay(hour: h.clamp(0, 23), minute: min.clamp(0, 59)));
    }

    if (times.isNotEmpty) {
      setState(() {
        _wake = times.first;
        if (times.length > 1) _sleep = times[1];
      });
    }
  }

  String _formatTod(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$min $p';
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Your daily rhythm',
      subtitle: 'Aghieri builds your day around these times.',
      onNext: () => widget.onNext(_todToString(_wake), _todToString(_sleep)),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          Text(
            'Wake up',
            style: AghieriTextStyles.label(
                size: 12, color: AghieriColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickWake,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: AghieriColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AghieriColors.accent.withOpacity(0.4)),
              ),
              child: Text(
                _formatTod(_wake),
                style: AghieriTextStyles.heading(
                    size: 32, weight: FontWeight.w600,
                    color: AghieriColors.accent),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Go to sleep',
            style: AghieriTextStyles.label(
                size: 12, color: AghieriColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickSleep,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              decoration: BoxDecoration(
                color: AghieriColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AghieriColors.accentDim.withOpacity(0.5)),
              ),
              child: Text(
                _formatTod(_sleep),
                style: AghieriTextStyles.heading(
                    size: 32, weight: FontWeight.w600,
                    color: AghieriColors.textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to change — or tap the mic to speak\ne.g. "7am and 11pm"',
            style: AghieriTextStyles.caption(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}


class _IntegrationsPage extends StatefulWidget {
  final void Function(bool calendar, bool notion) onNext;
  const _IntegrationsPage({required this.onNext});

  @override
  State<_IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<_IntegrationsPage> {
  bool _cal = false, _notion = false;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Connect your tools',
      subtitle: 'Optional. Connect anytime in settings.',
      onNext: () => widget.onNext(_cal, _notion),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ToggleTile(
            icon: Icons.calendar_today_outlined,
            title: 'Google Calendar',
            subtitle: 'Pull your schedule and sync tasks',
            value: _cal,
            onChanged: (v) => setState(() => _cal = v),
          ),
          const SizedBox(height: 12),
          _ToggleTile(
            icon: Icons.article_outlined,
            title: 'Notion',
            subtitle: 'Import tasks from your workspace',
            value: _notion,
            onChanged: (v) => setState(() => _notion = v),
          ),
        ],
      ),
    );
  }
}


class _VoiceSetupPage extends StatefulWidget {
  final VoidCallback onNext;
  final String userName;
  const _VoiceSetupPage({required this.onNext, required this.userName});

  @override
  State<_VoiceSetupPage> createState() => _VoiceSetupPageState();
}

class _VoiceSetupPageState extends State<_VoiceSetupPage> {
  bool _tested = false;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: "Meet Aghieri's voice",
      subtitle: 'Powered by ElevenLabs — natural and warm.',
      onNext: widget.onNext,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() => _tested = true);
                VoiceService.instance.speak(
                  'Hello${widget.userName.isNotEmpty ? ", ${widget.userName}" : ""}. '
                  'I am Aghieri, your productivity companion.',
                );
              },
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AghieriColors.surface,
                  border: Border.all(color: AghieriColors.accent, width: 1.5),
                ),
                child: const Icon(
                  Icons.volume_up_outlined,
                  color: AghieriColors.accent,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '"Hello${widget.userName.isNotEmpty ? ", ${widget.userName}" : ""}. '
            "I'm Aghieri, your productivity companion."
            '"',
            style: AghieriTextStyles.body(color: AghieriColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (_tested) ...[
            const SizedBox(height: 16),
            Text(
              'Voice ready.',
              style: AghieriTextStyles.caption(color: AghieriColors.accent),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}


class _TermsPage extends StatefulWidget {
  final Future<void> Function() onAccept;
  const _TermsPage({required this.onAccept});

  @override
  State<_TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<_TermsPage> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Terms & Privacy',
      subtitle: 'Please review before continuing.',
      canProceed: _accepted,
      onNext: widget.onAccept,
      buttonLabel: 'I agree — continue',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AghieriColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aghieri Terms of Service',
                        style: AghieriTextStyles.body(size: 16, weight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Text(
                      'By using Aghieri, you agree to the following:\n\n'
                      '1. Privacy First\n'
                      'Aghieri processes your data locally on your device whenever possible. '
                      'Voice commands are processed through secure APIs (Anthropic Claude, ElevenLabs) '
                      'and are not stored or used for training.\n\n'
                      '2. Data You Control\n'
                      'Your tasks, preferences, and behavioral patterns stay on your device '
                      'and your Firebase account. You can delete everything from Settings at any time.\n\n'
                      '3. No Tracking, No Ads\n'
                      'Aghieri does not serve advertisements, sell data, or track you across apps.\n\n'
                      '4. ADHD-Aware Design\n'
                      'Aghieri is designed as a productivity companion, not a medical device. '
                      'It does not diagnose, treat, or replace professional ADHD support.\n\n'
                      '5. Prototype Notice\n'
                      'This is a capstone prototype developed at NC State University. '
                      'Features may change. Use at your own discretion.\n\n'
                      '6. Calendar & Integration Access\n'
                      'When you connect Google Calendar or Notion, Aghieri accesses only what you authorize. '
                      'Calendar access is read-only. Nothing is shared externally.',
                      style: AghieriTextStyles.body(
                        size: 13,
                        color: AghieriColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _accepted = !_accepted),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: _accepted
                        ? AghieriColors.accent
                        : AghieriColors.surface,
                    border: Border.all(
                      color: _accepted
                          ? AghieriColors.accent
                          : AghieriColors.textSecondary,
                      width: 1.5,
                    ),
                  ),
                  child: _accepted
                      ? const Icon(Icons.check, size: 16, color: AghieriColors.bg)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'I have read and agree to the Terms of Service and Privacy Policy',
                    style: AghieriTextStyles.body(size: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _DonePage extends StatelessWidget {
  final String name;
  final VoidCallback onFinish;
  const _DonePage({required this.name, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "You're in${name.isNotEmpty ? ', $name' : ''}.",
            style: AghieriTextStyles.heading(size: 32),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.1),
          const SizedBox(height: 16),
          Text(
            "Aghieri is ready.\nNo pressure. No streaks. Just focus.",
            style: AghieriTextStyles.body(
                size: 18, color: AghieriColors.textSecondary),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onFinish,
              child: const Text('Open Aghieri'),
            ).animate().fadeIn(delay: 800.ms),
          ),
        ],
      ),
    );
  }
}

// ── Shared Components ──────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 250.ms,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AghieriColors.accent.withOpacity(0.15)
              : AghieriColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AghieriColors.accent : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AghieriTextStyles.body(
            size: 14,
            color: selected ? AghieriColors.accent : AghieriColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SelectOption extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SelectOption(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AghieriColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AghieriTextStyles.body(size: 15),
                  textAlign: TextAlign.center,
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: AghieriColors.textSecondary, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AghieriColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? AghieriColors.accent.withOpacity(0.5) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: value ? AghieriColors.accent : AghieriColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AghieriTextStyles.body(size: 15)),
                Text(subtitle, style: AghieriTextStyles.caption()),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AghieriColors.accent,
            inactiveTrackColor: AghieriColors.surfaceHigh,
          ),
        ],
      ),
    );
  }
}

// ── UI Mode Page ──────────────────────────────────────────────────────────────
class _UiModePage extends StatefulWidget {
  final void Function(String mode) onNext;
  const _UiModePage({required this.onNext});

  @override
  State<_UiModePage> createState() => _UiModePageState();
}

class _UiModePageState extends State<_UiModePage> {
  String _selected = 'day_clock';

  static const _modes = [
    (
      id: 'day_clock',
      title: 'Day Clock',
      desc: 'Ring shows your position in the day. '
          'Wake on the left, sleep on the right — current time moves clockwise through the top.',
      icon: Icons.radio_button_checked_outlined,
    ),
    (
      id: 'task_progress',
      title: 'Task Progress',
      desc: 'Ring fills as you complete what you planned. '
          'Each task gets a colored segment — glow grows as you check steps off.',
      icon: Icons.donut_large_outlined,
    ),
    (
      id: 'abstract',
      title: 'Abstract',
      desc: 'A white circle that slowly shrinks through the day. '
          'Full at wake, nearly gone at sleep — a quiet, ambient reminder of time.',
      icon: Icons.circle_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Your display style',
      subtitle: 'How should the circle show your day?',
      onNext: () => widget.onNext(_selected),
      content: Column(
        children: _modes.map((m) {
          final sel = _selected == m.id;
          return GestureDetector(
            onTap: () => setState(() => _selected = m.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sel
                    ? AghieriColors.accent.withOpacity(0.10)
                    : AghieriColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? AghieriColors.accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(m.icon,
                      color: sel ? AghieriColors.accent : AghieriColors.textSecondary,
                      size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title,
                            style: AghieriTextStyles.body(
                                size: 15,
                                weight: FontWeight.w600,
                                color: sel
                                    ? AghieriColors.accent
                                    : AghieriColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(m.desc,
                            style: AghieriTextStyles.caption(),
                            maxLines: 3),
                      ],
                    ),
                  ),
                  if (sel)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle_rounded,
                          color: AghieriColors.accent, size: 20),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Typography Page ───────────────────────────────────────────────────────────
class _TypographyPage extends StatefulWidget {
  final void Function(String mode) onNext;
  const _TypographyPage({required this.onNext});

  @override
  State<_TypographyPage> createState() => _TypographyPageState();
}

class _TypographyPageState extends State<_TypographyPage> {
  String _selected = 'default';

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Your typography',
      subtitle: 'Choose how text looks throughout the app.',
      onNext: () => widget.onNext(_selected),
      content: Column(
        children: [
          _TypographyCard(
            id: 'default',
            selected: _selected == 'default',
            onTap: () => setState(() => _selected = 'default'),
            label: 'Default',
            description: 'Clean and modern.',
            sampleHeading: 'Stay focused.',
            sampleBody: 'Tasks, alarms, and voice — all in one place.',
            headingStyle: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AghieriColors.textPrimary,
              decoration: TextDecoration.none,
            ),
            bodyStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AghieriColors.textSecondary,
              decoration: TextDecoration.none,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          _TypographyCard(
            id: 'classic',
            selected: _selected == 'classic',
            onTap: () => setState(() => _selected = 'classic'),
            label: 'Classic',
            description: 'Familiar and highly legible.',
            sampleHeading: 'Stay focused.',
            sampleBody: 'Tasks, alarms, and voice — all in one place.',
            headingStyle: const TextStyle(
              fontFamily: 'Verdana',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AghieriColors.textPrimary,
              decoration: TextDecoration.none,
            ),
            bodyStyle: const TextStyle(
              fontFamily: 'Verdana',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AghieriColors.textSecondary,
              decoration: TextDecoration.none,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 10),
          _TypographyCard(
            id: 'adaptive',
            selected: _selected == 'adaptive',
            onTap: () => setState(() => _selected = 'adaptive'),
            label: 'Adaptive',
            description: 'Bionic reading headers · OpenDyslexic body.\nDesigned for ADHD and dyslexia.',
            sampleHeading: 'Stay focused.',
            sampleBody: 'Tasks, alarms, and voice — all in one place.',
            headingStyle: const TextStyle(
              fontFamily: 'OpenDyslexic',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AghieriColors.textPrimary,
              decoration: TextDecoration.none,
            ),
            bodyStyle: const TextStyle(
              fontFamily: 'OpenDyslexic',
              fontSize: 12,
              color: AghieriColors.textSecondary,
              decoration: TextDecoration.none,
              height: 1.75,
            ),
            bionicHeading: true,
          ),
        ],
      ),
    );
  }
}

class _TypographyCard extends StatelessWidget {
  final String id;
  final bool selected;
  final VoidCallback onTap;
  final String label;
  final String description;
  final String sampleHeading;
  final String sampleBody;
  final TextStyle headingStyle;
  final TextStyle bodyStyle;
  final bool bionicHeading;

  const _TypographyCard({
    required this.id,
    required this.selected,
    required this.onTap,
    required this.label,
    required this.description,
    required this.sampleHeading,
    required this.sampleBody,
    required this.headingStyle,
    required this.bodyStyle,
    this.bionicHeading = false,
  });

  // No longer needed — BionicText widget handles splitting

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AghieriColors.accent.withOpacity(0.10)
              : AghieriColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AghieriColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: AghieriTextStyles.body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: selected
                            ? AghieriColors.accent
                            : AghieriColors.textSecondary)),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      color: AghieriColors.accent, size: 16),
              ],
            ),
            const SizedBox(height: 10),
            // Sample heading
            bionicHeading
                ? BionicText(
                    sampleHeading,
                    style: headingStyle,
                    fixation: 3,
                  )
                : Text(sampleHeading, style: headingStyle),
            const SizedBox(height: 5),
            Text(sampleBody, style: bodyStyle),
            const SizedBox(height: 8),
            Text(description,
                style: AghieriTextStyles.caption(
                    color: AghieriColors.textSecondary.withOpacity(0.7)),
                maxLines: 2),
          ],
        ),
      ),
    );
  }
}

// ── Aurora Background ─────────────────────────────────────────────────────────
/// Animated mesh-gradient background — ADHD color palette blobs drifting slowly.
class _AuroraPainter extends CustomPainter {
  final double t; // 0..1 from AnimationController.repeat()

  const _AuroraPainter(this.t);

  // [baseX, baseY, ampX, ampY, phaseX, phaseY, radius, color, opacity]
  // Positions are fractions of canvas width/height.
  // Drift uses independent sine waves on each axis for organic Lissajous motion.
  static const List<_AuroraBlob> _blobs = [
    // Sky blue — upper left, wide drift
    _AuroraBlob(0.12, 0.10, 0.12, 0.10, 0.00, 1.30, 260, Color(0xFFA0D8EF), 0.32),
    // Mint — left center, drifts down
    _AuroraBlob(0.08, 0.48, 0.09, 0.14, 2.10, 0.55, 210, Color(0xFFA4FFCA), 0.26),
    // Soft yellow — center, slow wide float
    _AuroraBlob(0.48, 0.28, 0.14, 0.12, 1.05, 2.40, 290, Color(0xFFFFE888), 0.22),
    // Muted purple — upper right
    _AuroraBlob(0.88, 0.16, 0.09, 0.16, 3.50, 1.70, 200, Color(0xFFCD79DD), 0.28),
    // Sage green — lower center
    _AuroraBlob(0.42, 0.78, 0.16, 0.09, 0.80, 3.10, 250, Color(0xFF96C8A2), 0.24),
    // Blue — lower right
    _AuroraBlob(0.82, 0.72, 0.11, 0.11, 2.75, 0.35, 215, Color(0xFF4A90E2), 0.26),
    // Extra sky blue — bottom left for coverage
    _AuroraBlob(0.18, 0.80, 0.10, 0.08, 4.20, 2.80, 195, Color(0xFFA0D8EF), 0.20),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in _blobs) {
      // Independent x/y drift using slightly different frequencies
      final dx = b.ampX * sin(t * 2 * pi * 0.9 + b.phaseX);
      final dy = b.ampY * sin(t * 2 * pi * 0.7 + b.phaseY);
      final cx = (b.baseX + dx) * size.width;
      final cy = (b.baseY + dy) * size.height;

      // Subtle breathe on opacity
      final breathe = 0.88 + 0.12 * sin(t * 2 * pi * 1.3 + b.phaseX * 0.5);

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            b.color.withOpacity(b.opacity * breathe),
            b.color.withOpacity(0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: b.radius),
        );

      canvas.drawCircle(Offset(cx, cy), b.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

class _AuroraBlob {
  final double baseX, baseY, ampX, ampY, phaseX, phaseY;
  final double radius;
  final Color color;
  final double opacity;

  const _AuroraBlob(
    this.baseX, this.baseY,
    this.ampX, this.ampY,
    this.phaseX, this.phaseY,
    this.radius, this.color, this.opacity,
  );
}
