import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/voice_service.dart';

/// VoiceStateRing — animated outer ring overlay that reflects the current
/// voice pipeline state: idle (subtle white), listening (green lava lamp),
/// thinking (amber slow rotation), responding (blue flowing).
///
/// Place this as an overlay around the moon clock at +20px outset.
class VoiceStateRing extends StatefulWidget {
  final double diameter;
  final double strokeWidth;

  const VoiceStateRing({
    super.key,
    required this.diameter,
    this.strokeWidth = 4.0,
  });

  @override
  State<VoiceStateRing> createState() => _VoiceStateRingState();
}

class _VoiceStateRingState extends State<VoiceStateRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  StreamSubscription<VoiceState>? _stateSub;
  VoiceState _state = VoiceState.idle;

  // EMA-smoothed amplitude (0..1) — updated when Web Audio AnalyserNode is wired
  final double _amplitude = 0.0;

  // Colors per state
  static const _colors = {
    VoiceState.idle: Color(0x40FFFFFF),
    VoiceState.listening: Color(0xFF7BC97B),
    VoiceState.thinking: Color(0xFFE8B86D),
    VoiceState.responding: Color(0xFF6DA8E8),
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _stateSub = VoiceService.instance.voiceStateStream.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.diameter, widget.diameter),
          painter: _VoiceRingPainter(
            state: _state,
            t: _controller.value,
            amplitude: _amplitude,
            strokeWidth: widget.strokeWidth,
            color: _colors[_state] ?? const Color(0x40FFFFFF),
          ),
        );
      },
    );
  }
}

class _VoiceRingPainter extends CustomPainter {
  final VoiceState state;
  final double t; // 0..1, loops every 4s
  final double amplitude;
  final double strokeWidth;
  final Color color;

  _VoiceRingPainter({
    required this.state,
    required this.t,
    required this.amplitude,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    switch (state) {
      case VoiceState.idle:
        _drawIdle(canvas, center, radius);
        break;
      case VoiceState.listening:
        _drawListening(canvas, center, radius);
        break;
      case VoiceState.thinking:
        _drawThinking(canvas, center, radius);
        break;
      case VoiceState.responding:
        _drawResponding(canvas, center, radius);
        break;
    }
  }

  void _drawIdle(Canvas canvas, Offset center, double radius) {
    // Subtle white ring with slow blob undulation
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    final path = Path();
    const segments = 120;
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * pi;
      final wobble = sin(angle * 3 + t * 2 * pi) * 0.8 +
          sin(angle * 5 - t * 2 * pi * 0.7) * 0.4;
      final r = radius + wobble;
      final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawListening(Canvas canvas, Offset center, double radius) {
    // Green flowing lava lamp — amplitude-reactive
    final amp = 2.0 + amplitude * 6.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1.0
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final path = Path();
    const segments = 120;
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * pi;
      final wobble = sin(angle * 4 + t * 2 * pi * 1.2) * amp +
          sin(angle * 7 - t * 2 * pi * 0.8) * amp * 0.5 +
          sin(angle * 2 + t * 2 * pi * 2.0) * amp * 0.3;
      final r = radius + wobble;
      final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawThinking(Canvas canvas, Offset center, double radius) {
    // Amber slow rotation with fixed gentle wave
    final rotOffset = t * 2 * pi;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final path = Path();
    const segments = 120;
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * pi + rotOffset;
      final wobble = sin(angle * 3) * 1.5 + sin(angle * 6) * 0.8;
      final r = radius + wobble;
      final drawAngle = (i / segments) * 2 * pi;
      final p = Offset(
          center.dx + r * cos(drawAngle), center.dy + r * sin(drawAngle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawResponding(Canvas canvas, Offset center, double radius) {
    // Blue flowing — similar to listening but different frequency
    final amp = 2.0 + amplitude * 5.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 0.5
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path();
    const segments = 120;
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2 * pi;
      final wobble = sin(angle * 3 + t * 2 * pi * 0.6) * amp +
          sin(angle * 5 + t * 2 * pi * 1.5) * amp * 0.6 +
          cos(angle * 8 - t * 2 * pi * 0.9) * amp * 0.3;
      final r = radius + wobble;
      final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_VoiceRingPainter old) =>
      old.state != state || old.t != t || old.amplitude != amplitude;
}
