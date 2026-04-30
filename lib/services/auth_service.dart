import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// AuthService — handles Firebase Auth state for Aghieri.
///
/// Strategy:
///   1. On first launch: sign in anonymously so the app is usable immediately
///   2. User can later upgrade to Google or Apple — credential is LINKED to the
///      anon uid so existing tasks/profile carry over
///   3. After upgrade, the same uid persists across phone, web, and Pi device
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  late final _auth = FirebaseAuth.instance;
  late final _db   = FirebaseFirestore.instance;

  User? get currentUser => _isLinux ? null : _auth.currentUser;
  String get uid => _auth.currentUser?.uid ?? 'local';
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;
  Stream<User?> get authStateChanges => _isLinux
      ? const Stream.empty()
      : _auth.authStateChanges();

  bool get _isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  // ── Initialize ─────────────────────────────────────────────────────────────
  Future<void> init() async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
        debugPrint('[Auth] Signed in anonymously: ${_auth.currentUser?.uid}');
      } else {
        debugPrint('[Auth] Already signed in: ${_auth.currentUser?.uid}');
      }
      await _ensureUserDoc();
    } catch (e) {
      debugPrint('[Auth] Init error: $e');
    }
  }

  Future<void> _ensureUserDoc() async {
    final uid = this.uid;
    if (uid == 'local') return;
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'isAnonymous': _auth.currentUser?.isAnonymous ?? true,
      }, SetOptions(merge: true));
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── Email link (kept for compatibility) ────────────────────────────────────
  Future<bool> linkEmail(String email, String password) async {
    try {
      final credential = EmailAuthProvider.credential(
          email: email, password: password);
      await _auth.currentUser?.linkWithCredential(credential);
      await _db.collection('users').doc(uid).update({
        'email': email,
        'isAnonymous': false,
      });
      return true;
    } catch (e) {
      debugPrint('[Auth] Link email error: $e');
      return false;
    }
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────────
  /// Signs in with Google. If the user is currently anonymous, the Google
  /// credential is LINKED so their existing data carries over. If linking
  /// fails because that Google account already has a Firebase user, falls
  /// back to a plain sign-in (the anon uid's data is left orphaned).
  Future<bool> signInWithGoogle() async {
    try {
      final credential = await _googleCredential();
      if (credential == null) return false;

      final user = _auth.currentUser;
      if (user != null && user.isAnonymous) {
        try {
          await user.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') {
            await _auth.signInWithCredential(credential);
          } else {
            rethrow;
          }
        }
      } else {
        await _auth.signInWithCredential(credential);
      }

      await _markUpgraded(provider: 'google');
      return true;
    } catch (e) {
      debugPrint('[Auth] Google sign-in error: $e');
      return false;
    }
  }

  Future<AuthCredential?> _googleCredential() async {
    final googleSignIn = GoogleSignIn();
    final account = await googleSignIn.signIn();
    if (account == null) return null;
    final tokens = await account.authentication;
    return GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
  }

  // ── Apple Sign-In ──────────────────────────────────────────────────────────
  /// Signs in with Apple. Same link-or-fallback strategy as Google.
  /// Only available on iOS, macOS, and web (not Android/Windows/Linux).
  Future<bool> signInWithApple() async {
    try {
      final rawNonce = _randomNonce();
      final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final user = _auth.currentUser;
      if (user != null && user.isAnonymous) {
        try {
          await user.linkWithCredential(oauthCredential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') {
            await _auth.signInWithCredential(oauthCredential);
          } else {
            rethrow;
          }
        }
      } else {
        await _auth.signInWithCredential(oauthCredential);
      }

      // Apple only provides display name on first auth — capture if present.
      final displayName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      if (displayName.isNotEmpty) {
        try {
          await _auth.currentUser?.updateDisplayName(displayName);
        } catch (_) {}
      }

      await _markUpgraded(provider: 'apple');
      return true;
    } catch (e) {
      debugPrint('[Auth] Apple sign-in error: $e');
      return false;
    }
  }

  // ── Phone Sign-In ──────────────────────────────────────────────────────────
  /// Step 1 — send SMS. Returns null on success, error string on failure.
  Future<String?> sendPhoneCode({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(PhoneAuthCredential) onAutoVerified,
  }) async {
    String? error;
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (cred) => onAutoVerified(cred),
      verificationFailed: (e) {
        error = e.message ?? 'Verification failed.';
        debugPrint('[Auth] Phone verification failed: $e');
      },
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
    return error;
  }

  /// Step 2 — confirm SMS code. Links to anon account if possible.
  Future<bool> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final user = _auth.currentUser;
      if (user != null && user.isAnonymous) {
        try {
          await user.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'provider-already-linked') {
            await _auth.signInWithCredential(credential);
          } else {
            rethrow;
          }
        }
      } else {
        await _auth.signInWithCredential(credential);
      }
      await _markUpgraded(provider: 'phone');
      return true;
    } catch (e) {
      debugPrint('[Auth] Phone confirm error: $e');
      return false;
    }
  }

  Future<void> _markUpgraded({required String provider}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'authProvider': provider,
        'isAnonymous': false,
        'upgradedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Auth] mark upgraded error: $e');
    }
  }

  String _randomNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(length, (_) => charset[r.nextInt(charset.length)])
        .join();
  }
}
