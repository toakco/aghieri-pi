import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  // ── Spotify ───────────────────────────────────────────────────────────────
  bool get isSpotifyConnected => _spotifyConnected;

  Future<void> disconnectSpotify() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('spotify_connected', false);
    _spotifyConnected = false;
    _broadcast();
  }

  /// Fetch the user's Spotify playlists using the stored access token.
  Future<List<SpotifyPlaylistItem>> getUserSpotifyPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('spotify_access_token');
    if (token == null || token.isEmpty) return [];

    try {
      final resp = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/playlists?limit=50'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? [];
      return items.map((item) => SpotifyPlaylistItem(
        id: item['id'] as String? ?? '',
        name: item['name'] as String? ?? '',
        imageUrl: ((item['images'] as List?)?.firstOrNull?['url']) as String?,
      )).where((p) => p.id.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[MusicService] Spotify playlists error: $e');
      return [];
    }
  }

  /// Start Spotify playback for a playlist URI via Spotify Connect Web API.
  Future<void> playSpotifyPlaylist(String playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('spotify_access_token');
    if (token == null || token.isEmpty) {
      // Fallback to local ambient tracks
      await startWakeUpFadeIn();
      return;
    }

    try {
      // Get active device ID
      final devResp = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/devices'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));

      String? deviceId;
      if (devResp.statusCode == 200) {
        final devData = jsonDecode(devResp.body) as Map<String, dynamic>;
        final devices = (devData['devices'] as List?) ?? [];
        final active = devices.firstWhere(
          (d) => d['is_active'] == true,
          orElse: () => devices.isNotEmpty ? devices.first : null,
        );
        deviceId = active?['id'] as String?;
      }

      final uri = playlistId.startsWith('spotify:')
          ? playlistId
          : 'spotify:playlist:$playlistId';

      final body = jsonEncode({'context_uri': uri});
      final playUrl = deviceId != null
          ? 'https://api.spotify.com/v1/me/player/play?device_id=$deviceId'
          : 'https://api.spotify.com/v1/me/player/play';

      await http.put(
        Uri.parse(playUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 8));

      _currentTrack = 'Spotify';
      _currentArtist = '';
      _isPlaying = true;
      _broadcast();
    } catch (e) {
      debugPrint('[MusicService] Spotify play error: $e — falling back to ambient');
      await startWakeUpFadeIn();
    }
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

class SpotifyPlaylistItem {
  final String id;
  final String name;
  final String? imageUrl;
  const SpotifyPlaylistItem({required this.id, required this.name, this.imageUrl});
}

extension _ListFirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
