import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/task_model.dart';
import '../../services/claude_service.dart';
import '../../services/interaction_tracker.dart';
import '../../services/task_service.dart';
import '../../services/voice_service.dart';

class FocusScreen extends StatefulWidget {
  final String taskId;
  const FocusScreen({super.key, required this.taskId});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen>
    with TickerProviderStateMixin {
  TaskModel? _task;
  bool _loading = true;

  late AnimationController _fadeCtrl;
  late AnimationController _topoCtrl;
  late AnimationController _stepFadeCtrl;
  late AnimationController _pulseCtrl;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _topoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _stepFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _load();
    InteractionTracker.instance.track(InteractionType.focusStarted);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _topoCtrl.dispose();
    _stepFadeCtrl.dispose();
    _pulseCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  bool _generatingSteps = false;

  Future<void> _load() async {
    final task = await TaskService.instance.getTask(widget.taskId);
    if (mounted) setState(() { _task = task; _loading = false; });
    if (task != null) {
      await TaskService.instance.startFocus(task.id);
      // Auto-generate steps if task has none
      if (task.steps.isEmpty && !_generatingSteps) {
        _autoGenerateSteps(task);
      }
    }
  }

  Future<void> _autoGenerateSteps(TaskModel task) async {
    setState(() => _generatingSteps = true);
    try {
      final parsed = await ClaudeService.instance.parseInstruction(
        'Task: ${task.title}', source: 'step_gen');
      if (parsed.isNotEmpty && mounted) {
        final taskData = parsed.first;
        final rawSteps = (taskData['steps'] as List?) ?? [];
        if (rawSteps.isNotEmpty) {
          final steps = rawSteps.asMap().entries.map((e) {
            if (e.value is Map<String, dynamic>) {
              return TaskStep.fromJson(e.value as Map<String, dynamic>).toJson();
            }
            return TaskStep(id: '${e.key}', text: e.value.toString()).toJson();
          }).toList();
          await TaskService.instance.updateTask(task.id, {
            'steps': steps,
            'current_step_index': 0,
          });
          // Reload to get the updated task with steps
          final updated = await TaskService.instance.getTask(task.id);
          if (mounted) setState(() => _task = updated);
          // Announce first step
          if (updated?.currentStep != null) {
            VoiceService.instance.speak('First step. ${updated!.currentStep!.text}');
          }
        }
      }
    } catch (e) {
      debugPrint('[Focus] Auto step generation error: $e');
    }
    if (mounted) setState(() => _generatingSteps = false);
  }

  Future<void> _completeStep() async {
    if (_task == null) return;
    // Fade out current step
    await _stepFadeCtrl.reverse();
    await TaskService.instance.completeStep(_task!.id);
    await _load();
    // Fade in new step
    if (mounted) _stepFadeCtrl.forward();
    final step = _task?.currentStep;
    if (step != null) {
      VoiceService.instance.speak('Moving on. ${step.text}');
    } else {
      VoiceService.instance.speak('All steps done. Well done.');
    }
  }

  Future<void> _endFocus() async {
    if (_task != null) await TaskService.instance.endFocus(_task!.id);
    if (mounted) context.pop();
  }

  Future<void> _activateVoice() async {
    if (_isListening) {
      // Tap again to cancel
      await VoiceService.instance.stop();
      if (mounted) {
        _pulseCtrl.stop();
        _pulseCtrl.reset();
        setState(() => _isListening = false);
      }
      return;
    }
    setState(() => _isListening = true);
    _pulseCtrl.repeat(reverse: true);

    // Unlock audio for iOS Safari — must happen in user gesture context
    await VoiceService.instance.unlockAudio();

    try {
      final transcript = await VoiceService.instance.listen(
        onInterim: (_) {},
      );
      if (transcript.isNotEmpty) {
        final t = _task;
        String? context;
        if (t != null) {
          final stepsList = t.steps.asMap().entries
              .map((e) => '${e.key + 1}. ${e.value.text}'
                  '${e.value.completed ? ' (done)' : ''}')
              .join('\n');
          final current = t.currentStep;
          final currentLine = current != null
              ? 'Currently on step ${t.currentStepIndex + 1}: ${current.text}'
              : 'No current step.';
          context = 'FOCUS MODE — user is working on task "${t.title}".\n'
              'Steps:\n$stepsList\n$currentLine\n'
              'Give short, direct, grounded advice about this task only. '
              'Two to three sentences max. No fluff.';
        }
        await VoiceService.instance.sendCommand(transcript, taskContext: context);
        await _load();
      }
    } finally {
      if (mounted) {
        _pulseCtrl.stop();
        _pulseCtrl.reset();
        setState(() => _isListening = false);
      }
    }
  }

  /// Build text with per-letter 3D distortion wave.
  /// Slow undulation: each letter gets different scale + rotation + Y offset
  /// creating a ribbon-like depth effect. Optional chromatic [shadow] layer
  /// offset by [offsetX]/[offsetY] for the glow.
  Widget _buildDistortedText(
    String text, double animT, Color color, {
    Color? shadow,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    final chars = text.split('');
    final displayColor = shadow ?? color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(chars.length, (i) {
        final char = chars[i];
        // Slow wave — 20s cycle, each letter offset by 0.35 radians
        final phase = animT * 2 * pi + i * 0.35;
        // Dramatic Y wave — ±12px undulation
        final dy = 10.0 * sin(phase) + offsetY;
        // Per-letter rotation — ±8° for depth perspective
        final rot = 0.14 * sin(phase * 0.7 + i * 0.2);
        // Scale variation — 0.85 to 1.15 for 3D push/pull
        final scale = 1.0 + 0.15 * sin(phase * 0.5 + i * 0.4);
        // Slight horizontal drift for organic feel
        final dx = 2.0 * cos(phase * 0.8) + offsetX;

        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: rot,
            child: Transform.scale(
              scale: scale,
              child: Text(
                char,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: displayColor,
                  letterSpacing: 1.4,
                  decoration: TextDecoration.none,
                  shadows: shadow != null ? [] : [
                    Shadow(
                      color: displayColor.withOpacity(0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AghieriColors.bg,
        body: Center(child: CircularProgressIndicator(color: AghieriColors.accent)),
      );
    }

    if (_task == null) {
      return Scaffold(
        backgroundColor: AghieriColors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Task not found.', style: AghieriTextStyles.body()),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.pop(),
                child: Text('Go back',
                    style: AghieriTextStyles.body(color: AghieriColors.accent)),
              ),
            ],
          ),
        ),
      );
    }

    final task       = _task!;
    final screenW    = MediaQuery.of(context).size.width;
    final screenH    = MediaQuery.of(context).size.height;
    final circleSize = min(screenW * 0.88, screenH * 0.68);
    // HSL complement of task color, luminance-adjusted for AAA contrast
    final taskHsl = HSLColor.fromColor(task.color);
    final compHsl = taskHsl.withHue((taskHsl.hue + 180) % 360)
        .withSaturation((taskHsl.saturation * 0.8).clamp(0.0, 1.0))
        .withLightness(task.color.computeLuminance() > 0.35 ? 0.15 : 0.92);
    final textColor = compHsl.toColor();
    final allDone    = task.steps.isEmpty || task.progress >= 1.0;
    final currentStep = task.currentStep;
    final stepNum    = task.currentStepIndex + 1;
    final totalSteps = task.steps.length;

    return Scaffold(
      backgroundColor: AghieriColors.bg,
      body: FadeTransition(
        opacity: _fadeCtrl,
        child: AnimatedBuilder(
          animation: Listenable.merge([_topoCtrl, _pulseCtrl]),
          builder: (_, __) => Stack(
            children: [
              // ── Focus circle — tap anywhere for voice ──────────────────────
              Center(
                child: GestureDetector(
                  onTap: _activateVoice,
                  child: SizedBox(
                    width: circleSize,
                    height: circleSize,
                    child: CustomPaint(
                      painter: _FocusCirclePainter(
                        color: task.color,
                        animT: _topoCtrl.value,
                        progress: task.progress,
                        isListening: _isListening,
                        pulseT: _pulseCtrl.value,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Listening indicator overlay ────────────────────────────────
              if (_isListening)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated sound wave bars
                      SizedBox(
                        height: 40,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(5, (i) {
                            final phase = _pulseCtrl.value * 2 * pi + i * 0.8;
                            final barH = 12.0 + 28.0 * ((sin(phase) + 1) / 2);
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: 4,
                              height: barH,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: textColor.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Listening...',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          color: textColor.withOpacity(0.6),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Task title — at TOP of circle ─────────────────────────────
              if (!_isListening)
                Align(
                  alignment: const Alignment(0, -0.32),
                  child: SizedBox(
                    width: circleSize * 0.80,
                    child: SizedBox(
                      height: 84,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _buildDistortedText(
                              task.title,
                              _topoCtrl.value,
                              textColor.withOpacity(0.0),
                              shadow: HSLColor.fromColor(task.color)
                                  .withHue((HSLColor.fromColor(task.color).hue + 240) % 360)
                                  .withSaturation(0.9)
                                  .withLightness(0.5)
                                  .toColor()
                                  .withOpacity(0.35),
                              offsetX: -2.5,
                              offsetY: 1.5,
                            ),
                            _buildDistortedText(
                              task.title,
                              _topoCtrl.value,
                              textColor.withOpacity(0.0),
                              shadow: HSLColor.fromColor(task.color)
                                  .withHue((HSLColor.fromColor(task.color).hue + 30) % 360)
                                  .withSaturation(0.9)
                                  .withLightness(0.55)
                                  .toColor()
                                  .withOpacity(0.25),
                              offsetX: 2.0,
                              offsetY: -1.0,
                            ),
                            _buildDistortedText(
                              task.title,
                              _topoCtrl.value,
                              textColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Current step — single, centered in the middle ─────────────
              if (!_isListening && currentStep != null)
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: circleSize * 0.72,
                    child: FadeTransition(
                      opacity: _stepFadeCtrl,
                      child: GestureDetector(
                        onDoubleTap: _completeStep,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Step $stepNum of $totalSteps',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 1.4,
                                  color: textColor.withOpacity(0.50),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                currentStep.text,
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 26,
                                  height: 1.25,
                                  fontWeight: FontWeight.w400,
                                  color: textColor.withOpacity(0.95),
                                  decoration: TextDecoration.none,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'double-tap to complete · tap circle to ask',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w300,
                                  color: textColor.withOpacity(0.35),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Generating steps indicator — centered when no step yet ────
              if (!_isListening && currentStep == null && _generatingSteps)
                Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: textColor.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Breaking it down...',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                          color: textColor.withOpacity(0.5),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── All steps complete — centered ─────────────────────────────
              if (!_isListening && allDone && task.steps.isNotEmpty)
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    'All steps complete',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      color: textColor.withOpacity(0.80),
                      decoration: TextDecoration.none,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              // ── Back button ───────────────────────────────────────────────
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: GestureDetector(
                    onTap: _endFocus,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AghieriColors.surfaceHigh.withOpacity(0.8),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AghieriColors.textSecondary,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Bottom actions ────────────────────────────────────────────
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: allDone ? _endFocus : _completeStep,
                          child: Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AghieriColors.surfaceHigh.withOpacity(0.9),
                              border: Border.all(
                                color: task.color.withOpacity(0.50),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              allDone
                                  ? Icons.check_circle_rounded
                                  : Icons.check_rounded,
                              color: task.color,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        // Voice toggle button with listening state
                        GestureDetector(
                          onTap: _activateVoice,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening
                                  ? task.color.withOpacity(0.25)
                                  : AghieriColors.surfaceHigh.withOpacity(0.9),
                              border: Border.all(
                                color: _isListening
                                    ? task.color
                                    : AghieriColors.accent.withOpacity(0.50),
                                width: _isListening ? 2.0 : 1.5,
                              ),
                            ),
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none_rounded,
                              color: _isListening ? task.color : AghieriColors.accent,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
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

// ── Auto-contrast text color ──────────────────────────────────────────────────

Color _autoContrast(Color bg) =>
    bg.computeLuminance() > 0.35
        ? const Color(0xFF0A0A0F)
        : const Color(0xFFF0EFE8);

// ── Focus Circle Painter — organic bezier blobs + progress ring ──────────────

class _FocusCirclePainter extends CustomPainter {
  final Color color;
  final double animT;
  final double progress; // 0.0 to 1.0
  final bool isListening;
  final double pulseT;

  const _FocusCirclePainter({
    required this.color,
    required this.animT,
    required this.progress,
    this.isListening = false,
    this.pulseT = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width / 2;
    final cy     = size.height / 2;
    final r      = size.width / 2;
    final center = Offset(cx, cy);

    // Breathing effect when listening — circle gently scales
    final breatheScale = isListening
        ? 1.0 + 0.02 * sin(pulseT * 2 * pi)
        : 1.0;
    final br = r * 0.85 * breatheScale; // visible gap from outer progress ring

    // ── Progress ring at outer edge (with gap from main circle) ──────────
    final ringR = r - 2.0;
    _drawProgressRing(canvas, center, ringR, r);

    // Clip to inner circle (with gap from ring)
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: br)));

    // ── Derive vivid palette from task color ─────────────────────────────
    final baseHsl = HSLColor.fromColor(color);
    final palette = <HSLColor>[
      baseHsl,
      baseHsl.withHue((baseHsl.hue + 30) % 360)
          .withSaturation((baseHsl.saturation * 1.3).clamp(0.0, 1.0)),
      baseHsl.withHue((baseHsl.hue - 30 + 360) % 360)
          .withSaturation((baseHsl.saturation * 1.2).clamp(0.0, 1.0)),
      baseHsl.withHue((baseHsl.hue + 60) % 360)
          .withSaturation((baseHsl.saturation * 1.4).clamp(0.0, 1.0)),
      baseHsl.withHue((baseHsl.hue - 60 + 360) % 360)
          .withSaturation((baseHsl.saturation * 1.1).clamp(0.0, 1.0)),
    ];

    // ── Base gradient fill using palette ─────────────────────────────────
    final gradPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          0.3 * sin(animT * 2 * pi),
          0.3 * cos(animT * 2 * pi * 0.7),
        ),
        radius: 1.0,
        colors: [
          palette[0].toColor(),
          palette[1].toColor(),
          palette[2].toColor(),
          palette[3].toColor(),
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, gradPaint);

    // ── Vivid lava lamp blobs — fewer, larger, fully opaque cores ────────
    final rng = _FocusRng(color.toARGB32());

    for (int i = 0; i < 6; i++) {
      final paletteColor = palette[i % palette.length];

      // Lissajous drift pattern — slower, smoother
      final lissA = rng.at(i * 4) * 2 + 1;       // frequency ratio A
      final lissB = rng.at(i * 4 + 1) * 2 + 1;   // frequency ratio B
      final phaseOff = rng.at(i * 4 + 2) * 2 * pi;
      final drift = 0.35 + rng.at(i * 4 + 3) * 0.15; // drift amplitude

      final bx = cx + r * drift * sin(animT * 2 * pi * lissA * 0.3 + phaseOff);
      final by = cy + r * drift * cos(animT * 2 * pi * lissB * 0.3 + phaseOff * 0.7);

      // Blob radius: 0.4–0.7 of circle radius
      final blobR = r * (0.4 + rng.at(i * 5) * 0.3);

      // Vivid core color — full opacity, boosted saturation
      final coreColor = paletteColor
          .withSaturation((paletteColor.saturation * 1.4).clamp(0.0, 1.0))
          .withLightness((paletteColor.lightness * 0.9).clamp(0.15, 0.85))
          .toColor();

      // Wide soft haze layer (heavy blur, semi-opaque)
      final hazePath = _organicBlobPath(
        Offset(bx, by), blobR * 1.2, i + 100, animT,
      );
      canvas.drawPath(hazePath,
        Paint()
          ..color = coreColor.withOpacity(0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18),
      );

      // Tight saturated core (moderate blur for liquid blending)
      final corePath = _organicBlobPath(
        Offset(bx, by), blobR * 0.7, i, animT,
      );
      canvas.drawPath(corePath,
        Paint()
          ..color = coreColor.withOpacity(0.85)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
      );
    }

  }

  /// Draw the progress ring + listening state at the outer edge
  /// Includes +20px glow bleed in complementary color
  void _drawProgressRing(Canvas canvas, Offset center, double ringR, double outerR) {
    final baseHsl = HSLColor.fromColor(color);
    final breathe = 0.78 + 0.22 * sin(animT * 2 * pi);
    final rc      = _autoContrast(color);

    // Complementary color for glow
    final compHsl = baseHsl.withHue((baseHsl.hue + 180) % 360)
        .withSaturation(1.0)
        .withLightness(0.6);
    final compColor = compHsl.toColor();

    // +20px glow bleed — colored halo around the ring
    canvas.drawCircle(center, ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..color = compColor.withOpacity(0.12 * breathe)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));

    // Listening state — pulsing green ring
    if (isListening) {
      final listenPulse = 0.3 + 0.7 * ((sin(pulseT * 2 * pi) + 1) / 2);
      canvas.drawCircle(center, ringR,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color       = const Color(0xFF4ADE80).withOpacity(0.5 * listenPulse)
          ..maskFilter  = MaskFilter.blur(BlurStyle.normal, 16 * listenPulse),
      );
      canvas.drawCircle(center, ringR,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color       = const Color(0xFF4ADE80).withOpacity(0.8),
      );
    } else {
      // Dim base ring (always visible)
      canvas.drawCircle(center, ringR,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color       = rc.withOpacity(0.10),
      );
    }

    // Progress arc
    if (progress > 0.001) {
      final rect       = Rect.fromCircle(center: center, radius: ringR);
      final sweepAngle = progress * 2 * pi;

      canvas.drawArc(rect, -pi / 2, sweepAngle, false,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 24
          ..strokeCap   = StrokeCap.round
          ..color       = compColor.withOpacity(0.25 * breathe)
          ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 18),
      );
      canvas.drawArc(rect, -pi / 2, sweepAngle, false,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap   = StrokeCap.round
          ..color       = color.withOpacity(0.35 * breathe)
          ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawArc(rect, -pi / 2, sweepAngle, false,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap   = StrokeCap.round
          ..color       = rc.withOpacity(0.75 * breathe),
      );
    }
  }

  /// Generate an organic closed bezier path with [numPoints] control points.
  Path _organicBlobPath(Offset center, double radius, int seed, double t) {
    const n = 7;
    final rng = _FocusRng(seed * 7919 + 31);
    final points = <Offset>[];

    for (int i = 0; i < n; i++) {
      final angle  = i * 2 * pi / n;
      final rOff   = rng.at(i) * 0.55;
      final animOff = 0.15 * sin(t * 2 * pi + i * 0.9 + seed * 0.3);
      final rr     = radius * (1.0 + rOff + animOff);
      points.add(Offset(
        center.dx + rr * cos(angle),
        center.dy + rr * sin(angle),
      ));
    }

    // Build smooth closed cubic bezier path
    final path = Path();
    path.moveTo(
      (points[n - 1].dx + points[0].dx) / 2,
      (points[n - 1].dy + points[0].dy) / 2,
    );

    for (int i = 0; i < n; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_FocusCirclePainter old) =>
      old.animT != animT ||
      old.color != color ||
      old.progress != progress ||
      old.isListening != isListening ||
      old.pulseT != pulseT;
}

// Deterministic value lookup by index (no mutable state)
class _FocusRng {
  final int seed;
  const _FocusRng(this.seed);

  double at(int i) {
    int s = (seed ^ (i * 2654435761)) & 0x7FFFFFFF;
    s = (s * 1664525 + 1013904223) & 0x7FFFFFFF;
    return s / 0x7FFFFFFF;
  }
}
