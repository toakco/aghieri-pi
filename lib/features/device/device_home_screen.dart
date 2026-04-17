import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/task_model.dart';
import '../../services/task_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/circular_display/circular_arc_display.dart';
import '../../widgets/voice_state_ring.dart';
import 'device_intents.dart';
import 'device_shell.dart';

/// Voice-first idle screen for the round physical device.
/// Always-on moon clock + voice ring. Tap anywhere to talk.
class DeviceHomeScreen extends StatefulWidget {
  const DeviceHomeScreen({super.key});

  @override
  State<DeviceHomeScreen> createState() => _DeviceHomeScreenState();
}

class _DeviceHomeScreenState extends State<DeviceHomeScreen> {
  List<TaskModel> _tasks = [];
  TaskModel? _activeTask;
  Timer? _refresh;
  Timer? _idleTimer;
  bool _busy = false;
  bool _dimmed = false;

  static const _idleTimeout = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _resetIdleTimer();
    VoiceService.instance.startWakeWordListening(onWakeWord: _onWakeWord);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _idleTimer?.cancel();
    VoiceService.instance.stopWakeWordListening();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_dimmed && mounted) setState(() => _dimmed = false);
    _idleTimer = Timer(_idleTimeout, () {
      if (mounted) setState(() => _dimmed = true);
    });
  }

  void _onWakeWord() {
    if (!mounted) return;
    _resetIdleTimer();
    _onTap();
  }

  Future<void> _load() async {
    final tasks = await TaskService.instance.getTodayTasks();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _activeTask = tasks.where((t) => t.isActive).cast<TaskModel?>()
          .firstWhere((_) => true, orElse: () => null);
    });
  }

  Future<void> _onTap() async {
    _resetIdleTimer();
    if (_busy) return;
    _busy = true;
    try {
      VoiceService.instance.stopWakeWordListening();
      final transcript = await VoiceService.instance.listen();
      if (!mounted || transcript.trim().isEmpty) return;
      await _handle(transcript);
    } finally {
      _busy = false;
      if (mounted) {
        VoiceService.instance.startWakeWordListening(onWakeWord: _onWakeWord);
      }
    }
  }

  Future<void> _handle(String transcript) async {
    final intent = matchIntent(transcript);
    final next = _nextActionable();

    switch (intent) {
      case DeviceIntent.startFocus:
        if (next != null) {
          await TaskService.instance.startFocus(next.id);
          if (!mounted) return;
          context.go('/device/focus/${next.id}');
          return;
        }
        await VoiceService.instance.speak("Nothing scheduled yet.");
        return;
      case DeviceIntent.whatsNext:
        if (next != null) {
          await VoiceService.instance.speak('Next up: ${next.title}.');
        } else {
          await VoiceService.instance.speak("You're clear.");
        }
        return;
      case DeviceIntent.completeTask:
      case DeviceIntent.nextStep:
        await VoiceService.instance.speak('Open a focus session first.');
        return;
      case DeviceIntent.pause:
      case DeviceIntent.goHome:
        return;
      case null:
        // Fall through to Claude for free-form questions.
        final reply = await VoiceService.instance.sendCommand(transcript);
        if (reply.isNotEmpty) await VoiceService.instance.speak(reply);
        return;
    }
  }

  TaskModel? _nextActionable() {
    final pending = _tasks.where((t) => !t.isComplete).toList();
    if (pending.isEmpty) return null;
    return pending.first;
  }

  @override
  Widget build(BuildContext context) {
    return DeviceShell(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 800),
          opacity: _dimmed ? 0.10 : 1.0,
          child: Stack(
            alignment: Alignment.center,
            children: [
              LayoutBuilder(builder: (context, c) {
                final size = c.maxWidth;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularArcDisplay(
                      tasks: _tasks,
                      activeTask: _activeTask,
                      size: size * 0.92,
                      uiMode: 'abstract',
                      isListening: false,
                    ),
                    IgnorePointer(
                      child: VoiceStateRing(
                        diameter: size * 0.96,
                        strokeWidth: 4.5,
                      ),
                    ),
                  ],
                );
              }),
              Positioned(
                bottom: 28,
                child: Text(
                  _dimmed ? 'tap or say "Aghieri"' : 'say "Aghieri" or tap',
                  style: AghieriTextStyles.caption(
                    size: 11, color: AghieriColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
