import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MusicService — ambient audio controller for Aghieri.
///
/// Manages playback ducking during voice interactions, auto-play
/// during focus sessions, and pre-wake fade-in.
///
/// Spotify OAuth and yt-dlp Cloud Function are planned but not yet wired.
/// Currently plays from a curated set of ambient audio URLs.
class MusicService {
  MusicService._();
  static final instance = MusicService._();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  double _targetVolume = 0.5;
  double _currentVolume = 0.5;
  Timer? _fadeTimer;
  Timer? _duckTimer;

  // Now-playing state
  String _currentTrack = '';
  String _currentArtist = '';
  bool _spotifyConnected = false;

  // ── Broadcast ───────────────────────────────────────────────────────────────
  final _stateCtrl = StreamController<MusicState>.broadcast();
  Stream<MusicState> get stateStream => _stateCtrl.stream;
  MusicState get currentState => MusicState(
    isPlaying: _isPlaying,
    track: _currentTrack,
    artist: _currentArtist,
    volume: _currentVolume,
    spotifyConnected: _spotifyConnected,
  );

  // ── Ambient tracks (royalty-free, curated for ADHD focus) ──────────────────
  static const _focusTracks = [
    _Track('Ambient Focus', 'Aghieri', 'https://cdn.pixabay.com/audio/2024/01/10/audio_29b0bfe3fd.mp3'),
    _Track('Deep Work', 'Aghieri', 'https://cdn.pixabay.com/audio/2023/10/30/audio_e4e0eef7d5.mp3'),
    _Track('Flow State', 'Aghieri', 'https://cdn.pixabay.com/audio/2024/02/14/audio_d4c4a8f4b0.mp3'),
  ];

