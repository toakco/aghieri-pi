import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

/// InteractionTracker — records lightweight interaction metadata
/// for TRIBE v2 portfolio analysis. No PII, no content — just
/// what type of action happened and when.
class InteractionTracker {
  InteractionTracker._();
  static final instance = InteractionTracker._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _interactions =>
      _db.collection('portfolio').doc(AuthService.instance.uid).collection('interactions');

  /// Record an interaction. Called from throughout the app.
  Future<void> track(InteractionType type, {Map<String, dynamic>? meta}) async {
    try {
      final now = DateTime.now();
      await _interactions.add({
        'type': type.name,
        'hour_of_day': now.hour,
        'day_of_week': now.weekday,
        'timestamp': FieldValue.serverTimestamp(),
        if (meta != null) ...meta,
      });
    } catch (e) {
      debugPrint('[Tracker] $e');
    }
  }

  /// Get interaction counts grouped by type for the last N days.
  Future<Map<String, int>> getTypeCounts({int days = 7}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snap = await _interactions
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
          .get();
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final t = doc.data()['type'] as String? ?? 'unknown';
        counts[t] = (counts[t] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      debugPrint('[Tracker] getTypeCounts error: $e');
      return {};
    }
  }

  /// Get hourly distribution for the last N days.
  Future<Map<int, int>> getHourlyDistribution({int days = 14}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snap = await _interactions
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
          .get();
      final hours = <int, int>{};
      for (final doc in snap.docs) {
        final h = doc.data()['hour_of_day'] as int? ?? 0;
        hours[h] = (hours[h] ?? 0) + 1;
      }
      return hours;
    } catch (e) {
      debugPrint('[Tracker] getHourlyDistribution error: $e');
      return {};
    }
  }

  /// Get total interaction count.
  Future<int> getTotalCount({int days = 30}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snap = await _interactions
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
          .count()
          .get();
      return snap.count ?? 0;
    } catch (e) {
      debugPrint('[Tracker] getTotalCount error: $e');
      return 0;
    }
  }
}

/// All trackable interaction types.
enum InteractionType {
  taskCreated,
  taskCompleted,
  taskDeferred,
  stepCompleted,
  focusStarted,
  focusEnded,
  voiceCommand,
  appOpened,
  settingsChanged,
  categoryEdited,
  fileUploaded,
  alarmSet,
  aquariumOpened,
}
