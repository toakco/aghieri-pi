import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/voice_service.dart';

/// Floating voice button — tap to speak.
/// Three staggered expanding rings while listening; smooth ease-in-out.
class VoiceButton extends StatefulWidget {
  final void Function(String transcript) onTranscript;
  final double size;

  const VoiceButton({super.key, required this.onTranscript, this.size = 64});

  @override
  State<VoiceButton> createState() => VoiceButtonState();
}

class VoiceButtonState extends State<VoiceButton>
    with TickerProviderStateMixin {
  late AnimationController _ring1;
  late AnimationController _ring2;
  late AnimationController _ring3;
  late AnimationController _pressCrl;
  bool _listening = false;

  @override
  void initState() {
    super.initState();

    // Three rings, staggered by 600ms each
    _ring1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _ring2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _ring3 = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));

    // Button scale on press
    _pressCrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.93,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ring1.dispose();
    _ring2.dispose();
    _ring3.dispose();
    _pressCrl.dispose();
    super.dispose();
  }

  void _startRings() {
    _ring1.repeat();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _ring2.repeat();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _ring3.repeat();
    });
  }

  void _stopRings() {
    _ring1.stop(); _ring1.value = 0;
    _ring2.stop(); _ring2.value = 0;
    _ring3.stop(); _ring3.value = 0;
  }

  /// Called externally (e.g. wake word detected) to start listening.
  void trigger() => _toggle();

  Future<void> _toggle() async {
    if (_listening) return;

    _pressCrl.reverse().then((_) => _pressCrl.forward());
    setState(() => _listening = true);
    _startRings();

    final transcript = await VoiceService.instance.listen(onInterim: (_) {});

    if (mounted) {
      setState(() => _listening = false);
      _stopRings();
    }
    if (transcript.isNotEmpty) {
      widget.onTranscript(transcript);
      await VoiceService.instance.sendCommand(transcript);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _listening ? null : _toggle,
      child: ScaleTransition(
        scale: _pressCrl,
        child: SizedBox(
          width: widget.size + 56,
          height: widget.size + 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Rings (render back-to-front so 1 is outermost)
              if (_listening) ...[
                _RippleRing(controller: _ring3, baseSize: widget.size, color: AghieriColors.accent, maxExtra: 40),
                _RippleRing(controller: _ring2, baseSize: widget.size, color: AghieriColors.accent, maxExtra: 28),
                _RippleRing(controller: _ring1, baseSize: widget.size, color: AghieriColors.accent, maxExtra: 16),
              ],

              // Core button
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? AghieriColors.accent : AghieriColors.surface,
                  boxShadow: _listening
                      ? [
                          BoxShadow(
                            color: AghieriColors.accent.withOpacity(0.5),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: AghieriColors.accent.withOpacity(0.2),
                            blurRadius: 50,
                            spreadRadius: 6,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                    child: child,
                  ),
                  child: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    key: ValueKey(_listening),
                    color: _listening ? AghieriColors.bg : AghieriColors.textPrimary,
                    size: widget.size * 0.40,
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

// ── Single expanding ripple ring ──────────────────────────────────────────────

class _RippleRing extends StatelessWidget {
  final AnimationController controller;
  final double baseSize;
  final Color color;
  final double maxExtra;

  const _RippleRing({
    required this.controller,
    required this.baseSize,
    required this.color,
    required this.maxExtra,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Ease-out expansion, ease-in fade — feels natural like a water drop
        final t = CurvedAnimation(
          parent: controller,
          curve: Curves.easeOut,
        ).value;
        final fadeT = CurvedAnimation(
          parent: controller,
          curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
        ).value;
        final diameter = baseSize + maxExtra * t;
        return Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity((1.0 - fadeT) * 0.45),
              width: 1.5,
            ),
          ),
        );
      },
    );
  }
}
