import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Calm-tech ambient background. A reusable, quieter sibling of the onboarding
/// Aurora — designed to sit behind any screen and make it feel inhabited
/// without competing for attention. Weiser & Brown (1996): information at the
/// periphery, never at the center.
///
/// Three intensity profiles:
///   • [AmbientIntensity.hush]  — barely-there. Use behind dense content (terms,
///                                settings, reading surfaces).
///   • [AmbientIntensity.calm]  — default. Use behind primary screens.
///   • [AmbientIntensity.awake] — onboarding-grade. Use only on entry surfaces.
///
/// Render once high in the tree and stack content on top.
enum AmbientIntensity { hush, calm, awake }

class AmbientBreathBackground extends StatefulWidget {
  final Widget child;
  final AmbientIntensity intensity;

  const AmbientBreathBackground({
    super.key,
    required this.child,
    this.intensity = AmbientIntensity.calm,
  });

  @override
  State<AmbientBreathBackground> createState() =>
      _AmbientBreathBackgroundState();
}

class _AmbientBreathBackgroundState extends State<AmbientBreathBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 38),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  double get _opacityScale => switch (widget.intensity) {
        AmbientIntensity.hush  => 0.35,
        AmbientIntensity.calm  => 0.55,
        AmbientIntensity.awake => 1.0,
      };

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: AghieriColors.bg),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (_, __) => CustomPaint(
              painter: _AmbientBreathPainter(
                t: _drift.value,
                opacityScale: _opacityScale,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AmbientBreathPainter extends CustomPainter {
  final double t;
  final double opacityScale;

  const _AmbientBreathPainter({required this.t, required this.opacityScale});

  // Quieter palette than onboarding aurora — three drifting fields, larger
  // and more diffuse so the background reads as atmospheric, not decorative.
  static const _blobs = [
    _Blob(0.18, 0.22, 0.07, 0.06, 0.0, 1.6, 340, Color(0xFFA0D8EF), 0.18),
    _Blob(0.78, 0.34, 0.06, 0.08, 2.3, 0.4, 360, Color(0xFFCD79DD), 0.14),
    _Blob(0.50, 0.82, 0.08, 0.05, 1.1, 2.8, 380, Color(0xFF96C8A2), 0.15),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in _blobs) {
      final dx = b.ampX * sin(t * 2 * pi * 0.62 + b.phaseX);
      final dy = b.ampY * sin(t * 2 * pi * 0.48 + b.phaseY);
      final cx = (b.baseX + dx) * size.width;
      final cy = (b.baseY + dy) * size.height;
      final breathe = 0.85 + 0.15 * sin(t * 2 * pi * 0.9 + b.phaseX * 0.5);

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            b.color.withOpacity(b.opacity * breathe * opacityScale),
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
  bool shouldRepaint(_AmbientBreathPainter old) => old.t != t;
}

class _Blob {
  final double baseX, baseY, ampX, ampY, phaseX, phaseY, radius, opacity;
  final Color color;
  const _Blob(this.baseX, this.baseY, this.ampX, this.ampY, this.phaseX,
      this.phaseY, this.radius, this.color, this.opacity);
}

/// A surface that breathes. Wrap any content panel to give it a faint,
/// continuous scale pulse (1.000 → 1.006 → 1.000 over ~5s) and a soft
/// rim glow that rises and falls. Calm-tech: never demands attention,
/// only signals "this thing is alive."
class BreathingSurface extends StatefulWidget {
  final Widget child;
  final Color? glowColor;
  final double maxScale;

  const BreathingSurface({
    super.key,
    required this.child,
    this.glowColor,
    this.maxScale = 1.006,
  });

  @override
  State<BreathingSurface> createState() => _BreathingSurfaceState();
}

class _BreathingSurfaceState extends State<BreathingSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.glowColor ?? AghieriColors.ledIdle;
    return AnimatedBuilder(
      animation: _breath,
      builder: (_, child) {
        final curved = AghieriMotion.breath.transform(_breath.value);
        final scale = 1.0 + (widget.maxScale - 1.0) * curved;
        final glowOpacity = 0.04 + 0.06 * curved;
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: glow.withOpacity(glowOpacity),
                  blurRadius: 28,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Hand-drawn check mark that draws on rather than snapping in. Replaces the
/// instant Icon(Icons.check) tell that reads as default-Material.
class AnimatedTickMark extends StatefulWidget {
  final bool checked;
  final Color color;
  final double size;

  const AnimatedTickMark({
    super.key,
    required this.checked,
    required this.color,
    this.size = 16,
  });

  @override
  State<AnimatedTickMark> createState() => _AnimatedTickMarkState();
}

class _AnimatedTickMarkState extends State<AnimatedTickMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: AghieriMotion.ease,
      value: widget.checked ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(AnimatedTickMark old) {
    super.didUpdateWidget(old);
    if (widget.checked != old.checked) {
      widget.checked ? _draw.forward() : _draw.reverse();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _draw,
      builder: (_, __) {
        final p = AghieriMotion.notice.transform(_draw.value);
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _TickPainter(progress: p, color: widget.color),
        );
      },
    );
  }
}

class _TickPainter extends CustomPainter {
  final double progress;
  final Color color;
  _TickPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final p1 = Offset(size.width * 0.20, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.74);
    final p3 = Offset(size.width * 0.82, size.height * 0.30);

    // Draw stroke in two segments; second segment grows after first completes.
    final firstLen = 0.42; // proportion of the draw to the elbow
    final path = Path()..moveTo(p1.dx, p1.dy);

    if (progress <= firstLen) {
      final f = progress / firstLen;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * f, p1.dy + (p2.dy - p1.dy) * f);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final f = (progress - firstLen) / (1.0 - firstLen);
      path.lineTo(p2.dx + (p3.dx - p2.dx) * f, p2.dy + (p3.dy - p2.dy) * f);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.progress != progress || old.color != color;
}
