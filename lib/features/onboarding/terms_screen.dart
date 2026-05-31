import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/profile_service.dart';
import '../../widgets/ambient_breath_background.dart';

/// Standalone Terms of Service screen.
/// Used by router guard when returning user hasn't accepted ToS.
/// Also reachable from Settings in read-only mode.
class TermsScreen extends StatefulWidget {
  final bool readOnly;
  const TermsScreen({super.key, this.readOnly = false});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _accepted = false;

  Future<void> _accept() async {
    await ProfileService.instance.acceptTos();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      appBar: widget.readOnly
          ? AppBar(
              backgroundColor: AghieriColors.bg,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: AghieriColors.textSecondary, size: 18),
                onPressed: () => context.pop(),
              ),
              title: Text('Terms of Service',
                  style: AghieriTextStyles.heading(size: 18)),
            )
          : null,
      body: AmbientBreathBackground(
        intensity: AmbientIntensity.hush,
        child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AghieriSpacing.rest,
                AghieriSpacing.horizon,
                AghieriSpacing.rest,
                AghieriSpacing.gather,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!widget.readOnly) ...[
                    Text(
                      'Terms & Privacy',
                      style: AghieriTextStyles.heading(size: 28),
                      textAlign: TextAlign.center,
                    )
                        .animate()
                        .fadeIn(
                          duration: AghieriMotion.arrive,
                          curve: AghieriMotion.wake,
                        )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(
                          begin: 1.0,
                          end: 1.012,
                          duration: AghieriMotion.breathe,
                          curve: AghieriMotion.breath,
                        ),
                    SizedBox(height: AghieriSpacing.tight),
                    Text(
                      'Please review before continuing.',
                      style: AghieriTextStyles.body(
                          color: AghieriColors.textSecondary),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(
                          delay: 120.ms,
                          duration: AghieriMotion.arrive,
                          curve: AghieriMotion.wake,
                        ),
                    SizedBox(height: AghieriSpacing.rest),
                  ],
                  Expanded(
                    child: SingleChildScrollView(
                      child: BreathingSurface(
                        glowColor: AghieriColors.ledIdle,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            AghieriSpacing.rest,
                            AghieriSpacing.rest,
                            AghieriSpacing.rest,
                            AghieriSpacing.gather,
                          ),
                          decoration: BoxDecoration(
                            color: AghieriColors.surface,
                            borderRadius:
                                BorderRadius.circular(AghieriRadii.gentle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Aghieri Terms of Service',
                                style: AghieriTextStyles.body(
                                    size: 16, weight: FontWeight.w600),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: AghieriSpacing.breath),
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
                              textAlign: TextAlign.left,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),
                  if (!widget.readOnly) ...[
                    SizedBox(height: AghieriSpacing.rest),
                    GestureDetector(
                      onTap: () => setState(() => _accepted = !_accepted),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: AghieriMotion.ease,
                            curve: AghieriMotion.notice,
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(AghieriRadii.tight - 4),
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
                            alignment: Alignment.center,
                            child: AnimatedTickMark(
                              checked: _accepted,
                              color: AghieriColors.bg,
                              size: 16,
                            ),
                          ),
                          SizedBox(width: AghieriSpacing.breath - 2),
                          Flexible(
                            child: Text(
                              'I have read and agree to the Terms of Service and Privacy Policy',
                              style: AghieriTextStyles.body(size: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: AghieriSpacing.rest),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _accepted ? _accept : null,
                        child: const Text('I agree — continue'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
