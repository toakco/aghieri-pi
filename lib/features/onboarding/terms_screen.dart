import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/profile_service.dart';

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.readOnly) ...[
                Center(
                  child: Text(
                    'Terms & Privacy',
                    style: AghieriTextStyles.heading(size: 28),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(duration: 400.ms),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Please review before continuing.',
                    style: AghieriTextStyles.body(
                        color: AghieriColors.textSecondary),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 100.ms),
                ),
                const SizedBox(height: 24),
              ],
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
                            style: AghieriTextStyles.body(
                                size: 16, weight: FontWeight.w600)),
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
              if (!widget.readOnly) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => setState(() => _accepted = !_accepted),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
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
                            ? const Icon(Icons.check,
                                size: 16, color: AghieriColors.bg)
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
                const SizedBox(height: 16),
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
    );
  }
}
