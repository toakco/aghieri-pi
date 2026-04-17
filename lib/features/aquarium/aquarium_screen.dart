import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class AquariumScreen extends StatefulWidget {
  const AquariumScreen({super.key});

  @override
  State<AquariumScreen> createState() => _AquariumScreenState();
}

class _AquariumScreenState extends State<AquariumScreen>
    with TickerProviderStateMixin {
  late AnimationController _masterCtrl; // drives everything
  late AnimationController _entryCtrl;  // fade-in on mount
  late List<_FishData> _fish;
  String? _tappedName;

  static const _fishNames = [
    'Dante', 'Beatrice', 'Virgil', 'Lucia', 'Marco', 'Francesca',
  ];

  static const _fishColors = [
    Color(0xFF6AAEE8),
    Color(0xFFE8C96A),
    Color(0xFF8AE86A),
    Color(0xFFC46AE8),
    Color(0xFF6AE8D4),
    Color(0xFFE8856A),
  ];

  @override
  void initState() {
    super.initState();

    _masterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(); // always runs, fish read elapsed time

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    final rng = Random(77);
    _fish = List.generate(_fishNames.length, (i) => _FishData(
      name: _fishNames[i],
      color: _fishColors[i],
      // Each fish starts at a random horizontal position
      startOffset: rng.nextDouble(),
      // Speed: 0.03–0.06 world-units/sec (world = 0..1)
      speed: 0.025 + rng.nextDouble() * 0.025,
      // Vertical center: 15%–65% down
      yCenter: 0.15 + rng.nextDouble() * 0.50,
      // Vertical amplitude: 2–5% of screen height
      yAmplitude: 0.02 + rng.nextDouble() * 0.03,
      // Vertical frequency
      yFreq: 0.6 + rng.nextDouble() * 0.6,
      // Body size: 5–8% of screen width
      bodyLen: 0.055 + rng.nextDouble() * 0.025,
    ));
  }

  @override
  void dispose() {
    _masterCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF04090F),
      body: FadeTransition(
        opacity: _entryCtrl,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _tappedName = null),
          child: Stack(
            children: [
              // ── Canvas ──────────────────────────────────────────────────────
              AnimatedBuilder(
                animation: _masterCtrl,
                builder: (_, __) {
                  // elapsed time in seconds (wraps at 3600s to avoid float drift)
                  final t = (DateTime.now().millisecondsSinceEpoch % 3600000) / 1000.0;
                  return CustomPaint(
                    size: size,
                    painter: _AquariumPainter(t: t, fish: _fish),
                  );
                },
              ),

              // ── Fish tap zones ───────────────────────────────────────────────
              AnimatedBuilder(
                animation: _masterCtrl,
                builder: (_, __) {
                  final t = (DateTime.now().millisecondsSinceEpoch % 3600000) / 1000.0;
                  return Stack(
                    children: _fish.map((f) {
                      final pos = f.position(t, size);
                      return Positioned(
                        left: pos.dx - 36,
                        top: pos.dy - 20,
                        child: GestureDetector(
                          onTap: () => setState(() => _tappedName = f.name),
                          child: const SizedBox(width: 72, height: 40),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              // ── Name tooltip ─────────────────────────────────────────────────
              if (_tappedName != null)
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    builder: (_, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1520).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: AghieriColors.accent.withOpacity(0.4),
                            width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: AghieriColors.accent.withOpacity(0.12),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Text(
                        _tappedName!,
                        style: AghieriTextStyles.body(
                            size: 16, color: AghieriColors.textPrimary),
                      ),
                    ),
                  ),
                ),

              // ── Close ────────────────────────────────────────────────────────
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 22),
                    onPressed: () => context.pop(),
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

// ── Fish data model ───────────────────────────────────────────────────────────

class _FishData {
  final String name;
  final Color color;
  final double startOffset; // 0..1 horizontal starting position
  final double speed;       // world units/sec
  final double yCenter;     // 0..1 vertical center
  final double yAmplitude;  // 0..1 vertical sway amplitude
  final double yFreq;       // sway cycles per second
  final double bodyLen;     // 0..1 relative body length

  const _FishData({
    required this.name,
    required this.color,
    required this.startOffset,
    required this.speed,
    required this.yCenter,
    required this.yAmplitude,
    required this.yFreq,
    required this.bodyLen,
  });

  // Returns screen position given elapsed time t (seconds) and screen size.
  // Fish swim right→left, wrapping seamlessly.
  Offset position(double t, Size size) {
    final x = ((startOffset + t * speed) % 1.0) * size.width;
    final y = yCenter * size.height
        + sin(t * yFreq * 2 * pi) * yAmplitude * size.height;
    return Offset(x, y);
  }

  // True if currently moving right (for body flip)
  bool facingRight(double t) {
    // Derivative of x w.r.t. t is always positive (wraps 0→1)
    // They always swim in one direction, so flip based on startOffset parity
    return startOffset < 0.5;
  }
}

// ── Aquarium painter ──────────────────────────────────────────────────────────

class _AquariumPainter extends CustomPainter {
  final double t;
  final List<_FishData> fish;

  _AquariumPainter({required this.t, required this.fish});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintCaustics(canvas, size);
    _paintPlants(canvas, size);
    _paintFish(canvas, size);
    _paintBubbles(canvas, size);
    _paintSubstrate(canvas, size);
    _paintWaterSurface(canvas, size);
  }

  void _paintBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF071525),
          Color(0xFF081B10),
          Color(0xFF050D08),
        ],
        stops: [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintCaustics(Canvas canvas, Size size) {
    // Soft blurry caustic patches — slow drift
    final rng = Random(31);
    for (int i = 0; i < 8; i++) {
      final bx = rng.nextDouble() * size.width;
      final by = rng.nextDouble() * size.height * 0.55;
      final drift = sin(t * 0.3 + i * 1.1) * 22;
      final r = 16.0 + rng.nextDouble() * 28;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(bx + drift, by + drift * 0.4),
          width: r * 2.2,
          height: r * 0.9,
        ),
        Paint()
          ..color = const Color(0xFF8FDDF0)
              .withOpacity(0.025 + 0.015 * sin(t * 0.5 + i))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
  }

  void _paintPlants(Canvas canvas, Size size) {
    // Substrate line
    final substrateY = size.height * 0.86;

    // Plant clusters: x-position, height-factor, color variant
    final clusters = [
      (0.06, 0.30, const Color(0xFF1E5A30)),
      (0.14, 0.22, const Color(0xFF2A5C3A)),
      (0.78, 0.28, const Color(0xFF1A4A24)),
      (0.86, 0.20, const Color(0xFF2D5535)),
      (0.50, 0.18, const Color(0xFF234C2D)),
      (0.42, 0.14, const Color(0xFF1C3E26)),
    ];

    for (final (xFrac, hFrac, baseColor) in clusters) {
      final px = xFrac * size.width;
      final ph = hFrac * size.height;

      // Draw 3 stems per cluster with slight x spread
      for (int s = 0; s < 3; s++) {
        final ox = (s - 1) * 7.0;
        // Sway: slow sine, each stem slightly out of phase
        final sway = sin(t * 0.9 + xFrac * 6 + s * 0.8) * 9;
        final ctrl1x = px + ox + sway;
        final ctrl1y = substrateY - ph * 0.45;
        final endX   = px + ox + sway * 1.3;
        final endY   = substrateY - ph;

        final path = Path()
          ..moveTo(px + ox, substrateY)
          ..quadraticBezierTo(ctrl1x, ctrl1y, endX, endY);

        // Slight color variation per stem
        final c = Color.lerp(baseColor, baseColor.withOpacity(0.6), s * 0.25)!;
        canvas.drawPath(
          path,
          Paint()
            ..color = c.withOpacity(0.80)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.8 - s * 0.6
            ..strokeCap = StrokeCap.round,
        );

        // Leaf tip — small oval at stem end
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(endX, endY),
            width: 6 + s.toDouble(),
            height: 3.0,
          ),
          Paint()..color = c.withOpacity(0.60),
        );
      }
    }
  }

  void _paintFish(Canvas canvas, Size size) {
    for (final f in fish) {
      final pos  = f.position(t, size);
      final bLen = f.bodyLen * size.width;
      final bH   = bLen * 0.42;

      // Tail wag: sinusoidal, frequency linked to swim speed
      final wagFreq = f.yFreq * 2.5;
      final wag = sin(t * wagFreq * 2 * pi) * 0.18; // radians

      // Face direction: swimming right → x increases → flip canvas
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      // Fish always appear to move left (decreasing x after wrap looks weird),
      // so we flip horizontally so they always face the direction of travel.
      // Since they travel left→right in world coords but we want them to appear
      // to swim organically, alternate direction per fish.
      final flip = f.startOffset < 0.5 ? 1.0 : -1.0;
      canvas.scale(flip, 1.0);

      _drawFishBody(canvas, bLen, bH, wag, f.color);
      canvas.restore();
    }
  }

  void _drawFishBody(Canvas canvas, double bLen, double bH,
      double wag, Color color) {
    // Tail — wagging, drawn behind body
    final tailW = bLen * 0.28;
    final tailH = bH * 0.9;
    final tailX = -bLen / 2 - tailW * 0.3;

    canvas.save();
    canvas.translate(tailX + tailW * 0.3, 0);
    canvas.rotate(wag);
    canvas.translate(-(tailX + tailW * 0.3), 0);

    final tail = Path()
      ..moveTo(tailX + tailW * 0.4, 0)
      ..lineTo(tailX, -tailH / 2)
      ..lineTo(tailX - tailW * 0.1, 0)
      ..lineTo(tailX, tailH / 2)
      ..close();
    canvas.drawPath(tail, Paint()..color = color.withOpacity(0.55));
    canvas.restore();

    // Body — tapered oval
    final bodyRect = Rect.fromCenter(
        center: Offset(bLen * 0.04, 0), width: bLen, height: bH);
    final bodyPath = Path()
      ..moveTo(-bLen / 2, 0)
      ..cubicTo(
        -bLen * 0.3, -bH / 2,
        bLen * 0.25, -bH / 2,
        bLen / 2, 0,
      )
      ..cubicTo(
        bLen * 0.25, bH / 2,
        -bLen * 0.3, bH / 2,
        -bLen / 2, 0,
      );

    // Body gradient (head brighter, tail dimmer)
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            color.withOpacity(0.90),
            color.withOpacity(0.60),
          ],
        ).createShader(bodyRect),
    );

    // Lateral line — subtle highlight along center
    canvas.drawPath(
      Path()
        ..moveTo(bLen * 0.3, -bH * 0.06)
        ..cubicTo(
          0, -bH * 0.08,
          -bLen * 0.2, -bH * 0.05,
          -bLen * 0.38, 0,
        ),
      Paint()
        ..color = Colors.white.withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Dorsal fin
    final dorsalPath = Path()
      ..moveTo(-bLen * 0.05, -bH / 2)
      ..cubicTo(
        bLen * 0.05, -bH * 0.85,
        bLen * 0.20, -bH * 0.85,
        bLen * 0.28, -bH / 2,
      );
    canvas.drawPath(
      dorsalPath,
      Paint()
        ..color = color.withOpacity(0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // Eye — white sclera + dark iris
    final eyeX = bLen * 0.26;
    final eyeR = bH * 0.14;
    canvas.drawCircle(Offset(eyeX, -bH * 0.10), eyeR,
        Paint()..color = Colors.white.withOpacity(0.88));
    canvas.drawCircle(Offset(eyeX + eyeR * 0.2, -bH * 0.10), eyeR * 0.55,
        Paint()..color = const Color(0xFF1A1A1A));
    // Catchlight
    canvas.drawCircle(Offset(eyeX + eyeR * 0.05, -bH * 0.17), eyeR * 0.18,
        Paint()..color = Colors.white.withOpacity(0.70));
  }

  void _paintBubbles(Canvas canvas, Size size) {
    final rng = Random(19);
    for (int i = 0; i < 10; i++) {
      final bx    = rng.nextDouble() * size.width;
      // Each bubble has its own slow rise speed
      final speed = 0.05 + rng.nextDouble() * 0.08; // world/sec
      final prog  = ((t * speed + rng.nextDouble()) % 1.0);
      final by    = size.height * 0.88 - prog * size.height * 0.80;
      // Slight horizontal drift
      final drift = sin(t * 1.2 + i * 0.9) * 6;
      final r     = 1.5 + rng.nextDouble() * 3.5;

      canvas.drawCircle(
        Offset(bx + drift, by),
        r,
        Paint()
          ..color = Colors.white.withOpacity(0.12 * (1 - prog * 0.5))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7,
      );

      // Specular on bubble
      canvas.drawArc(
        Rect.fromCircle(center: Offset(bx + drift - r * 0.2, by - r * 0.2), radius: r * 0.55),
        pi * 1.1, pi * 0.55, false,
        Paint()
          ..color = Colors.white.withOpacity(0.08 * (1 - prog * 0.5))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  void _paintSubstrate(Canvas canvas, Size size) {
    final y = size.height * 0.86;

    // Sand — gradient layer
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, size.height - y),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF2A1E12), Color(0xFF160F08)],
        ).createShader(Rect.fromLTWH(0, y, size.width, size.height - y)),
    );

    // Pebbles — random sizes, subtle color variation
    final rng = Random(41);
    for (int i = 0; i < 45; i++) {
      final px = rng.nextDouble() * size.width;
      final py = y + 3 + rng.nextDouble() * 14;
      final pw = 3.0 + rng.nextDouble() * 6;
      final ph = pw * (0.5 + rng.nextDouble() * 0.4);
      final brightness = rng.nextDouble();
      final pebbleColor = Color.lerp(
          const Color(0xFF35280E), const Color(0xFF5A4820), brightness)!;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(px, py), width: pw, height: ph),
        Paint()..color = pebbleColor,
      );
      // Specular sheen on each pebble
      canvas.drawArc(
        Rect.fromCenter(center: Offset(px - pw * 0.1, py - ph * 0.2),
            width: pw * 0.6, height: ph * 0.5),
        pi * 1.2, pi * 0.5, false,
        Paint()
          ..color = Colors.white.withOpacity(0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }
  }

  void _paintWaterSurface(Canvas canvas, Size size) {
    // Subtle shimmer line at the very top — optional atmospheric touch
    final shimmer = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          const Color(0xFF8FDDF0).withOpacity(0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2), shimmer);
  }

  @override
  bool shouldRepaint(_AquariumPainter old) => true;
}
