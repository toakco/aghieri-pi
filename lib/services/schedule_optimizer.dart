import 'package:flutter/foundation.dart';
import '../models/task_model.dart';
import '../models/user_profile.dart';
import 'interaction_tracker.dart';
import 'task_service.dart';
import 'profile_service.dart';
import 'claude_service.dart';

/// ScheduleOptimizer — suggests optimal time slots for tasks
/// based on user patterns, preferences, and calendar gaps.
class ScheduleOptimizer {
  ScheduleOptimizer._();
  static final instance = ScheduleOptimizer._();

  /// Suggest optimal slots for a task based on user history and preferences.
  Future<List<TimeSlot>> suggestSlots(TaskModel task) async {
    final profile = await ProfileService.instance.getProfile();
    final hourly = await InteractionTracker.instance.getHourlyDistribution();
    final existingTasks = await TaskService.instance.getTodayTasks();

    // Parse waking hours
    final wakeHour = _parseHour(profile.wakeTime);
    final sleepHour = _parseHour(profile.sleepTime);

    // Find occupied hours
    final occupied = <int>{};
    for (final t in existingTasks) {
      if (t.scheduledTime != null && t.id != task.id) {
        final start = _parseHour(t.scheduledTime!);
        final end = t.scheduledEndTime != null
            ? _parseHour(t.scheduledEndTime!)
            : start + 1;
        for (int h = start; h < end && h < 24; h++) {
          occupied.add(h);
        }
      }
    }

    // Score each available hour
    final scores = <int, double>{};
    for (int h = wakeHour; h < sleepHour; h++) {
      if (occupied.contains(h)) continue;

      double score = 50; // base

      // Boost hours the user is historically active
      final activity = hourly[h] ?? 0;
      score += activity * 3;

      // Morning person boost for early hours
      if (profile.schedulePreference == 'morning' && h < 12) {
        score += 20;
      }
      // Night owl boost for later hours
      if (profile.schedulePreference == 'night_owl' && h >= 16) {
        score += 20;
      }

      // Avoid scheduling right at wake or sleep edges
      if (h == wakeHour || h == sleepHour - 1) {
        score -= 15;
      }

      // Prefer gaps between existing tasks (buffer time)
      if (occupied.contains(h - 1) || occupied.contains(h + 1)) {
        score -= 10;
      }

      scores[h] = score;
    }

    // Sort by score, return top 3
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ranked.take(3).map((e) {
      final h = e.key;
      return TimeSlot(
        start: '${h.toString().padLeft(2, '0')}:00',
        end: '${(h + 1).toString().padLeft(2, '0')}:00',
        score: e.value,
        reason: _reason(h, profile, hourly),
      );
    }).toList();
  }

  /// Ask Claude for a natural-language schedule suggestion.
  Future<String> getClaudeSuggestion(TaskModel task) async {
    try {
      final slots = await suggestSlots(task);
      if (slots.isEmpty) {
        return 'Your schedule looks pretty full today. Want to push ${task.title} to tomorrow?';
      }
      final slotStr = slots.map((s) => s.start).join(', ');
      return await ClaudeService.instance.suggestReschedule(
        '${task.title} (available slots: $slotStr)',
      );
    } catch (e) {
      debugPrint('[Optimizer] Claude suggestion error: $e');
      return 'How about we find a quiet spot in your schedule for ${task.title}?';
    }
  }

  /// Find the best slot for tomorrow.
  Future<List<TimeSlot>> suggestTomorrowSlots(TaskModel task) async {
    final profile = await ProfileService.instance.getProfile();
    final wakeHour = _parseHour(profile.wakeTime);
    final sleepHour = _parseHour(profile.sleepTime);

    // For tomorrow, no existing tasks to block (simplified)
    final slots = <TimeSlot>[];

    // Morning slot
    if (profile.schedulePreference != 'night_owl') {
      final h = wakeHour + 1;
      slots.add(TimeSlot(
        start: '${h.toString().padLeft(2, '0')}:00',
        end: '${(h + 1).toString().padLeft(2, '0')}:00',
        score: 80,
        reason: 'Fresh start to the day',
      ));
    }

    // Midday slot
    final mid = ((wakeHour + sleepHour) / 2).floor();
    slots.add(TimeSlot(
      start: '${mid.toString().padLeft(2, '0')}:00',
      end: '${(mid + 1).toString().padLeft(2, '0')}:00',
      score: 70,
      reason: 'Middle of your active hours',
    ));

    // Afternoon slot
    if (profile.schedulePreference != 'morning') {
      final h = sleepHour - 4;
      slots.add(TimeSlot(
        start: '${h.toString().padLeft(2, '0')}:00',
        end: '${(h + 1).toString().padLeft(2, '0')}:00',
        score: 65,
        reason: 'Afternoon focus window',
      ));
    }

    return slots;
  }

  String _reason(int hour, UserProfile profile, Map<int, int> hourly) {
    final activity = hourly[hour] ?? 0;
    if (activity > 5) return 'You\'re usually active around this time';
    if (profile.schedulePreference == 'morning' && hour < 12) {
      return 'Matches your morning preference';
    }
    if (profile.schedulePreference == 'night_owl' && hour >= 16) {
      return 'Fits your night owl rhythm';
    }
    return 'Open slot in your schedule';
  }

  int _parseHour(String time) {
    final parts = time.split(':');
    return int.tryParse(parts[0]) ?? 8;
  }
}

class TimeSlot {
  final String start;
  final String end;
  final double score;
  final String reason;

  const TimeSlot({
    required this.start,
    required this.end,
    required this.score,
    required this.reason,
  });

  String get formatted {
    final sh = int.parse(start.split(':')[0]);
    final eh = int.parse(end.split(':')[0]);
    String fmt(int h) {
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      final p = h >= 12 ? 'PM' : 'AM';
      return '$h12 $p';
    }
    return '${fmt(sh)} – ${fmt(eh)}';
  }
}
