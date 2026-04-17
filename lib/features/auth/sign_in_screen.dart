import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';

/// Sign-in screen — Google + Apple options. Linking-mode preserves any data
/// the user already created while anonymous.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  bool get _appleAvailable {
    if (kIsWeb) return true;
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await AuthService.instance.signInWithGoogle();
    if (!mounted) return;
    setState(() => _busy = false);
    _afterAuth(ok, 'Google');
  }

  Future<void> _apple() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await AuthService.instance.signInWithApple();
    if (!mounted) return;
    setState(() => _busy = false);
    _afterAuth(ok, 'Apple');
  }

  void _afterAuth(bool ok, String provider) {
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Signed in with $provider.',
            style: AghieriTextStyles.body(size: 14)),
        backgroundColor: AghieriColors.surface,
      ));
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("$provider sign-in didn't complete.",
            style: AghieriTextStyles.body(size: 14)),
        backgroundColor: AghieriColors.surface,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final upgraded = user != null && !user.isAnonymous;

    return Scaffold(
      backgroundColor: AghieriColors.bg,
      appBar: AppBar(
        backgroundColor: AghieriColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AghieriColors.textSecondary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Sign in', style: AghieriTextStyles.heading(size: 18)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(
              upgraded
                  ? 'Signed in as ${user.email ?? user.displayName ?? user.uid}.'
                  : 'Sign in so your tasks sync across phone, web, and your device.',
              style: AghieriTextStyles.body(size: 14),
            ),
            const SizedBox(height: 32),

            _AuthButton(
              label: 'Continue with Google',
              icon: Icons.g_mobiledata_rounded,
              onPressed: _busy ? null : _google,
            ),
            const SizedBox(height: 12),

            if (_appleAvailable)
              _AuthButton(
                label: 'Continue with Apple',
                icon: Icons.apple_rounded,
                onPressed: _busy ? null : _apple,
              ),

            const Spacer(),

            if (upgraded)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await AuthService.instance.signOut();
                        if (mounted) context.pop();
                      },
                child: Text('Sign out',
                    style: AghieriTextStyles.body(
                        size: 14, color: AghieriColors.textSecondary)),
              ),

            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AghieriColors.accent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _AuthButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AghieriColors.surface,
          side: BorderSide(color: AghieriColors.surfaceHigh),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, color: AghieriColors.textPrimary),
        label: Text(label,
            style: AghieriTextStyles.body(
                size: 15, weight: FontWeight.w500)),
      ),
    );
  }
}
