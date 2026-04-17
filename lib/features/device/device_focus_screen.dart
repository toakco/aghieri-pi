import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/task_model.dart';
import '../../services/task_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/voice_state_ring.dart';
import 'device_intents.dart';
import 'device_shell.dart';

/// Voice-first focus screen for the round physical device.
/// Big task title, current step text, voice ring around the whole circle.
class DeviceFocusScreen extends StatefulWidget {
  final String taskId;
  const DeviceFocusScreen({super.key, required this.taskId});

  @override
  State<DeviceFocusScreen> createState() => _DeviceFocusScreenState();
}

class _DeviceFocusScreenState extends State<DeviceFocusScreen> {
  TaskModel? _task;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await TaskService.instance.getTask(widget.taskId);
    if (!mounted) return;
    setState(() => _task = t);
    if (t != null && !t.isActive) {
      await TaskService.instance.startFocus(t.id);
    }
  }

  Future<void> _onTap() async {
    if (_busy) return;
    _busy = true;
    try {
      final transcript = await VoiceService.instance.listen();
      if (!mounted || transcript.trim().isEmpty) return;
      await _handle(transcript);
    } finally {
      _busy = false;
    }
  }

  Future<void> _handle(String transcript) async {
    final intent = matchIntent(transcript);
    final t = _task;

    switch (intent) {
      case DeviceIntent.nextStep:
        if (t != null) {
          await TaskService.instance.completeStep(t.id);
          await _load();
          await VoiceService.instance.speak('Marked. Onto the next.');
        }
        return;
      case DeviceIntent.completeTask:
        if (t != null) {
          await TaskService.instance.completeTask(t.id);
          await VoiceService.instance.speak('Task complete.');
          if (!mounted) return;
          context.go('/device');
        }
        return;
      case DeviceIntent.goHome:
        if (t != null) await TaskService.instance.endFocus(t.id);
        if (!mounted) return;
        context.go('/device');
        return;
      case DeviceIntent.startFocus:
      case DeviceIntent.whatsNext:
      case DeviceIntent.pause:
        return;
      case null:
        // Free-form question — pass current task as context for grounded reply.
        String? ctx;
        if (t != null) {
          final stepsList = t.steps.asMap().entries
              .map((e) =>
                  '${e.key + 1}. ${e.value.text}${e.value.completed ? ' (done)' : ''}')
              .join('\n');
          final cs = t.currentStep;
          final csLine = cs != null
              ? 'Currently on step ${t.currentStepIndex + 1}: ${cs.text}'
              : 'No current step.';
          ctx = 'FOCUS MODE — task "${t.title}".\n'
              'Steps:\n$stepsList\n$csLine\n'
              'Answer in one or two short sentences. Grounded, no fluff.';
        }
        final reply = await VoiceService.instance
            .sendCommand(transcript, taskContext: ctx);
        if (reply.isNotEmpty) await VoiceService.instance.speak(reply);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    return DeviceShell(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            LayoutBuilder(builder: (context, c) {
              final size = c.maxWidth;
              return IgnorePointer(
                child: VoiceStateRing(
                  diameter: size * 0.96,
                  strokeWidth: 4.5,
                ),
              );
            }),
            if (t == null)
              const CircularProgressIndicator(color: AghieriColors.accent)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'STEP ${t.currentStepIndex + 1} of ${t.steps.length}',
                      style: AghieriTextStyles.label(
                        size: 12, color: AghieriColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AghieriTextStyles.heading(size: 22),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      t.currentStep?.text ?? 'All steps complete.',
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AghieriTextStyles.body(
                        size: 18, weight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              bottom: 28,
              child: Text(
                'tap to talk',
                style: AghieriTextStyles.caption(
                  size: 11, color: AghieriColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
