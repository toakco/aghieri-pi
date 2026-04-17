import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// OAuthService — handles Spotify + Notion OAuth flows via Cloud Functions.
/// Functions are invoked via raw HTTP (callable wire format) to dodge the
/// cloud_functions package's dart2js Int64 bug.
class OAuthService {
  OAuthService._();
  static final instance = OAuthService._();

  static const _fnBase =
      'https://us-central1-aghieri-7a8ce.cloudfunctions.net';

  Future<String?> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }

  /// Returns the provider authorize URL the browser should navigate to.
  Future<String?> startAuth(String provider) async {
    final token = await _idToken();
    if (token == null) return null;

    final fn = provider == 'spotify' ? 'spotifyAuthStart' : 'notionAuthStart';
    try {
      final resp = await http.post(
        Uri.parse('$_fnBase/$fn'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'data': {}}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = body['result'] as Map<String, dynamic>? ?? {};
        return result['url'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Exchanges the code+state from the redirect back into a stored token.
  /// Returns a map with display info (e.g. profile or workspace_name) on success.
  Future<Map<String, dynamic>?> completeAuth(
    String provider,
    String code,
    String state,
  ) async {
    final token = await _idToken();
    if (token == null) return null;

    final fn =
        provider == 'spotify' ? 'spotifyAuthCallback' : 'notionAuthCallback';
    try {
      final resp = await http.post(
        Uri.parse('$_fnBase/$fn'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'data': {'code': code, 'state': state},
        }),
      ).timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['result'] as Map<String, dynamic>? ?? {};
      }
    } catch (_) {}
    return null;
  }

  /// Reads the stored integration doc for display ("Connected as ...").
  Future<Map<String, dynamic>?> readIntegration(String provider) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc(provider)
          .get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnect(String provider) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('integrations')
          .doc(provider)
          .delete();
    } catch (_) {}
  }

  /// Open the provider's authorize URL in the browser tab (web: same-tab nav,
  /// mobile: external browser). Returns true if the launch succeeded.
  Future<bool> openAuthUrl(String url) async {
    final uri = Uri.parse(url);
    return launchUrl(uri, webOnlyWindowName: '_self');
  }
}
