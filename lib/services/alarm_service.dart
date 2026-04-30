import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/alarms/wakeup_routine.dart';
import 'music_service.dart';
import 'voice_service.dart';

/// Alarm — a scheduled time that triggers a voice wake-up.
class Alarm {
  final String id;
  final String label;             // e.g. "Good morning" or task title
  final TimeEntry time;           // hour + minute
  final List<int> days;           // 0=Mon … 6=Sun, empty = once
  bool enabled;
  final bool isWakeUp;            // triggers morning briefing routine
  final List<String> deviceIds;   // which registered devices fire this alarm
  final String? spotifyPlaylistId; // Spotify playlist URI for wake-up music

  Alarm({
    required this.id,
    required this.label,
    required this.time,
    this.days = const [],
    this.enabled = true,
    this.isWakeUp = false,
    this.deviceIds = const [],
    this.spotifyPlaylistId,
  });

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
    id:      j['id'] as String,
    label:   j['label'] as String,
    time:    TimeEntry(j['hour'] as int, j['minute'] as int),
    days:    List<int>.from(j['days'] ?? []),
    enabled: j['enabled'] as bool? ?? true,
    isWakeUp: j['is_wake_up'] as bool? ?? false,
    deviceIds: List<String>.from(j['device_ids'] ?? []),
    spotifyPlaylistId: j['spotify_playlist_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id':      id,
    'label':   label,
    'hour':    time.hour,
    'minute':  time.minute,
    'days':    days,
    'enabled': enabled,
    'is_wake_up': isWakeUp,
    'device_ids': deviceIds,
    'spotify_playlist_id': spotifyPlaylistId,
  };
}

class TimeEntry {
  final int hour;
  final int minute;
  const TimeEntry(this.hour, this.minute);

  String format() {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final p = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $p';
  }
}

/// AlarmService — schedules periodic checks against saved alarms.
/// Fires browser audio + Aghieri voice greeting when triggered.
class AlarmService {
  AlarmService._();
  static final instance = AlarmService._();

  static const _prefKey = 'alarms';

  List<Alarm> _alarms = [];
  Timer? _ticker;
  DateTime? _lastFired; // debounce — don't fire twice in same minute

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  Future<void> init() async {
    await _load();
    _startTicker();
  }

  void dispose() => _ticker?.cancel();

  // ── Persistence ─────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _alarms = list.map((j) => Alarm.fromJson(j as Map<String, dynamic>)).toList();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_alarms.map((a) => a.toJson()).toList()));
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────
  List<Alarm> get alarms => List.unmodifiable(_alarms);

  Future<void> add(Alarm alarm) async {
    _alarms.add(alarm);
    await _save();
  }

  Future<void> toggle(String id, bool enabled) async {
    final idx = _alarms.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _alarms[idx].enabled = enabled;
      await _save();
    }
  }

  Future<void> delete(String id) async {
    _alarms.removeWhere((a) => a.id == id);
    await _save();
  }

  /// Sync wake alarm with the user's onboarding wake time.
  Future<void> syncWakeAlarm(String wakeTime, String userName) async {
    const wakeId = '__wake__';
    _alarms.removeWhere((a) => a.id == wakeId);

    final parts = wakeTime.split(':');
    final hour = int.tryParse(parts.firstOrNull ?? '7') ?? 7;
    final minute = int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0;

    final greeting = userName.isNotEmpty
        ? 'Good morning, $userName. Your day is ready.'
        : 'Good morning. Your day is ready.';

    _alarms.add(Alarm(
      id: wakeId,
      label: greeting,
      time: TimeEntry(hour, minute),
      days: [0, 1, 2, 3, 4, 5, 6], // every day
      isWakeUp: true,
    ));
    await _save();
  }

  // ── Tick check ──────────────────────────────────────────────────────────────
  void _startTicker() {
    _ticker?.cancel();
    // Check every 30 seconds for accuracy without burning CPU
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  void _check() {
    final now = DateTime.now();
    // Debounce: only fire once per minute
    if (_lastFired != null &&
        _lastFired!.hour == now.hour &&
        _lastFired!.minute == now.minute) return;

    for (final alarm in _alarms) {
      if (!alarm.enabled) continue;
      if (alarm.time.hour != now.hour || alarm.time.minute != now.minute) continue;

      // Day filter (0=Mon … 6=Sun matches DateTime.weekday - 1)
      if (alarm.days.isNotEmpty) {
        final todayIndex = now.weekday - 1; // 0=Mon
        if (!alarm.days.contains(todayIndex)) continue;
      }

      _lastFired = now;
      _fire(alarm);
      break; // only one alarm per minute
    }
  }

  Future<void> _fire(Alarm alarm) async {
    // Disarm one-shot alarms
    if (alarm.days.isEmpty) {
      alarm.enabled = false;
      await _save();
    }

    // Start Spotify playlist if configured
    if (alarm.spotifyPlaylistId != null && alarm.spotifyPlaylistId!.isNotEmpty) {
      await MusicService.instance.playSpotifyPlaylist(alarm.spotifyPlaylistId!);
    }

    if (alarm.isWakeUp) {
      // Full morning briefing via Claude + ElevenLabs
      await WakeupRoutine.instance.execute();
    } else {
      // Simple voice announcement
      await VoiceService.instance.speak(alarm.label);
    }
  }

  // ── Test fire (preview) ──────────────────────────────────────────────────────
  Future<void> preview(Alarm alarm) => _fire(alarm);
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? elementAtOrNull(int i) => i < length ? this[i] : null;
}
