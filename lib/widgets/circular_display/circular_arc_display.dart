import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/task_model.dart';
import '../../core/theme/app_theme.dart';

/// Day-clock / moon-phase circular display.
///
/// The circle represents the user's waking day:
/// - Wake time = left (π = 9 o'clock position)
/// - Sleep time = right (2π = 3 o'clock position)
/// - Day arc runs clockwise: left → top → right (upper 180°)
/// - Bottom half = sleeping arc (dark, new-moon feel)
///
/// Visual layers (back to front):
/// 1. Outer dim ring
/// 2. Night arc (bottom, very dark)
/// 3. Completed day arc — vibrant 3-layer glow
/// 4. Remaining day arc — dim
/// 5. Task dots at scheduled times
/// 6. Current time indicator (pulsing)
/// 7. Center content: time + date
///
/// When [tabIndex] > 0 (Week/Month/Year), draws a "beach ball" circle
/// where each task gets a proportional wedge colored by its [TaskModel.color].
class CircularArcDisplay extends StatefulWidget {
  final List<TaskModel> tasks;
  final TaskModel? activeTask;
  final double size;
  final bool showFocusState;
  final String wakeTime;    // '07:00'
  final String sleepTime;   // '23:00'
  final String uiMode;      // 'day_clock' | 'task_progress' | 'abstract'
  final bool isListening;
  final int tabIndex;        // 0=Today, 1=Week, 2=Month, 3=Year
  final void Function(String taskId)? onTaskTap;

  const CircularArcDisplay({
    super.key,
    required this.tasks,
    this.activeTask,
    required this.size,
    this.showFocusState = false,
    this.wakeTime = '07:00',
    this.sleepTime = '23:00',
    this.uiMode = 'day_clock',
    this.isListening = false,
    this.tabIndex = 0,
    this.onTaskTap,
  });

  @override
  State<CircularArcDisplay> createState() => _CircularArcDisplayState();
}

