/// DeviceIntent — a fast, local pattern matcher for the most common voice
/// commands. Avoids a Claude round-trip when the user just says "next" or
/// "go home". Returns null when no local match — caller should then route
/// to Claude.
enum DeviceIntent {
  goHome,
  startFocus,
  nextStep,
  completeTask,
  whatsNext,
  pause,
}

DeviceIntent? matchIntent(String transcript) {
  final t = transcript.trim().toLowerCase();
  if (t.isEmpty) return null;

  if (_any(t, [
    'go home', 'home screen', 'back home', 'exit focus',
    'leave focus', 'end focus',
  ])) {
    return DeviceIntent.goHome;
  }
  if (_any(t, [
    'start focus', 'begin focus', 'focus mode',
    'focus on the next', 'focus on next',
    "let's start", 'lets start', 'start working',
  ])) {
    return DeviceIntent.startFocus;
  }
  if (_any(t, [
    'next step', 'next', 'mark step', 'finished step',
    'step done', 'done with this step', 'done with step',
    'check off', 'next one',
  ])) {
    return DeviceIntent.nextStep;
  }
  if (_any(t, [
    'complete task', 'task done', "i'm done", 'im done',
    'all done', 'finished it', 'task complete', 'mark complete',
    'mark this done', 'mark it done',
  ])) {
    return DeviceIntent.completeTask;
  }
  if (_any(t, [
    "what's next", 'whats next', 'what next', 'next task',
    "what's up next", 'what should i do', 'what do i have',
  ])) {
    return DeviceIntent.whatsNext;
  }
  if (_any(t, ['pause', 'stop', 'wait', 'hold on', 'hang on'])) {
    return DeviceIntent.pause;
  }

  return null;
}

bool _any(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(n)) return true;
  }
  return false;
}
