import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/oauth_service.dart';

/// Renders briefly after the OAuth provider redirects back with ?code=...&state=...
/// Exchanges the code via Cloud Function, then routes back to /integrations.
class OAuthCallbackScreen extends StatefulWidget {
  final String provider; // 'spotify' or 'notion'
  final String? code;
  final String? state;
  final String? error;

  const OAuthCallbackScreen({
    super.key,
    required this.provider,
    this.code,
    this.state,
    this.error,
  });

  @override
  State<OAuthCallbackScreen> createState() => _OAuthCallbackScreenState();
}

class _OAuthCallbackScreenState extends State<OAuthCallbackScreen> {
  String _status = 'Connecting...';

  @override
  void initState() {
    super.initState();
    _exchange();
  }

  Future<void> _exchange() async {
    if (widget.error != null && widget.error!.isNotEmpty) {
      setState(() => _status = 'Authorization cancelled.');
      _bounceBack(success: false);
      return;
    }

    final code = widget.code;
    final state = widget.state;
    if (code == null || state == null || code.isEmpty || state.isEmpty) {
      setState(() => _status = 'Missing code or state.');
      _bounceBack(success: false);
      return;
    }

    final result = await OAuthService.instance.completeAuth(
      widget.provider, code, state,
    );

    if (!mounted) return;
    if (result != null && result['connected'] == true) {
      setState(() => _status = 'Connected.');
      _bounceBack(success: true);
    } else {
      setState(() => _status = 'Connection failed.');
      _bounceBack(success: false);
    }
  }

  void _bounceBack({required bool success}) {
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      context.go('/integrations');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: AghieriColors.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(_status, style: AghieriTextStyles.body(size: 14)),
          ],
        ),
      ),
    );
  }
}
