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

  // ── Phone auth state ────────────────────────────────────────────────────────
  bool _phoneMode = false;
  String _verificationId = '';
  final _phoneCtrl = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool _codeSent = false;

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

  Future<void> _sendPhoneCode() async {
    final number = _phoneCtrl.text.trim();
    if (number.isEmpty) return;
    setState(() => _busy = true);
    final error = await AuthService.instance.sendPhoneCode(
      phoneNumber: number,
      onCodeSent: (id) {
        if (!mounted) return;
        setState(() { _verificationId = id; _codeSent = true; _busy = false; });
      },
      onAutoVerified: (cred) async {
        final ok = await AuthService.instance.confirmPhoneCode(
          verificationId: cred.verificationId ?? '',
          smsCode: cred.smsCode ?? '',
        );
        if (mounted) { setState(() => _busy = false); _afterAuth(ok, 'Phone'); }
      },
    );
    if (error != null && mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error, style: AghieriTextStyles.body(size: 14)),
        backgroundColor: AghieriColors.surface,
      ));
    }
  }

  Future<void> _confirmCode() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await AuthService.instance.confirmPhoneCode(
      verificationId: _verificationId,
      smsCode: _codeCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _afterAuth(ok, 'Phone');
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

            if (!_phoneMode) ...[
              _AuthButton(
                label: 'Continue with Google',
                icon: Icons.g_mobiledata_rounded,
                onPressed: _busy ? null : _google,
              ),
              const SizedBox(height: 12),
              if (_appleAvailable) ...[
                _AuthButton(
                  label: 'Continue with Apple',
                  icon: Icons.apple_rounded,
                  onPressed: _busy ? null : _apple,
                ),
                const SizedBox(height: 12),
              ],
              _AuthButton(
                label: 'Continue with Phone',
                icon: Icons.phone_outlined,
                onPressed: _busy ? null : () => setState(() => _phoneMode = true),
              ),
            ] else ...[
              if (!_codeSent) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: AghieriTextStyles.body(size: 16),
                  decoration: InputDecoration(
                    hintText: '+1 555 000 0000',
                    labelText: 'Phone number',
                    labelStyle: AghieriTextStyles.caption(),
                    filled: true,
                    fillColor: AghieriColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.phone_outlined,
                        color: AghieriColors.textSecondary, size: 20),
                  ),
                  onSubmitted: (_) => _sendPhoneCode(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _sendPhoneCode,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AghieriColors.bg))
                        : const Text('Send code'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _phoneMode = false),
                  child: Text('Back', style: AghieriTextStyles.caption()),
                ),
              ] else ...[
                Text('Enter the 6-digit code sent to ${_phoneCtrl.text}',
                    style: AghieriTextStyles.body(size: 14,
                        color: AghieriColors.textSecondary)),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: AghieriTextStyles.heading(size: 28),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '------',
                    filled: true,
                    fillColor: AghieriColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _confirmCode(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _confirmCode,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AghieriColors.bg))
                        : const Text('Verify'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() { _codeSent = false; _codeCtrl.clear(); }),
                  child: Text('Resend code', style: AghieriTextStyles.caption()),
                ),
              ],
            ],

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