class _CircularArcDisplayState extends State<CircularArcDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _masterCtrl;

  @override
  void initState() {
    super.initState();
    _masterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _masterCtrl.dispose();
    super.dispose();
  }

  String? _hoveredTaskTitle;
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _masterCtrl,
        builder: (_, __) {
          final now = DateTime.now();

          // Select painter — same abstract moon for all tabs
          final painter = switch (widget.uiMode) {
            'task_progress' => _TaskProgressPainter(
                tasks: widget.tasks,
                animT: _masterCtrl.value,
              ) as CustomPainter,
            'abstract' => _AbstractPainter(
                tasks: widget.tasks,
                animT: _masterCtrl.value,
                now: now,
                wakeTime: widget.wakeTime,
                sleepTime: widget.sleepTime,
                isListening: widget.isListening,
                tabIndex: widget.tabIndex,
              ),
            _ => _DayClockPainter(
                tasks: widget.tasks,
                activeTask: widget.activeTask,
                animT: _masterCtrl.value,
                now: now,
                wakeTime: widget.wakeTime,
                sleepTime: widget.sleepTime,
                showFocusState: widget.showFocusState,
              ),
          };

          // Hover support for task bands (tap handled by parent GestureDetector)
          return MouseRegion(
            onHover: (event) {
              final title = _hitTestMoonBands(
                event.localPosition, widget.size, widget.tasks,
                widget.wakeTime, widget.sleepTime);
              if (title != _hoveredTaskTitle) {
                setState(() {
                  _hoveredTaskTitle = title;
                  _hoverPosition = event.localPosition;
                });
              }
            },
            onExit: (_) {
              if (_hoveredTaskTitle != null) {
                setState(() {
                  _hoveredTaskTitle = null;
                  _hoverPosition = null;
                });
              }
            },
            child: Stack(
              children: [
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: painter,
                    child: Center(
                      child: _CenterContent(
                        now: now,
                        size: widget.size,
                        uiMode: widget.uiMode,
                        tasks: widget.tasks,
                        tabIndex: widget.tabIndex,
                      ),
                    ),
                  ),
                ),
                if (_hoveredTaskTitle != null && _hoverPosition != null)
                  Positioned(
                    left: (_hoverPosition!.dx + 12).clamp(0, widget.size - 120),
                    top: (_hoverPosition!.dy - 32).clamp(0, widget.size - 28),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AghieriColors.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AghieriColors.surfaceHigh),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Text(
                        _hoveredTaskTitle!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AghieriColors.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Hit test for beach ball segments — returns task title or null.
  String? _hitTestBeachBall(Offset pos, double size, List<TaskModel> tasks) {
    if (tasks.isEmpty) return null;
    final cx = size / 2;
    final cy = size / 2;
    final r = size * 0.44;
    final dx = pos.dx - cx;
    final dy = pos.dy - cy;
    if (dx * dx + dy * dy > r * r) return null;

    // Calculate angle from top (0 at top, clockwise)
    var angle = atan2(dx, -dy); // 0 at top, CW positive
    if (angle < 0) angle += 2 * pi;

    final sliceAngle = 2 * pi / tasks.length;
    final idx = (angle / sliceAngle).floor().clamp(0, tasks.length - 1);
    return tasks[idx].title;
  }

  /// Compute longitude range (phi1, phi2) for a task on the sphere.
  (double, double)? _taskLongitudeBounds(TaskModel task,
      int wakeMin, int sleepMin, int dayDur,
      double dayFrac, int unschedIdx, int unschedTotal) {
    double sf, ef;
    if (task.scheduledTime != null) {
      final startMin = _parseTimeMinutes(task.scheduledTime!);
      final endMin = task.scheduledEndTime != null
          ? _parseTimeMinutes(task.scheduledEndTime!)
          : startMin + 60;
      int se = startMin - wakeMin; if (se < 0) se += 1440;
      int ee = endMin - wakeMin;   if (ee < 0) ee += 1440;
      sf = (se / dayDur).clamp(0.0, 1.0);
      ef = (ee / dayDur).clamp(0.0, 1.0);
    } else {
      final futureStart = dayFrac;
      final futureRange = (1.0 - futureStart).clamp(0.1, 1.0);
      final slotSize = futureRange / (unschedTotal + 1);
      sf = (futureStart + (unschedIdx + 1) * slotSize - slotSize * 0.3).clamp(0.0, 1.0);
      ef = (futureStart + (unschedIdx + 1) * slotSize + slotSize * 0.3).clamp(0.0, 1.0);
    }
    // Map to longitude: 0 → -π/2, 1 → π/2
    return (-pi / 2 + sf * pi, -pi / 2 + ef * pi);
  }

  /// Hit test a tap point against longitude stripe geometry.
  /// Returns the longitude (phi) of the tap point on the sphere, or null if outside.
  double? _tapToLongitude(Offset pos, double size) {
    final cx = size / 2;
    final cy = size / 2;
    final moonR = size * 0.42;
    final dx = pos.dx - cx;
    final dy = pos.dy - cy;
    if (dx * dx + dy * dy > moonR * moonR) return null;

    // Inverse spherical projection: find latitude and longitude
    // y = cy - R * sin(lat) → sin(lat) = -(pos.dy - cy) / R
    final sinLat = -dy / moonR;
    if (sinLat.abs() > 1.0) return null;
    final lat = asin(sinLat.clamp(-1.0, 1.0));
    final cosLat = cos(lat);
    if (cosLat.abs() < 0.001) return null; // at pole, ambiguous

    // x = cx + R * cos(lat) * sin(phi) → sin(phi) = dx / (R * cos(lat))
    final sinPhi = dx / (moonR * cosLat);
    if (sinPhi.abs() > 1.0) return null;
    return asin(sinPhi.clamp(-1.0, 1.0));
  }

  /// Hit test returning task ID for navigation (longitude stripe geometry).
  String? _hitTestMoonBandId(Offset pos, double size, List<TaskModel> tasks,
      String wakeTime, String sleepTime) {
    final tapPhi = _tapToLongitude(pos, size);
    if (tapPhi == null) return null;

    final wakeMin = _parseTimeMinutes(wakeTime);
    final sleepMin = _parseTimeMinutes(sleepTime);
    int dayDur = sleepMin - wakeMin;
    if (dayDur <= 0) dayDur += 1440;
    // Approximate dayFrac for unscheduled distribution
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    int elapsed = nowMin - wakeMin; if (elapsed < 0) elapsed += 1440;
    final dayFrac = (elapsed / dayDur).clamp(0.0, 1.0);

    final unsched = tasks.where((t) => t.scheduledTime == null).toList();
    int ui = 0;
    for (final task in tasks) {
      final isUnsched = task.scheduledTime == null;
      final bounds = _taskLongitudeBounds(task, wakeMin, sleepMin, dayDur,
          dayFrac, isUnsched ? ui : 0, unsched.length);
      if (isUnsched) ui++;
      if (bounds == null) continue;
      if (tapPhi >= bounds.$1 && tapPhi <= bounds.$2) return task.id;
    }
    return null;
  }

  /// Hit test for longitude stripe segments (returns title for tooltip).
  String? _hitTestMoonBands(Offset pos, double size, List<TaskModel> tasks,
      String wakeTime, String sleepTime) {
    final tapPhi = _tapToLongitude(pos, size);
    if (tapPhi == null) return null;

    final wakeMin = _parseTimeMinutes(wakeTime);
    final sleepMin = _parseTimeMinutes(sleepTime);
    int dayDur = sleepMin - wakeMin;
    if (dayDur <= 0) dayDur += 1440;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    int elapsed = nowMin - wakeMin; if (elapsed < 0) elapsed += 1440;
    final dayFrac = (elapsed / dayDur).clamp(0.0, 1.0);

    final unsched = tasks.where((t) => t.scheduledTime == null).toList();
    int ui = 0;
    for (final task in tasks) {
      final isUnsched = task.scheduledTime == null;
      final bounds = _taskLongitudeBounds(task, wakeMin, sleepMin, dayDur,
          dayFrac, isUnsched ? ui : 0, unsched.length);
      if (isUnsched) ui++;
      if (bounds == null) continue;
      if (tapPhi >= bounds.$1 && tapPhi <= bounds.$2) return task.title;
    }
    return null;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Draws the task ring at radius [r] around [center].
/// Tasks with scheduledTime are positioned by their time slot on the ring.
/// Active task arc glows; completed task arcs glow fully.
void _drawTaskRing(
  Canvas canvas,
  Offset center,
  double r,
  double animT,
  List<TaskModel> tasks, {
  double strokeWidth = 6,
  String wakeTime = '07:00',
  String sleepTime = '23:00',
  TaskModel? activeTask,
}) {
  // Dim base ring
  canvas.drawCircle(
    center, r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = AghieriColors.surfaceHigh,
  );

  final scheduledTasks = tasks.where((t) => t.scheduledTime != null).toList();
  if (scheduledTasks.isEmpty) return;

  final wakeMin  = _parseTimeMinutes(wakeTime);
  final sleepMin = _parseTimeMinutes(sleepTime);
  final rect     = Rect.fromCircle(center: center, radius: r);

  for (final task in scheduledTasks) {
    final startMin = _parseTimeMinutes(task.scheduledTime!);
    final endMin   = task.scheduledEndTime != null
        ? _parseTimeMinutes(task.scheduledEndTime!)
        : startMin + 60;

    final startAngle = _timeToRingAngle(startMin, wakeMin, sleepMin);
    final endAngle   = _timeToRingAngle(endMin,   wakeMin, sleepMin);
    var   sweep      = endAngle - startAngle;
    if (sweep <= 0) sweep += 2 * pi;
    sweep = sweep.clamp(0.01, 1.85 * pi);

    final isActive = activeTask?.id == task.id;
    final breathe  = (isActive || task.isComplete)
        ? (0.80 + 0.20 * sin(animT * 2 * pi))
        : 1.0;

    // Glow layer for active / complete tasks
    if (isActive || task.isComplete) {
      canvas.drawArc(rect, startAngle, sweep, false,
        Paint()
          ..style      = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 3.2
          ..strokeCap  = StrokeCap.round
          ..color      = task.color.withOpacity(
              (isActive ? 0.32 : 0.22) * breathe)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // Main arc
    canvas.drawArc(rect, startAngle, sweep, false,
      Paint()
        ..style      = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap  = StrokeCap.round
        ..color      = task.color.withOpacity(
            task.isComplete ? 0.90 : (isActive ? 0.70 : 0.25)),
    );
  }
}

/// Map a time-of-day to a ring angle.
/// wakeTime → −π/2 (12 o'clock), sleepTime → −π/2 + 2π (back to top).
double _timeToRingAngle(int timeMin, int wakeMin, int sleepMin) {
  int dayDuration = sleepMin - wakeMin;
  if (dayDuration <= 0) dayDuration += 1440;
  int elapsed = timeMin - wakeMin;
  if (elapsed < 0) elapsed += 1440;
  final frac = (elapsed / dayDuration).clamp(0.0, 1.0);
  return -pi / 2 + frac * 2 * pi;
}

/// Parse "HH:MM" → minutes since midnight
int _parseTimeMinutes(String t) {
  final parts = t.split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

/// Given wake/sleep minutes and current minutes, return arc angle on the circle.
/// Wake = π (left), sleep = 2π (right), traversing through the top (upper half).
double _timeToAngle(int currentMin, int wakeMin, int sleepMin) {
  int dayDuration = sleepMin - wakeMin;
  if (dayDuration <= 0) dayDuration += 1440;
  int elapsed = currentMin - wakeMin;
  if (elapsed < 0) elapsed += 1440;
  final frac = (elapsed / dayDuration).clamp(0.0, 1.0);
  // Wake = π, Sleep = 2π (going through top at 3π/2 or equivalently −π/2)
  // Arc direction: from π, going counter-clockwise through 3π/2 to 2π
  // In Flutter: 0 = 3 o'clock, angles go clockwise.
  // Wake (9 o'clock) = π
  // Top (12 o'clock) = -π/2 = 3π/2
  // Sleep (3 o'clock) = 0 (or 2π)
  // Going from π backward (counter-clockwise) to 0 covers the top half.
  // In canvas angles: wake=π, sleep=0, traversal = π * (1 - frac) going counter-clockwise
  // Simpler: traverse the upper arc from π → 0 counter-clockwise
  // Upper arc: from π, decreasing to 0 (through π/2 at top-left and 0 at right)
  // Wait — 9 o'clock = π, 12 o'clock = 3π/2 (clockwise from 0), but that's bottom.
  // Actually in Flutter canvas: 0 = right (3 o'clock), π/2 = bottom, π = left, 3π/2 = top.
  // So: wake = π (left = 9 o'clock), sleep = 0 (right = 3 o'clock)
  // Top = 3π/2 (but going clockwise from wake π → 3π/2 goes THROUGH BOTTOM)
  // We want to go counter-clockwise: π → π/2 → 0 (through top-right-ish)
  // Actually to go through the TOP (12 o'clock = 3π/2 in Flutter) from left (π):
  // Counter-clockwise from π: π → π/2 → 0 → 7π/4 → 3π/2 = going right then looping
  // Clockwise from π: π → 3π/2 → 2π = 0 is the BOTTOM path
  // To go through top from left to right:
  //   Flutter: top = -π/2 (or equivalently 3π/2), left = π, right = 0 (2π)
  //   Path from π going through -π/2 to 0: this is the counter-clockwise arc
  //   In terms of angle values: π → π/2 → 0 is counter-clockwise (decreasing)
  //   But π/2 is BOTTOM in Flutter...
  // Let's be precise: Flutter drawArc(startAngle, sweepAngle)
  //   0 = right (3 o'clock)
  //   π/2 = bottom (6 o'clock)
  //   π = left (9 o'clock)
  //   3π/2 = top (12 o'clock) [or -π/2]
  // Day arc: wake (9 o'clock = π) → top (12 o'clock = 3π/2 = -π/2) → sleep (3 o'clock = 0)
  // This is the UPPER arc going clockwise from left through top to right.
  // startAngle = π, sweepAngle = π (clockwise sweep from π to 2π/0)
  // Going clockwise: π → 3π/2 → 2π → 0
  // Wait: clockwise from π with sweep π: π + π = 2π = 0.
  //   Midpoint: π + π/2 = 3π/2 = TOP. YES! This is correct.
  // So day arc: startAngle = π, sweepAngle = π (full day)
  // Current position at frac: π + frac * π
  return pi + frac * pi;
}

Color _blendTaskColors(List<TaskModel> tasks) {
  if (tasks.isEmpty) return AghieriColors.accent;
  int r = 0, g = 0, b = 0;
  for (final t in tasks) {
    r += t.color.red;
    g += t.color.green;
    b += t.color.blue;
  }
  return Color.fromARGB(255, r ~/ tasks.length, g ~/ tasks.length, b ~/ tasks.length);
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _DayClockPainter extends CustomPainter {
  final List<TaskModel> tasks;
  final TaskModel? activeTask;
  final double animT;
  final DateTime now;
  final String wakeTime;
  final String sleepTime;
  final bool showFocusState;

  _DayClockPainter({
    required this.tasks,
    this.activeTask,
    required this.animT,
    required this.now,
    required this.wakeTime,
    required this.sleepTime,
    this.showFocusState = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;
    final arcR = r * 0.82; // radius where the day arc sits

    // Times in minutes
    final wakeMin  = _parseTimeMinutes(wakeTime);
    final sleepMin = _parseTimeMinutes(sleepTime);
    final nowMin   = now.hour * 60 + now.minute;

    // Current position angle
    final currentAngle = _timeToAngle(nowMin, wakeMin, sleepMin);
    // Wake angle = π, sleep angle = 2π (0)
    const wakeAngle  = pi;
    const sleepAngle = 2 * pi; // same as 0

    // Completed arc: from π to currentAngle (clockwise)
    final completedSweep = currentAngle - wakeAngle; // 0 to π
    // Remaining arc: from currentAngle to 2π
    final remainingSweep = (sleepAngle - currentAngle).clamp(0.0, pi);

    // Dominant color
    final domColor = activeTask?.color ??
        (tasks.isNotEmpty ? _blendTaskColors(tasks) : AghieriColors.accent);

    // ── Outer task completion ring (drawn BEFORE clip, sits at widget edge) ──────
    _drawTaskRing(
      canvas, Offset(cx, cy), r * 0.965, animT, tasks,
      strokeWidth: 5,
      wakeTime: wakeTime,
      sleepTime: sleepTime,
      activeTask: activeTask,
    );

    // Clip to circle
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // ── Layer 1: Background ────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()..color = AghieriColors.bg,
    );

    // ── Layer 2: Outer dim ring (full circle outline) ──────────────────────────
    canvas.drawCircle(
      Offset(cx, cy), arcR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = AghieriColors.surface.withOpacity(0.6),
    );

    // ── Layer 3: Night arc (bottom half — π to 2π clockwise = bottom) ─────────
    // Bottom arc: start = 0 (right), sweep = π (going clockwise through bottom to left)
    // Or equivalently: start = 0, sweep = π covers bottom half.
    // We want the sleeping half: from sleep (right=0) clockwise through bottom to wake (left=π)
    final nightRect = Rect.fromCircle(center: Offset(cx, cy), radius: arcR);
    canvas.drawArc(
      nightRect, 0, pi, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = const Color(0xFF0A0A0F).withOpacity(0.9),
    );
    // Subtle night arc visible stroke
    canvas.drawArc(
      nightRect, 0, pi, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AghieriColors.surfaceHigh.withOpacity(0.3),
    );

    // ── Layer 4: Remaining day arc (dim with faint glow) ─────────────────────
    if (remainingSweep > 0.01) {
      final remRect = Rect.fromCircle(center: Offset(cx, cy), radius: arcR);
      // Faint glow halo behind remaining arc
      canvas.drawArc(
        remRect, currentAngle, remainingSweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..color = domColor.withOpacity(0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // Dim foreground line
      canvas.drawArc(
        remRect, currentAngle, remainingSweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..color = domColor.withOpacity(0.28),
      );
    }

    // ── Layer 5: Completed day arc — 3 passes for glow depth ─────────────────
    if (completedSweep > 0.01) {
      final compRect = Rect.fromCircle(center: Offset(cx, cy), radius: arcR);

      // Feather start: fade in over first 20°
      // Feather end: fade out over last 20°
      // We achieve this with opacity — at edges the glow dominates, the crisp line fades

      // Breathing factor — arc slowly pulses in brightness
      final breathe = 0.85 + 0.15 * sin(animT * 2 * pi);

      // Pass 1 — wide outer diffuse halo (vibrant bloom)
      canvas.drawArc(
        compRect, wakeAngle, completedSweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 36
          ..strokeCap = StrokeCap.round
          ..color = domColor.withOpacity(0.22 * breathe)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );

      // Pass 2 — tight bloom ring
      canvas.drawArc(
        compRect, wakeAngle, completedSweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round
          ..color = domColor.withOpacity(0.45 * breathe)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );

      // Pass 3 — soft inner edge (fills out the luminosity)
      canvas.drawArc(
        compRect, wakeAngle, completedSweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = domColor.withOpacity(0.70 * breathe)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

      // Pass 4 — crisp foreground line with sweep gradient (full intensity)
      canvas.drawArc(
        compRect, wakeAngle, completedSweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            center: Alignment.center,
            startAngle: wakeAngle,
            endAngle: wakeAngle + completedSweep,
            colors: [
              domColor.withOpacity(0.45),
              domColor.withOpacity(1.0),
              domColor.withOpacity(0.90),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(compRect),
      );

      // Shimmer — bright spot sweeping slowly along completed arc
      final shimmerPos = wakeAngle + completedSweep * ((animT * 0.6) % 1.0);
      final shimmerX = cx + arcR * cos(shimmerPos);
      final shimmerY = cy + arcR * sin(shimmerPos);
      canvas.drawCircle(
        Offset(shimmerX, shimmerY), 4,
        Paint()
          ..color = Colors.white.withOpacity(0.25 * (0.5 + 0.5 * sin(animT * 2 * pi)))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // ── Layer 6: Task dots at scheduled times ─────────────────────────────────
    for (final task in tasks) {
      if (task.scheduledTime == null) continue;
      final taskMin = _parseTimeMinutes(task.scheduledTime!);
      final taskAngle = _timeToAngle(taskMin, wakeMin, sleepMin);

      // Check if within waking hours
      final frac = (taskAngle - wakeAngle) / pi;
      if (frac < 0 || frac > 1) continue;

      final dotX = cx + arcR * cos(taskAngle);
      final dotY = cy + arcR * sin(taskAngle);
      final breathe = 0.95 + 0.05 * sin((animT + frac) * 2 * pi);

      // Glow halo
      canvas.drawCircle(
        Offset(dotX, dotY), 14 * breathe,
        Paint()
          ..color = task.color.withOpacity(0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Dot
      canvas.drawCircle(
        Offset(dotX, dotY), 8 * breathe,
        Paint()..color = task.color,
      );

      // White center
      canvas.drawCircle(
        Offset(dotX, dotY), 3 * breathe,
        Paint()..color = Colors.white.withOpacity(0.8),
      );
    }

    // ── Layer 7: Current time indicator ───────────────────────────────────────
    // Pulse: scale + opacity
    final pulse = 1.0 + 0.15 * sin(animT * 2 * pi);
    final pulseOpacity = 0.7 + 0.3 * sin(animT * 2 * pi);

    final nowX = cx + arcR * cos(currentAngle);
    final nowY = cy + arcR * sin(currentAngle);

    // Outer glow
    canvas.drawCircle(
      Offset(nowX, nowY), 18 * pulse,
      Paint()
        ..color = domColor.withOpacity(0.25 * pulseOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Colored ring
    canvas.drawCircle(
      Offset(nowX, nowY), 10 * pulse,
      Paint()
        ..color = domColor.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // White center
    canvas.drawCircle(
      Offset(nowX, nowY), 5.0,
      Paint()..color = Colors.white.withOpacity(pulseOpacity),
    );

    // Focus state overlay: if active, paint task color fill
    if (showFocusState && activeTask != null) {
      _paintFocusOverlay(canvas, cx, cy, r, activeTask!.color);
    }
  }

  void _paintFocusOverlay(Canvas canvas, double cx, double cy, double r, Color taskColor) {
    // Semi-transparent task color fill
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()..color = taskColor.withOpacity(0.18),
    );

    // Topo blobs
    final rng = Random(taskColor.value);
    for (int i = 0; i < 8; i++) {
      final ox = (rng.nextDouble() - 0.5) * r * 1.0;
      final oy = (rng.nextDouble() - 0.5) * r * 1.0;
      final br = r * (0.15 + rng.nextDouble() * 0.32);
      final phase = (i / 8 + animT * 0.3 + rng.nextDouble() * 0.2) % 1.0;
      final dl = 0.08 * sin(phase * 2 * pi);
      final hsl = HSLColor.fromColor(taskColor);
      final c = hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0))
          .toColor().withOpacity(0.25);
      canvas.drawCircle(Offset(cx + ox, cy + oy), br, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_DayClockPainter old) =>
      old.animT != animT ||
      old.wakeTime != wakeTime ||
      old.sleepTime != sleepTime ||
      old.tasks != tasks ||
      old.activeTask != activeTask ||
      old.now.minute != now.minute;
}

// ── Center content ────────────────────────────────────────────────────────────

class _CenterContent extends StatelessWidget {
  final DateTime now;
  final double size;
  final String uiMode;
  final List<TaskModel> tasks;
  final int tabIndex;

  const _CenterContent({
    required this.now,
    required this.size,
    this.uiMode = 'day_clock',
    this.tasks = const [],
    this.tabIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hour = now.hour;
    final min  = now.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12  = hour % 12 == 0 ? 12 : hour % 12;
    final timeStr = '$h12:$min';

    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    final dateStr = '${days[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}';

    // Task progress mode: show completed/total count instead of time
    if (uiMode == 'task_progress') {
      final total     = tasks.fold(0, (s, t) => s + t.steps.length);
      final completed = tasks.fold(0, (s, t) => s + t.completedSteps);
      final pct = total > 0 ? (completed / total * 100).round() : 0;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$pct%',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: size * 0.14,
                fontWeight: FontWeight.w600,
                color: AghieriColors.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
            Text(
              'done today',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: size * 0.042,
                fontWeight: FontWeight.w300,
                color: AghieriColors.textSecondary,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    }

    // Abstract mode: no text on any tab — the moon phase speaks for itself
    if (uiMode == 'abstract') return const SizedBox.shrink();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: size * 0.13,
                  fontWeight: FontWeight.w500,
                  color: AghieriColors.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 3),
                child: Text(
                  ampm,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: size * 0.045,
                    fontWeight: FontWeight.w300,
                    color: AghieriColors.textSecondary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: size * 0.042,
              fontWeight: FontWeight.w300,
              color: AghieriColors.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Task Progress Painter ─────────────────────────────────────────────────────
/// Full ring split into colored segments per task; completed portion glows.
class _TaskProgressPainter extends CustomPainter {
  final List<TaskModel> tasks;
  final double animT;

  _TaskProgressPainter({required this.tasks, required this.animT});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.44;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Outer dim ring
    canvas.drawCircle(
      Offset(cx, cy), r + 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AghieriColors.surfaceHigh,
    );

    final totalSteps = tasks.fold(0, (s, t) => s + t.steps.length);
    if (totalSteps == 0 || tasks.isEmpty) {
      // No tasks — dim full circle
      canvas.drawArc(rect, -pi / 2, 2 * pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = AghieriColors.surface,
      );
      return;
    }

    // Draw each task as a proportional arc segment
    double startAngle = -pi / 2; // start at top (12 o'clock)
    for (final task in tasks) {
      if (task.steps.isEmpty) continue;
      final fraction = task.steps.length / totalSteps;
      final sweep    = fraction * 2 * pi;
      final completedFrac = task.steps.isNotEmpty
          ? task.completedSteps / task.steps.length
          : 0.0;

      // Dim background segment
      canvas.drawArc(rect, startAngle, sweep - 0.03, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.butt
          ..color = task.color.withOpacity(0.18),
      );

      // Completed portion with glow
      if (completedFrac > 0) {
        final completedSweep = sweep * completedFrac;
        final breathe = 0.85 + 0.15 * sin(animT * 2 * pi);

        // Bloom
        canvas.drawArc(rect, startAngle, completedSweep, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 22
            ..strokeCap = StrokeCap.round
            ..color = task.color.withOpacity(0.18 * breathe)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
        // Crisp line
        canvas.drawArc(rect, startAngle, completedSweep, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round
            ..color = task.color.withOpacity(0.90),
        );
      }

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_TaskProgressPainter old) =>
      old.animT != animT || old.tasks != tasks;
}

// ── Abstract / Moon Phase Painter ────────────────────────────────────────────
/// Moon-phase circle: white portion = time remaining in the day.
/// Shadow sweeps from right as the day progresses (waning moon metaphor).
/// Outer task ring shows completion — same as _TaskProgressPainter but separated
/// from the moon circle by a visible gap.
class _AbstractPainter extends CustomPainter {
  final List<TaskModel> tasks;
  final double animT;
  final DateTime now;
  final String wakeTime;
  final String sleepTime;
  final bool isListening;
  final int tabIndex; // 0=Today, 1=Week, 2=Month, 3=Year

  _AbstractPainter({
    required this.tasks,
    required this.animT,
    required this.now,
    required this.wakeTime,
    required this.sleepTime,
    this.isListening = false,
    this.tabIndex = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);

    final moonR = size.width * 0.44; // moon close to ring, small visible gap
    final ringR = size.width * 0.48; // thin ring just outside, with gap

    // ── Progress fraction based on tab ───────────────────────────────────────
    late final double dayFrac;
    late final int periodStart;
    late final int periodDuration;

    bool isNight = false;

    if (tabIndex == 0) {
      // Today: time-of-day progress
      final wakeMin  = _parseTimeMinutes(wakeTime);
      final sleepMin = _parseTimeMinutes(sleepTime);
      int dayDur = sleepMin - wakeMin;
      if (dayDur <= 0) dayDur += 1440;
      final nowMin = now.hour * 60 + now.minute;

      // Detect if we're in the sleep window
      bool inSleepWindow;
      if (sleepMin > wakeMin) {
        inSleepWindow = nowMin >= sleepMin || nowMin < wakeMin;
      } else {
        inSleepWindow = nowMin >= sleepMin && nowMin < wakeMin;
      }

      if (inSleepWindow) {
        // Night mode: moon reverses, lit area grows left→right
        isNight = true;
        int nightDur = 1440 - dayDur; // total sleep minutes
        if (nightDur <= 0) nightDur = 1440;
        int nightElapsed;
        if (nowMin >= sleepMin) {
          nightElapsed = nowMin - sleepMin;
        } else {
          nightElapsed = (1440 - sleepMin) + nowMin;
        }
        // nightFrac: 0 at sleep time → 1 at wake time
        final nightFrac = (nightElapsed / nightDur).clamp(0.0, 1.0);
        // Invert: k=1 at start (fully dark), k=0 at end (fully lit)
        dayFrac = 1.0 - nightFrac;
      } else {
        int elapsed = nowMin - wakeMin;
        if (elapsed < 0) elapsed += 1440;
        dayFrac = (elapsed / dayDur).clamp(0.0, 1.0);
      }
      periodStart = wakeMin;
      periodDuration = dayDur;
    } else if (tabIndex == 1) {
      // Week: day-of-week progress (Mon=1 .. Sun=7)
      final dayOfWeek = now.weekday; // 1=Mon
      final hourFrac = (now.hour * 60 + now.minute) / 1440.0;
      dayFrac = ((dayOfWeek - 1 + hourFrac) / 7.0).clamp(0.0, 1.0);
      periodStart = 0;
      periodDuration = 7;
    } else if (tabIndex == 2) {
      // Month: day-of-month progress
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final hourFrac = (now.hour * 60 + now.minute) / 1440.0;
      dayFrac = ((now.day - 1 + hourFrac) / daysInMonth).clamp(0.0, 1.0);
      periodStart = 0;
      periodDuration = daysInMonth;
    } else {
      // Year: day-of-year progress
      final startOfYear = DateTime(now.year, 1, 1);
      final dayOfYear = now.difference(startOfYear).inDays;
      final totalDays = DateTime(now.year + 1, 1, 1).difference(startOfYear).inDays;
      dayFrac = (dayOfYear / totalDays).clamp(0.0, 1.0);
      periodStart = 0;
      periodDuration = totalDays;
    }

    // ── Outer completion ring ────────────────────────────────────────────────
    _drawCompletionRing(canvas, center, ringR, animT, tasks, isListening: isListening);

    // ── Moon phase circle with task bands inside ────────────────────────────
    _drawMoon(canvas, center, moonR, dayFrac, animT,
        periodStart: periodStart, periodDuration: periodDuration,
        isNight: isNight);
  }

  void _drawMoon(Canvas canvas, Offset center, double r, double dayFrac, double t,
      {required int periodStart, required int periodDuration,
       bool isNight = false}) {
    final breathe = isListening ? (1.0 + 0.018 * sin(t * 2 * pi)) : 1.0;
    final br = r * breathe;
    final cx = center.dx;
    final cy = center.dy;

    // ── Night mode: mirror canvas so lit area grows left→right ─────────────
    if (isNight) {
      canvas.save();
      // Mirror horizontally around the moon center
      canvas.translate(2 * cx, 0);
      canvas.scale(-1, 1);
    }

    // ── 1. Dark base sphere ─────────────────────────────────────────────────
    // Night: deeper blue-black. Day: warm dark.
    final darkColor1 = isNight ? const Color(0xFF0E1220) : const Color(0xFF1E1E2A);
    final darkColor2 = isNight ? const Color(0xFF060810) : const Color(0xFF0A0A12);
    final lightDir = isNight ? 0.15 : -0.15; // light from opposite side at night

    canvas.drawCircle(center, br,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx + br * lightDir, cy - br * 0.15),
          br * 1.2,
          [darkColor1, darkColor2],
          [0.0, 1.0],
        ));

    // ── 2. Lit moon face — 3D sphere shading ────────────────────────────────
    if (dayFrac < 1.0) {
      final litPath = _moonLitPath(center, br, dayFrac);

      // Pure white moon face (matches the outer ring tone).
      final moonFaceBase = Colors.white;
      final highlightColor = Colors.white;

      canvas.drawPath(litPath, Paint()..color = moonFaceBase);

      // 3D sphere shading
      canvas.save();
      canvas.clipPath(litPath);

      // Primary sphere gradient — highlight offset toward light source
      final lightX = isNight ? 0.25 : -0.25;
      canvas.drawCircle(center, br,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx + br * lightX, cy - br * 0.3),
            br * 1.1,
            [
              highlightColor.withOpacity(0.45),
              moonFaceBase.withOpacity(0.0),
            ],
            [0.0, 0.7],
          ));

      // Edge darkening — very subtle curvature hint (keeps moon reading white)
      final edgeShadow = isNight
          ? const Color(0xFF6A7080).withOpacity(0.08)
          : const Color(0xFF8A8680).withOpacity(0.06);
      canvas.drawCircle(center, br,
        Paint()
          ..shader = ui.Gradient.radial(
            center, br,
            [Colors.transparent, Colors.transparent, edgeShadow],
            [0.0, 0.7, 1.0],
          ));

      // Terminator shadow
      final terminatorX = cx + br * cos(dayFrac * pi);
      canvas.drawCircle(Offset(terminatorX, cy), br * 0.6,
        Paint()
          ..color = (isNight ? const Color(0xFF1A2030) : const Color(0xFF2A2A35))
              .withOpacity(0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.3));

      canvas.restore();

      // Specular highlight
      final specX = cx + br * (isNight ? 0.28 : -0.28);
      final specY = cy - br * 0.32;
      canvas.save();
      canvas.clipPath(litPath);
      canvas.drawCircle(Offset(specX, specY), br * 0.18,
        Paint()
          ..color = highlightColor.withOpacity(0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.12));
      canvas.drawCircle(Offset(specX, specY), br * 0.06,
        Paint()
          ..color = highlightColor.withOpacity(0.50)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.04));
      canvas.restore();
    }

    // Restore from night mirror before drawing rim and stripes
    if (isNight) {
      canvas.restore();
    }

    // ── 3. Sphere rim — atmospheric edge glow ───────────────────────────────
    final rimColor = isNight
        ? const Color(0xFF4A6080) // cool blue rim at night
        : AghieriColors.surfaceHigh;
    canvas.drawCircle(center, br,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = (isNight ? const Color(0xFFB0C4DE) : Colors.white).withOpacity(0.08));

    // Inner subtle rim
    final pulse = 0.90 + 0.10 * sin(t * 2 * pi);
    canvas.drawCircle(center, br - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = AghieriColors.textSecondary.withOpacity(0.06 * pulse));

    // ── 4. Task stripes — longitude bands on a 3D sphere ────────────────────
    // Skip during night mode — no tasks while sleeping
    // Tab-aware positioning:
    //   Today: wake/sleep window, time determines position + width
    //   Week:  date positions within 7 days, time determines width
    //   Month: date positions within month, time determines width
    //   Year:  date positions within year, time determines width
    // Sphere projection: x = R·cos(lat)·sin(lon), y = R·sin(lat)
    if (tasks.isNotEmpty && dayFrac < 1.0 && !isNight) {
      final litPath = _moonLitPath(center, br, dayFrac);
      canvas.save();
      canvas.clipPath(litPath); // ONLY visible in the white/lit area

      final wakeMin  = _parseTimeMinutes(wakeTime);
      final sleepMin = _parseTimeMinutes(sleepTime);
      int dayDur = sleepMin - wakeMin;
      if (dayDur <= 0) dayDur += 1440;

      // Period boundaries for multi-tab support
      late final DateTime periodStartDate;
      late final int totalPeriodMinutes;

      if (tabIndex == 0) {
        // Today: period = wake-to-sleep window
        totalPeriodMinutes = dayDur;
        periodStartDate = DateTime(now.year, now.month, now.day);
      } else if (tabIndex == 1) {
        // Week: period = 7 full days starting Monday
        final monday = now.subtract(Duration(days: now.weekday - 1));
        periodStartDate = DateTime(monday.year, monday.month, monday.day);
        totalPeriodMinutes = 7 * 1440;
      } else if (tabIndex == 2) {
        // Month: period = all days in current month
        periodStartDate = DateTime(now.year, now.month, 1);
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        totalPeriodMinutes = daysInMonth * 1440;
      } else {
        // Year: period = all days in current year
        periodStartDate = DateTime(now.year, 1, 1);
        final daysInYear = DateTime(now.year + 1, 1, 1).difference(periodStartDate).inDays;
        totalPeriodMinutes = daysInYear * 1440;
      }

      final unscheduledTasks = tasks.where((t) => t.scheduledTime == null).toList();
      int unschedIdx = 0;
      const curveSteps = 40;

      for (final task in tasks) {
        double sf, ef;

        if (tabIndex == 0) {
          // ── Today tab: position by time within wake/sleep window ──
          if (task.scheduledTime != null) {
            final startMin = _parseTimeMinutes(task.scheduledTime!);
            final endMin = task.scheduledEndTime != null
                ? _parseTimeMinutes(task.scheduledEndTime!)
                : startMin + 60;
            int se = startMin - wakeMin; if (se < 0) se += 1440;
            int ee = endMin - wakeMin;   if (ee < 0) ee += 1440;
            sf = (se / dayDur).clamp(0.0, 1.0);
            ef = (ee / dayDur).clamp(0.0, 1.0);
          } else {
            final n = unscheduledTasks.length;
            final futureStart = dayFrac;
            final futureRange = (1.0 - futureStart).clamp(0.1, 1.0);
            final slotSize = futureRange / (n + 1);
            sf = (futureStart + (unschedIdx + 1) * slotSize - slotSize * 0.3).clamp(0.0, 1.0);
            ef = (futureStart + (unschedIdx + 1) * slotSize + slotSize * 0.3).clamp(0.0, 1.0);
            unschedIdx++;
          }
        } else {
          // ── Week/Month/Year: position by date + time ──
          // Parse task date
          DateTime taskDate;
          if (task.dueDate != null) {
            final parts = task.dueDate!.split('-');
            if (parts.length >= 3) {
              taskDate = DateTime(
                int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
            } else {
              taskDate = now;
            }
          } else {
            taskDate = now; // no date → assume today
          }

          // Task start/end time within the day (minutes)
          final taskStartMin = task.scheduledTime != null
              ? _parseTimeMinutes(task.scheduledTime!)
              : wakeMin; // default to wake time if no start time
          final taskEndMin = task.scheduledEndTime != null
              ? _parseTimeMinutes(task.scheduledEndTime!)
              : taskStartMin + 60;

          // Day offset from period start
          final dayOffset = taskDate.difference(periodStartDate).inDays;

          // Total minutes from period start
          final startFromPeriod = dayOffset * 1440 + taskStartMin;
          final endFromPeriod = dayOffset * 1440 + taskEndMin;

          sf = (startFromPeriod / totalPeriodMinutes).clamp(0.0, 1.0);
          ef = (endFromPeriod / totalPeriodMinutes).clamp(0.0, 1.0);

          // Ensure minimum visible width (at least 0.5% of face for legibility)
          if ((ef - sf) < 0.005) {
            final mid = (sf + ef) / 2;
            sf = (mid - 0.0025).clamp(0.0, 1.0);
            ef = (mid + 0.0025).clamp(0.0, 1.0);
          }
        }

        // Map fraction to longitude: 0 → -π/2 (left), 1 → π/2 (right)
        final phi1 = -pi / 2 + sf * pi;
        final phi2 = -pi / 2 + ef * pi;

        // Build longitude stripe path using spherical projection
        final taskPath = Path();

        // Left edge: north pole → south pole
        for (int i = 0; i <= curveSteps; i++) {
          final lat = pi / 2 - i * pi / curveSteps;
          final x = cx + br * cos(lat) * sin(phi1);
          final y = cy - br * sin(lat);
          if (i == 0) taskPath.moveTo(x, y);
          else taskPath.lineTo(x, y);
        }

        // Right edge: south pole → north pole
        for (int i = curveSteps; i >= 0; i--) {
          final lat = pi / 2 - i * pi / curveSteps;
          final x = cx + br * cos(lat) * sin(phi2);
          final y = cy - br * sin(lat);
          taskPath.lineTo(x, y);
        }
        taskPath.close();

        // ── Focus-style vivid gradient + lava blobs inside stripe ──
        // Multi-day: 0.35 opacity with slow pulse. Active: 0.85. Normal: 0.7.
        final isMulti = task.isMultiDay;
        final isActive = task.isActive;
        double stripeOpacity;
        if (isMulti && !isActive) {
          final pulse = 0.75 + 0.25 * sin(t * 2 * pi / 4.0); // 4s period
          stripeOpacity = 0.35 * pulse;
        } else if (isActive) {
          stripeOpacity = 0.85;
        } else {
          stripeOpacity = 0.70;
        }

        canvas.save();
        canvas.clipPath(taskPath);

        // Derive vivid palette from task color (same as focus screen)
        final baseHsl = HSLColor.fromColor(task.color);
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

        // Animated radial gradient fill (center drifts with animation)
        final stripeBounds = taskPath.getBounds();
        // Apply opacity layer: multi-day 0.35 + pulse, active 0.85, normal 0.70
        canvas.saveLayer(stripeBounds, Paint()..color = Color.fromRGBO(0, 0, 0, stripeOpacity));
        canvas.drawRect(stripeBounds,
          Paint()
            ..shader = RadialGradient(
              center: Alignment(
                0.3 * sin(t * 2 * pi),
                0.3 * cos(t * 2 * pi * 0.7),
              ),
              radius: 1.2,
              colors: [
                palette[0].toColor(),
                palette[1].toColor(),
                palette[2].toColor(),
                palette[3].toColor(),
              ],
              stops: const [0.0, 0.35, 0.65, 1.0],
            ).createShader(stripeBounds));

        // Lava lamp blobs — 3 per stripe (scaled to stripe size)
        final rng = _MoonRng(task.color.value);
        final blobCx = stripeBounds.center.dx;
        final blobCy = stripeBounds.center.dy;
        final blobW = stripeBounds.width;
        final blobH = stripeBounds.height;

        for (int i = 0; i < 3; i++) {
          final paletteColor = palette[(i + 1) % palette.length];
          final phaseOff = rng.at(i * 4 + 2) * 2 * pi;
          final drift = 0.25 + rng.at(i * 4 + 3) * 0.15;

          final bx = blobCx + blobW * drift * sin(t * 2 * pi * 0.4 + phaseOff);
          final by = blobCy + blobH * 0.3 * cos(t * 2 * pi * 0.3 + phaseOff * 0.7);
          final blobR = blobW * (0.5 + rng.at(i * 5) * 0.5);

          final coreColor = paletteColor
              .withSaturation((paletteColor.saturation * 1.4).clamp(0.0, 1.0))
              .withLightness((paletteColor.lightness * 0.9).clamp(0.15, 0.85))
              .toColor();

          // Haze layer
          canvas.drawCircle(Offset(bx, by), blobR * 1.2,
            Paint()
              ..color = coreColor.withOpacity(0.40)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blobW * 0.4));

          // Core
          canvas.drawCircle(Offset(bx, by), blobR * 0.6,
            Paint()
              ..color = coreColor.withOpacity(0.75)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blobW * 0.15));
        }

        // 3D curvature: darken left/right edges of stripe
        canvas.drawRect(stripeBounds,
          Paint()
            ..shader = ui.Gradient.linear(
              stripeBounds.centerLeft,
              stripeBounds.centerRight,
              [
                Colors.black.withOpacity(0.30),
                Colors.transparent,
                Colors.black.withOpacity(0.20),
              ],
              [0.0, 0.45, 1.0],
            ));

        // Specular highlight — small bright spot near top
        canvas.drawCircle(
          Offset(stripeBounds.center.dx - blobW * 0.1, stripeBounds.top + blobH * 0.2),
          blobW * 0.3,
          Paint()
            ..color = Colors.white.withOpacity(0.18)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blobW * 0.2));

        canvas.restore(); // saveLayer (opacity)
        canvas.restore(); // clipPath

        // Edge highlight on left boundary
        final edgePath = Path();
        for (int i = 0; i <= curveSteps; i++) {
          final lat = pi / 2 - i * pi / curveSteps;
          final x = cx + br * cos(lat) * sin(phi1);
          final y = cy - br * sin(lat);
          if (i == 0) edgePath.moveTo(x, y);
          else edgePath.lineTo(x, y);
        }
        canvas.drawPath(edgePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white.withOpacity(0.12)
            ..strokeWidth = 0.6);
      }

      canvas.restore();
    }

    // ── 5. Final 3D sphere overlay — subtle ambient occlusion ──────────────
    // Darkens bottom edge for grounding, adds subtle top highlight
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: br)));
    // Bottom shadow for grounding
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + br * 0.4), width: br * 1.8, height: br * 0.7),
      Paint()
        ..color = Colors.black.withOpacity(0.08)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.2));
    canvas.restore();
  }

  /// Outer ring: single thin stroke with slow ambient light spots.
  /// Simple drawCircle stroke — no clip path, no fills, no way to glitch into a band.
  void _drawCompletionRing(Canvas canvas, Offset center, double r,
      double animT, List<TaskModel> tasks, {bool isListening = false}) {
    const ringWidth = 3.0;

    // ── The ring itself — thin stroke, soft white ─────────────────────────
    canvas.drawCircle(center, r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = Colors.white.withOpacity(0.35));

    // ── 3 slow orbiting light spots for subtle ambient animation ──────────
    const slowOrbits = 3;
    for (int i = 0; i < slowOrbits; i++) {
      final baseAngle = i * 2 * pi / slowOrbits;
      final angle = baseAngle + animT * 2 * pi * 0.04;
      final bx = center.dx + r * cos(angle);
      final by = center.dy + r * sin(angle);
      final breathe = 0.85 + 0.15 * sin(animT * 2 * pi * 0.15 + i * 2.1);
      final spotR = 4.0 * breathe;

      canvas.drawCircle(Offset(bx, by), spotR,
        Paint()
          ..color = Colors.white.withOpacity(0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, spotR * 1.2));
    }

    // ── Listening state: green pulse overlay ──────────────────────────────
    if (isListening) {
      final listenPulse = 0.3 + 0.7 * ((sin(animT * 2 * pi * 4) + 1) / 2);
      canvas.drawCircle(center, r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth + 3
          ..color = const Color(0xFF4ADE80).withOpacity(0.25 * listenPulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * listenPulse),
      );
    }
  }

  /// Build the lit (white) region path for a waning moon.
  /// k=0 → full circle lit. k=1 → nothing lit.
  /// Shadow grows from the LEFT side — right crescent is the last thing remaining.
  Path _moonLitPath(Offset center, double r, double k) {
    if (k <= 0) {
      return Path()..addOval(Rect.fromCircle(center: center, radius: r));
    }
    if (k >= 1) return Path();

    // Terminator x-offset from center:
    //   k=0   → lx=+r  (terminator all the way right = full circle lit)
    //   k=0.5 → lx=0   (terminator at center = right half lit)
    //   k=1   → lx=-r  (terminator all the way left = empty)
    final lx = r * cos(k * pi);

    final path = Path();
    path.moveTo(center.dx, center.dy - r); // Top

    // Right semicircle (always lit): CW from top → right → bottom
    path.arcTo(
      Rect.fromCircle(center: center, radius: r),
      -pi / 2, // top
      pi,      // +π CW sweeps through 0 (right) to π/2 (bottom)
      false,
    );

    // Terminator from bottom → top
    if (lx.abs() < 0.5) {
      // Near half-moon: straight vertical line
      path.lineTo(center.dx, center.dy - r);
    } else {
      final ellipseRect = Rect.fromCenter(
        center: center,
        width: 2 * lx.abs(),
        height: 2 * r,
      );
      if (lx > 0) {
        // Gibbous (early day, >half lit): terminator left of center
        // Add left area → CW from bottom through left (π) to top
        path.arcTo(ellipseRect, pi / 2, pi, false);
      } else {
        // Crescent (late day, <half lit): terminator right of center
        // Right sliver only → CCW from bottom through right (0) to top
        path.arcTo(ellipseRect, pi / 2, -pi, false);
      }
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_AbstractPainter old) =>
      old.animT != animT ||
      old.now.minute != now.minute ||
      old.tasks != tasks ||
      old.tabIndex != tabIndex;
}

// ── Deterministic RNG for moon blob animation ──────────────────────────────
class _MoonRng {
  final int seed;
  const _MoonRng(this.seed);

  double at(int i) {
    int s = (seed ^ (i * 2654435761)) & 0x7FFFFFFF;
    s = (s * 1664525 + 1013904223) & 0x7FFFFFFF;
    return s / 0x7FFFFFFF;
  }
}

// ── Beach Ball Painter ───────────────────────────────────────────────────────
/// Draws a circle divided into equal wedges — one per task — colored by task color.
/// Colors meet at top and bottom poles like a beach ball.
/// Each wedge runs from top pole to bottom pole.
class _BeachBallPainter extends CustomPainter {
  final List<TaskModel> tasks;
  final double animT;

  _BeachBallPainter({required this.tasks, required this.animT});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final r = size.width * 0.44;

    // Background dark circle
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF16161F));

    // Subtle rim
    canvas.drawCircle(center, r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = AghieriColors.surfaceHigh.withOpacity(0.5));

    if (tasks.isEmpty) {
      // Empty dim circle
      canvas.drawCircle(center, r * 0.95,
        Paint()..color = AghieriColors.surfaceHigh.withOpacity(0.3));
      return;
    }

    // Clip to circle
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));

    final n = tasks.length;
    final sliceAngle = 2 * pi / n;

    for (int i = 0; i < n; i++) {
      final task = tasks[i];
      // Each slice starts from top (−π/2) going clockwise
      final startAngle = -pi / 2 + i * sliceAngle;

      final path = Path();
      path.moveTo(cx, cy); // center
      path.lineTo(
        cx + r * 1.1 * cos(startAngle),
        cy + r * 1.1 * sin(startAngle),
      );
      path.arcTo(
        Rect.fromCircle(center: center, radius: r * 1.1),
        startAngle,
        sliceAngle,
        false,
      );
      path.lineTo(cx, cy);
      path.close();

      // Fill with task color
      canvas.drawPath(path,
        Paint()..color = task.color.withOpacity(task.isComplete ? 0.85 : 0.55));

      // Soft inner glow for depth
      canvas.drawPath(path,
        Paint()
          ..color = task.color.withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 12));
    }

    // Draw subtle separator lines between wedges
    for (int i = 0; i < n; i++) {
      final angle = -pi / 2 + i * sliceAngle;
      canvas.drawLine(
        center,
        Offset(cx + r * cos(angle), cy + r * sin(angle)),
        Paint()
          ..color = AghieriColors.bg.withOpacity(0.4)
          ..strokeWidth = 1.2,
      );
    }

    canvas.restore();

    // Outer completion ring
    _drawBeachBallRing(canvas, center, r * 1.06, tasks);

    // Subtle breathing pulse on the rim
    final breathe = 0.90 + 0.10 * sin(animT * 2 * pi);
    canvas.drawCircle(center, r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AghieriColors.textSecondary.withOpacity(0.15 * breathe));
  }

  void _drawBeachBallRing(Canvas canvas, Offset center, double r, List<TaskModel> tasks) {
    // Dim base ring
    canvas.drawCircle(center, r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = AghieriColors.surfaceHigh);

    final total = tasks.length;
    final completed = tasks.where((t) => t.isComplete).length;
    if (total == 0 || completed == 0) return;

    final frac = completed / total;
    final sweep = frac * 2 * pi;
    final ringColor = _blendTaskColors(tasks.where((t) => t.isComplete).toList());
    final rect = Rect.fromCircle(center: center, radius: r);

    // Bloom
    canvas.drawArc(rect, -pi / 2, sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = ringColor.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    // Crisp arc
    canvas.drawArc(rect, -pi / 2, sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = ringColor.withOpacity(0.75));
  }

  @override
  bool shouldRepaint(_BeachBallPainter old) =>
      old.animT != animT || old.tasks != tasks;
}
