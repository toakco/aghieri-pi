import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';

/// ProfileService — reads/writes user profile.
///
/// Storage priority:
///   Write: Firestore (primary) + SharedPreferences (local cache)
///   Read:  SharedPreferences first (instant), Firestore refreshes in background
class ProfileService {
  ProfileService._();
  static final instance = ProfileService._();

  static const _prefKey    = 'aghieri_profile';
  static const _onboardKey = 'aghieri_onboarded';

  late final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _db.collection('users').doc(AuthService.instance.uid);

  // ── Onboarding ─────────────────────────────────────────────────────────────
  Future<bool> isOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardKey) ?? false;
  }

  Future<void> markOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardKey, true);
    try {
      await _userDoc.set({'onboarded': true}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Profile] Firestore markOnboarded error: $e');
    }
  }

  // ── Terms of Service ────────────────────────────────────────────────────────
  Future<bool> hasTosAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('aghieri_tos_accepted') ?? false;
  }

  Future<void> acceptTos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('aghieri_tos_accepted', true);
    try {
      await _userDoc.set({
        'profile': {'tos_accepted_at': FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Profile] Firestore acceptTos error: $e');
    }
  }

  // ── Profile ────────────────────────────────────────────────────────────────
  Future<UserProfile> getProfile() async {
    // Serve from local cache instantly
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    UserProfile local = const UserProfile();
    if (raw != null) {
      try {
        local = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }

    // Refresh from Firestore in background
    _refreshFromFirestore(prefs);

    return local;
  }

  Future<void> _refreshFromFirestore(SharedPreferences prefs) async {
    try {
      final snap = await _userDoc.get();
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (data.containsKey('profile')) {
        final profileData = data['profile'] as Map<String, dynamic>;
        final profile = UserProfile.fromJson(profileData);
        await prefs.setString(_prefKey, jsonEncode(profile.toJson()));
      }
    } catch (e) {
      debugPrint('[Profile] Firestore refresh error: $e');
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    // Local cache first (instant)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(profile.toJson()));

    // Firestore (authoritative)
    try {
      await _userDoc.set({
        'profile': profile.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Profile] Firestore save error: $e');
    }
  }

  // ── Portfolio suggestions (Phase 5) ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getSuggestions() async {
    try {
      final snap = await _userDoc
          .collection('suggestions')
          .where('dismissed', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get();
      return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (e) {
      debugPrint('[Profile] getSuggestions error: $e');
      return [];
    }
  }

  Future<void> dismissSuggestion(String suggestionId) async {
    try {
      await _userDoc
          .collection('suggestions')
          .doc(suggestionId)
          .update({'dismissed': true});
    } catch (e) {
      debugPrint('[Profile] dismissSuggestion error: $e');
    }
  }
}
