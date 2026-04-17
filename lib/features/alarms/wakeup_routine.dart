import '../../services/claude_service.dart';
import '../../services/profile_service.dart';
import '../../services/task_service.dart';
import '../../services/voice_service.dart';

/// Wake-up routine: generates a calm 45-second morning briefing
/// via Claude API, then speaks it using ElevenLabs Antonio voice.
/// Hard-capped at 60s (truncates at last sentence boundary before 55s).
class WakeupRoutine {
  WakeupRoutine._();
  static final instance = WakeupRoutine._();

  Future<void> execute() async {
    try {
      final profile = await ProfileService.instance.getProfile();
      final name = profile.displayName;
      final interests = profile.interests;
      final todayTasks = await TaskService.instance.getTodayTasks();
      final firstTask = todayTasks.isNotEmpty ? todayTasks.first.title : null;

      final interestStr = interests.isNotEmpty
          ? interests.take(5).join(', ')
          : 'general wellness';

      final prompt =
          'Generate a calm 45-second morning briefing for $name. '
          'Brief greeting, 1 short item per category from [$interestStr], '
          '${firstTask != null ? 'end with first task: $firstTask' : 'end with encouragement to start the day'}. '
          'Tone: gentle, encouraging, never urgent. '
          'Keep under 120 words total.';

      final response = await ClaudeService.instance.chat(prompt);
      if (response.isEmpty) {
        // Fallback
        await VoiceService.instance.speak(
            'Good morning${name.isNotEmpty ? ", $name" : ""}. Your day is ready.');
        return;
      }

      // Truncate at last sentence boundary before ~55s worth of text (~140 words)
      final truncated = _truncateToWordLimit(response, 140);
      await VoiceService.instance.speak(truncated);
    } catch (_) {
      // Fallback on any error
      await VoiceService.instance.speak('Good morning. Your day is ready.');
    }
  }

  String _truncateToWordLimit(String text, int maxWords) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= maxWords) return text;

    // Find last sentence boundary before maxWords
    final truncated = words.take(maxWords).join(' ');
    final lastSentence = truncated.lastIndexOf(RegExp(r'[.!?]\s'));
    if (lastSentence > truncated.length * 0.5) {
      return truncated.substring(0, lastSentence + 1).trim();
    }
    return '$truncated.';
  }
}
