import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'interaction_tracker.dart';
import 'profile_service.dart';
import 'task_service.dart';

/// TRIBE v2 Engine — adaptive behavior system.
///
/// T = Trust (does the user rely on the app?)
/// R = Rhythm (when and how do they work?)
/// I = Impulse (how reactive vs. deliberate?)
/// B = Bandwidth (cognitive load tolerance)
/// E = Energy (current capacity)
///
/// These scores are derived from interaction patterns, not surveys.
/// They inform UI decisions: notification timing, feature density,
/// communication tone, and task ordering.
class TribeEngine {
  TribeEngine._();
  static final instance = TribeEngine._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _tribeDoc =>
      _db.collection('users').doc(AuthService.instance.uid);

  /// Compute the current TRIBE profile from interaction history.
  Future<TribeProfile> analyze() async {
    final tracker = InteractionTracker.instance;
    final typeCounts = await tracker.getTypeCounts(days: 14);
    final hourly = await tracker.getHourlyDistribution(days: 14);
    final total = await tracker.getTotalCount(days: 14);
    final profile = await ProfileService.instance.getProfile();

    // T — Trust: how consistently does the user return?
    final trust = _computeTrust(total);

    // R — Rhythm: morning vs night distribution
    final rhythm = _computeRhythm(hourly, profile);

    // I — Impulse: ratio of voice commands to manual actions
    final impulse = _computeImpulse(typeCounts);

    // B — Bandwidth: how many tasks they manage simultaneously
    final bandwidth = await _computeBandwidth();

    // E — Energy: recent activity level vs historical baseline
    final energy = _computeEnergy(typeCounts, total);

    final tribe = TribeProfile(
      trust: trust,
      rhythm: rhythm,
      impulse: impulse,
      bandwidth: bandwidth,
      energy: energy,
      updatedAt: DateTime.now(),
    );

    // Persist to Firestore
    try {
      await _tribeDoc.set({
        'tribe_profile': tribe.toJson(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[TRIBE] save error: $e');
    }

    return tribe;
  }

  /// Load cached TRIBE profile (fast, no recomputation).
  Future<TribeProfile?> getCached() async {
    try {
      final snap = await _tribeDoc.get();
      final data = snap.data();
      if (data != null && data.containsKey('tribe_profile')) {
        return TribeProfile.fromJson(
            data['tribe_profile'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[TRIBE] getCached error: $e');
    }
    return null;
  }

  /// Get adaptive suggestions based on current TRIBE state.
  List<TribeSuggestion> getSuggestions(TribeProfile tribe) {
    final suggestions = <TribeSuggestion>[];

    // Low trust → reduce friction, simplify
    if (tribe.trust < 0.3) {
      suggestions.add(const TribeSuggestion(
        type: SuggestionType.uiSimplify,
        message: 'Keep things simple today. One task at a time.',
        priority: 0.9,
      ));
    }

    // Night owl rhythm → shift notifications later
    if (tribe.rhythm == RhythmType.nightOwl) {
      suggestions.add(const TribeSuggestion(
        type: SuggestionType.scheduleShift,
        message: 'Your peak hours are afternoon and evening. Scheduling heavier tasks then.',
        priority: 0.7,
      ));
    }

    // High impulse → voice-first UI
    if (tribe.impulse > 0.7) {
      suggestions.add(const TribeSuggestion(
        type: SuggestionType.voiceFirst,
        message: 'Voice seems to be your thing. Tap the circle anytime to talk.',
        priority: 0.6,
      ));
    }

    // Low bandwidth → reduce visible tasks
    if (tribe.bandwidth < 3) {
      suggestions.add(const TribeSuggestion(
        type: SuggestionType.reduceTasks,
        message: 'Showing fewer tasks to keep things clear.',
        priority: 0.8,
      ));
    }

    // Low energy → gentle mode
    if (tribe.energy < 0.3) {
      suggestions.add(const TribeSuggestion(
        type: SuggestionType.gentleMode,
        message: 'Low energy day. Focus on what matters most.',
        priority: 0.85,
      ));
    }

    suggestions.sort((a, b) => b.priority.compareTo(a.priority));
    return suggestions;
  }

  // ── Internal scoring ──────────────────────────────────────────────────────

  double _computeTrust(int totalInteractions) {
    // More interactions = more trust, capped at 1.0
    return min(totalInteractions / 50.0, 1.0);
  }

  RhythmType _computeRhythm(Map<int, int> hourly, UserProfile profile) {
    int morning = 0, afternoon = 0, evening = 0;
    hourly.forEach((h, count) {
      if (h >= 5 && h < 12) morning += count;
      else if (h >= 12 && h < 17) afternoon += count;
      else if (h >= 17 && h < 24) evening += count;
    });

    if (morning > afternoon && morning > evening) return RhythmType.earlyBird;
    if (evening > morning && evening > afternoon) return RhythmType.nightOwl;
    return RhythmType.flexible;
  }

  double _computeImpulse(Map<String, int> typeCounts) {
    final voice = typeCounts['voiceCommand'] ?? 0;
    final manual = (typeCounts['taskCreated'] ?? 0) +
        (typeCounts['taskCompleted'] ?? 0) +
        (typeCounts['stepCompleted'] ?? 0);
    final total = voice + manual;
    if (total == 0) return 0.5;
    return voice / total;
  }

  Future<double> _computeBandwidth() async {
    final tasks = await TaskService.instance.getTodayTasks();
    final active = tasks.where((t) => t.status != 'complete').length;
    return active.toDouble().clamp(0, 10);
  }

  double _computeEnergy(Map<String, int> typeCounts, int total) {
    // Recent completions relative to total activity = energy indicator
    final completed = (typeCounts['taskCompleted'] ?? 0) +
        (typeCounts['stepCompleted'] ?? 0);
    if (total == 0) return 0.5;
    return min(completed / (total * 0.3), 1.0);
  }
}

// ── Models ──────────────────────────────────────────────────────────────────────

class TribeProfile {
  final double trust;
  final RhythmType rhythm;
  final double impulse;
  final double bandwidth;
  final double energy;
  final DateTime updatedAt;

  const TribeProfile({
    required this.trust,
    required this.rhythm,
    required this.impulse,
    required this.bandwidth,
    required this.energy,
    required this.updatedAt,
  });

  factory TribeProfile.fromJson(Map<String, dynamic> j) => TribeProfile(
        trust: (j['trust'] as num?)?.toDouble() ?? 0.5,
        rhythm: RhythmType.values.firstWhere(
          (r) => r.name == (j['rhythm'] ?? 'flexible'),
          orElse: () => RhythmType.flexible,
        ),
        impulse: (j['impulse'] as num?)?.toDouble() ?? 0.5,
        bandwidth: (j['bandwidth'] as num?)?.toDouble() ?? 5,
        energy: (j['energy'] as num?)?.toDouble() ?? 0.5,
        updatedAt: j['updated_at'] != null
            ? DateTime.tryParse(j['updated_at']) ?? DateTime.now()
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'trust': trust,
        'rhythm': rhythm.name,
        'impulse': impulse,
        'bandwidth': bandwidth,
        'energy': energy,
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Overall engagement score (0-1).
  double get engagement => (trust * 0.3 + energy * 0.4 + (1 - impulse) * 0.3);
}

enum RhythmType { earlyBird, nightOwl, flexible }

class TribeSuggestion {
  final SuggestionType type;
  final String message;
  final double priority;

  const TribeSuggestion({
    required this.type,
    required this.message,
    required this.priority,
  });
}

enum SuggestionType {
  uiSimplify,
  scheduleShift,
  voiceFirst,
  reduceTasks,
  gentleMode,
}