  static const _wakeUpTracks = [
    _Track('Morning Light', 'Aghieri', 'https://cdn.pixabay.com/audio/2024/03/04/audio_d1a2b3c4e5.mp3'),
  ];

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _spotifyConnected = prefs.getBool('spotify_connected') ?? false;
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _broadcast();
    });
  }

  void dispose() {
    _fadeTimer?.cancel();
    _duckTimer?.cancel();
    _player.dispose();
    _stateCtrl.close();
  }

  // ── Playback ───────────────────────────────────────────────────────────────
  Future<void> play({String? url, String? track, String? artist}) async {
    try {
      if (url != null) {
        await _player.setUrl(url);
      }
      _currentTrack = track ?? _currentTrack;
      _currentArtist = artist ?? _currentArtist;
      await _player.setVolume(_currentVolume);
      await _player.play();
      _broadcast();
    } catch (e) {
      debugPrint('[MusicService] Play error: $e');
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _broadcast();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentTrack = '';
    _currentArtist = '';
    _broadcast();
  }

  Future<void> setVolume(double vol) async {
    _currentVolume = vol.clamp(0.0, 1.0);
    _targetVolume = _currentVolume;
    await _player.setVolume(_currentVolume);
    _broadcast();
  }

  // ── Focus mode auto-play ──────────────────────────────────────────────────
  Future<void> startFocusPlayback() async {
    final track = (_focusTracks.toList()..shuffle()).first;
    _currentVolume = 0.5;
    _targetVolume = 0.5;
    await play(url: track.url, track: track.name, artist: track.artist);
    // Loop focus audio
    _player.setLoopMode(LoopMode.one);
  }

  Future<void> stopFocusPlayback() async {
    _fadeTo(0.0, duration: const Duration(seconds: 2));
    await Future.delayed(const Duration(seconds: 2));
    await stop();
    _player.setLoopMode(LoopMode.off);
  }

  // ── Wake-up fade-in (5 min before alarm) ──────────────────────────────────
  Future<void> startWakeUpFadeIn() async {
    final track = _wakeUpTracks.first;
    _currentVolume = 0.1;
    await _player.setVolume(0.1);
    await play(url: track.url, track: track.name, artist: track.artist);
    _player.setLoopMode(LoopMode.one);
    // Fade from 10% to 60% over 5 minutes (300 seconds)
    _fadeTo(0.6, duration: const Duration(minutes: 5));
  }

  // ── Voice ducking ─────────────────────────────────────────────────────────
  /// Duck volume to 15% over 200ms when voice is active.
  void duckForVoice() {
    _duckTimer?.cancel();
    _targetVolume = _currentVolume;
    _fadeTo(0.15, duration: const Duration(milliseconds: 200));
  }

  /// Restore volume after 1s of voice idle.
  void restoreAfterVoice() {
    _duckTimer?.cancel();
    _duckTimer = Timer(const Duration(seconds: 1), () {
      _fadeTo(_targetVolume, duration: const Duration(milliseconds: 400));
    });
  }

  // ── Wind-down (30 min before sleep) ──────────────────────────────────────
  Future<void> startWindDown() async {
    // Play current track but fade to zero over 30 minutes
    _fadeTo(0.0, duration: const Duration(minutes: 30));
  }

  // ── Fade utility ──────────────────────────────────────────────────────────
  void _fadeTo(double target, {required Duration duration}) {
    _fadeTimer?.cancel();
    final start = _currentVolume;
    final diff = target - start;
    const stepMs = 100;
    final steps = (duration.inMilliseconds / stepMs).ceil();
    int step = 0;

    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (timer) {
      step++;
      if (step >= steps) {
        _currentVolume = target;
        _player.setVolume(_currentVolume);
        timer.cancel();
        _broadcast();
        return;
      }
      _currentVolume = start + diff * (step / steps);
      _player.setVolume(_currentVolume);
    });
  }

  // ── Music intent classification (from voice commands) ─────────────────────
  /// Parse a voice transcript for music intents.
  /// Returns the action to take, or null if no music intent detected.
  MusicIntent? classifyIntent(String transcript) {
    final t = transcript.toLowerCase().trim();

    if (t.contains('play') && !t.contains('pause')) return MusicIntent.play;
    if (t.contains('pause') || t.contains('stop music')) return MusicIntent.pause;
    if (t.contains('next') || t.contains('skip')) return MusicIntent.next;
    if (t.contains('previous') || t.contains('go back')) return MusicIntent.previous;
    if (t.contains('volume up') || t.contains('louder')) return MusicIntent.volumeUp;
    if (t.contains('volume down') || t.contains('quieter') || t.contains('softer')) {
      return MusicIntent.volumeDown;
    }
    if (t.contains('calmer') || t.contains('chill') || t.contains('relax')) {
      return MusicIntent.playCalmer;
    }
    if (t.contains('upbeat') || t.contains('energize') || t.contains('energy')) {
      return MusicIntent.playUpbeat;
    }

    return null;
  }

  /// Execute a classified music intent.
  Future<void> executeIntent(MusicIntent intent) async {
    switch (intent) {
      case MusicIntent.play:
        if (!_isPlaying) await startFocusPlayback();
        break;
      case MusicIntent.pause:
        await pause();
        break;
      case MusicIntent.next:
      case MusicIntent.previous:
        // Shuffle to next/previous track
        await startFocusPlayback();
        break;
      case MusicIntent.volumeUp:
        await setVolume(_currentVolume + 0.15);
        break;
      case MusicIntent.volumeDown:
        await setVolume(_currentVolume - 0.15);
        break;
      case MusicIntent.playCalmer:
      case MusicIntent.playUpbeat:
        // Same tracks for now — Spotify integration will differentiate
        await startFocusPlayback();
        break;
    }
  }

  // ── Spotify (placeholder) ─────────────────────────────────────────────────
  bool get isSpotifyConnected => _spotifyConnected;

  Future<void> connectSpotify() async {
    // OAuth flow would go here — requires redirect URI setup
    debugPrint('[MusicService] Spotify OAuth not yet implemented');
  }

  Future<void> disconnectSpotify() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('spotify_connected', false);
    _spotifyConnected = false;
    _broadcast();
  }

  void _broadcast() {
    _stateCtrl.add(currentState);
  }
}

// ── Models ──────────────────────────────────────────────────────────────────

class MusicState {
  final bool isPlaying;
  final String track;
  final String artist;
  final double volume;
  final bool spotifyConnected;

  const MusicState({
    this.isPlaying = false,
    this.track = '',
    this.artist = '',
    this.volume = 0.5,
    this.spotifyConnected = false,
  });
}

enum MusicIntent {
  play, pause, next, previous,
  volumeUp, volumeDown,
  playCalmer, playUpbeat,
}

class _Track {
  final String name;
  final String artist;
  final String url;
  const _Track(this.name, this.artist, this.url);
}
