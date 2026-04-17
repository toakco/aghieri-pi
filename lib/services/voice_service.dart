import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'auth_service.dart';
import 'interaction_tracker.dart';
import 'task_service.dart';
import 'web_audio_stub.dart' if (dart.library.html) 'web_audio.dart';

enum ConnectivityStatus { online, deviceOnline, offline }

/// Voice pipeline state — drives the outer ring animation.
enum VoiceState { idle, listening, thinking, responding }

/// VoiceService — STT + TTS + wake word + agentic command routing.
///
/// TTS priority chain:
///   (1) ElevenLabs direct API (if key is set)
///   (2) Device FastAPI /voice/tts (Pi, uses ElevenLabs server-side)
///   (3) Browser SpeechSynthesis fallback
///
/// Command priority chain:
///   (1) Device FastAPI /voice/command
///   (2) Claude API direct (claude-haiku)
///   (3) Offline stub
class VoiceService {
  VoiceService._();
  static final instance = VoiceService._();

  // ── Config keys ────────────────────────────────────────────────────────────
  static const _prefKeyClaudeKey      = 'claude_api_key';
  static const _prefKeyDeviceIp       = 'device_ip';
  static const _prefKeyElevenLabsKey  = 'elevenlabs_api_key';
  static const _prefKeyVoiceId        = 'elevenlabs_voice_id';

  static const _claudeEndpoint   = 'https://api.anthropic.com/v1/messages';
  static const _elevenLabsBase   = 'https://api.elevenlabs.io/v1';
  static const _functionsBase    = 'https://us-central1-aghieri-7a8ce.cloudfunctions.net';

  // Built-in voice presets — id → display name
  static const Map<String, String> voicePresets = {
    'iLVmqjzCGGvqtMCk6vVQ': 'Antonio — lively, engaging',
  };
  static const _defaultVoiceId = 'iLVmqjzCGGvqtMCk6vVQ'; // Antonio

  // ── State ─────────────────────────────────────────────────────────────────
  String _deviceUrl       = 'http://192.168.1.100:8000';
  String _claudeApiKey    = '';
  String _elevenLabsKey   = '';
  String _voiceId         = _defaultVoiceId;

  bool? _deviceReachable;
  bool _networkAvailable  = true;
  StreamSubscription? _connectSub;

  final _stt    = SpeechToText();
  AudioPlayer _player = AudioPlayer();
  final _flutterTts = FlutterTts();
  bool _sttReady = false;
  bool _ttsInitialized = false;

  void _resetPlayer() {
    _player = AudioPlayer();
  }

  /// Unlock audio on iOS Safari — must be called during a user gesture.
  /// This primes speechSynthesis and AudioContext so subsequent async calls work.
  Future<void> unlockAudio() async {
    if (!kIsWeb) return;
    try {
      // Prime flutter_tts / speechSynthesis with a silent utterance
      await _flutterTts.setVolume(0.01);
      await _flutterTts.speak(' ');
      await Future.delayed(const Duration(milliseconds: 100));
      await _flutterTts.setVolume(1.0);
      _ttsInitialized = true;
      debugPrint('[VoiceService] Audio unlocked for iOS Safari');
    } catch (e) {
      debugPrint('[VoiceService] Audio unlock error: $e');
    }
  }

  /// Play audio bytes on web using Blob URL (works on iOS Safari).
  Future<bool> _playAudioBytesWeb(Uint8List bytes) async {
    if (!kIsWeb) return false;
    try {
      return await playAudioBytes(bytes);
    } catch (e) {
      debugPrint('[VoiceService] Web audio playback error: $e');
      return false;
    }
  }

  // Wake word
  bool _wakeWordActive = false;
  void Function()? _onWakeWord;

  // Status broadcast
  final _statusCtrl = StreamController<ConnectivityStatus>.broadcast();
  Stream<ConnectivityStatus> get statusStream => _statusCtrl.stream;
  ConnectivityStatus get currentStatus => _lastStatus;
  ConnectivityStatus _lastStatus = ConnectivityStatus.online;

  // Voice state broadcast — drives outer ring animation
  final _voiceStateCtrl = StreamController<VoiceState>.broadcast();
  Stream<VoiceState> get voiceStateStream => _voiceStateCtrl.stream;
  VoiceState get currentVoiceState => _voiceState;
  VoiceState _voiceState = VoiceState.idle;

  void _setVoiceState(VoiceState state) {
    if (_voiceState == state) return;
    _voiceState = state;
    _voiceStateCtrl.add(state);
  }

  // Expose current voice id for UI
  String get voiceId => _voiceId;

  // Conversation history for multi-turn voice sessions
  final List<Map<String, String>> _conversationHistory = [];

  /// Clear conversation history (call when voice session ends).
  void clearConversation() => _conversationHistory.clear();

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _claudeApiKey  = prefs.getString(_prefKeyClaudeKey)     ?? '';
    _elevenLabsKey = prefs.getString(_prefKeyElevenLabsKey) ?? '';
    _voiceId       = prefs.getString(_prefKeyVoiceId)       ?? _defaultVoiceId;
    final savedIp  = prefs.getString(_prefKeyDeviceIp);
    if (savedIp != null && savedIp.isNotEmpty) {
      _deviceUrl = 'http://$savedIp:8000';
    }

    // Restore from Firestore if local keys are empty (survives reinstall)
    if (_claudeApiKey.isEmpty || _elevenLabsKey.isEmpty) {
      await _restoreKeysFromFirestore(prefs);
    }

    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile);
      _networkAvailable = hasNet;
      _deviceReachable  = null;
      _lastStatus = hasNet ? ConnectivityStatus.online : ConnectivityStatus.offline;
      _statusCtrl.add(_lastStatus);
    });
  }

  /// Restore API keys from Firestore (backup, survives app reinstall).
  Future<void> _restoreKeysFromFirestore(SharedPreferences prefs) async {
    try {
      final uid = AuthService.instance.uid;
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return;
      final keys = data['api_keys'] as Map<String, dynamic>?;
      if (keys == null) return;

      if (_claudeApiKey.isEmpty && keys['claude'] != null) {
        _claudeApiKey = keys['claude'] as String;
        await prefs.setString(_prefKeyClaudeKey, _claudeApiKey);
        debugPrint('[VoiceService] Restored Claude key from Firestore');
      }
      if (_elevenLabsKey.isEmpty && keys['elevenlabs'] != null) {
        _elevenLabsKey = keys['elevenlabs'] as String;
        await prefs.setString(_prefKeyElevenLabsKey, _elevenLabsKey);
        debugPrint('[VoiceService] Restored ElevenLabs key from Firestore');
      }
      if (keys['device_ip'] != null) {
        final ip = keys['device_ip'] as String;
        _deviceUrl = 'http://$ip:8000';
        await prefs.setString(_prefKeyDeviceIp, ip);
      }
    } catch (e) {
      debugPrint('[VoiceService] Firestore key restore error: $e');
    }
  }

  /// Backup API keys to Firestore.
  Future<void> _backupKeysToFirestore() async {
    try {
      final uid = AuthService.instance.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'api_keys': {
          if (_claudeApiKey.isNotEmpty) 'claude': _claudeApiKey,
          if (_elevenLabsKey.isNotEmpty) 'elevenlabs': _elevenLabsKey,
          'device_ip': _deviceUrl.replaceAll('http://', '').replaceAll(':8000', ''),
          'voice_id': _voiceId,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[VoiceService] Firestore key backup error: $e');
    }
  }

  void disposeService() {
    stopWakeWordListening();
    _connectSub?.cancel();
    _statusCtrl.close();
    _voiceStateCtrl.close();
  }

  /// Call a Firebase callable function via raw HTTP (avoids cloud_functions
  /// package Int64 dart2js bug on web).
  Future<Map<String, dynamic>> _callFunction(
      String name, Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null) throw Exception('Not authenticated');

    final resp = await http.post(
      Uri.parse('$_functionsBase/$name'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'data': data}),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (body['result'] as Map<String, dynamic>?) ?? {};
    } else {
      debugPrint('[VoiceService] Cloud Function $name error: ${resp.statusCode} ${resp.body}');
      throw Exception('Cloud Function $name failed: ${resp.statusCode}');
    }
  }

  // ── Configure ──────────────────────────────────────────────────────────────
  Future<void> configure({
    String? claudeApiKey,
    String? deviceIp,
    String? elevenLabsKey,
    String? voiceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (claudeApiKey != null) {
      _claudeApiKey = claudeApiKey;
      await prefs.setString(_prefKeyClaudeKey, claudeApiKey);
    }
    if (deviceIp != null) {
      _deviceUrl = 'http://$deviceIp:8000';
      await prefs.setString(_prefKeyDeviceIp, deviceIp);
      _deviceReachable = null;
    }
    if (elevenLabsKey != null) {
      _elevenLabsKey = elevenLabsKey;
      await prefs.setString(_prefKeyElevenLabsKey, elevenLabsKey);
    }
    if (voiceId != null) {
      _voiceId = voiceId;
      await prefs.setString(_prefKeyVoiceId, voiceId);
    }

    // Backup to Firestore so keys survive reinstall
    _backupKeysToFirestore();
  }

  // ── Device ping ────────────────────────────────────────────────────────────
  Future<bool> _checkDevice() async {
    if (kIsWeb) return false; // No local device on web — skip ping entirely
    if (!_networkAvailable) return false;
    if (_deviceReachable != null) return _deviceReachable!;
    try {
      final resp = await http.get(Uri.parse('$_deviceUrl/health'))
          .timeout(const Duration(seconds: 3));
      _deviceReachable = resp.statusCode == 200;
    } catch (_) {
      _deviceReachable = false;
    }
    if (_deviceReachable == true) {
      _lastStatus = ConnectivityStatus.deviceOnline;
      _statusCtrl.add(_lastStatus);
    }
    Future.delayed(const Duration(seconds: 60), () => _deviceReachable = null);
    return _deviceReachable!;
  }

  // ── STT ────────────────────────────────────────────────────────────────────
  Future<String> listen({
    void Function(String)? onInterim,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Stop any playing audio first — iOS Safari can't share audio session
    try { await _player.stop(); } catch (_) {}
    try { await _player.dispose(); } catch (_) {}
    // Recreate player for next TTS use (avoids stale audio session on iOS)
    _resetPlayer();

    // On web, re-initialize STT each time — iOS Safari drops the session
    if (kIsWeb) {
      _sttReady = false;
    }

    if (!_sttReady) {
      _sttReady = await _stt.initialize(
        onError: (e) => debugPrint('[VoiceService] STT error: ${e.errorMsg}'),
        onStatus: (s) => debugPrint('[VoiceService] STT status: $s'),
      );
    }
    if (!_sttReady) {
      debugPrint('[VoiceService] STT failed to initialize');
      return '';
    }

    // Clean stop before re-listen
    try { await _stt.stop(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));

    _setVoiceState(VoiceState.listening);

    final completer = Completer<String>();
    String last = '';

    try {
      await _stt.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            last = result.recognizedWords;
            if (!result.finalResult) onInterim?.call(last);
            if (result.finalResult) {
              _stt.stop();
              if (!completer.isCompleted) completer.complete(last);
            }
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(milliseconds: 1200),
        localeId: 'en_US',
      );
    } catch (e) {
      debugPrint('[VoiceService] STT listen error: $e');
      if (!completer.isCompleted) completer.complete('');
    }

    return completer.future.timeout(timeout, onTimeout: () {
      _stt.stop();
      _setVoiceState(VoiceState.idle);
      return last;
    });
  }

  Future<void> stop() async {
    await _stt.stop();
    _setVoiceState(VoiceState.idle);
  }

  // ── TTS ────────────────────────────────────────────────────────────────────
  /// Speak text.
  /// On mobile web (iOS Safari): use native TTS directly (most reliable).
  /// On desktop web: ElevenLabs via Cloud Function → native fallback.
  /// On native mobile: ElevenLabs direct → device → native.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    _setVoiceState(VoiceState.responding);

    // Mobile web (iPhone Safari) — go straight to native TTS, it's the only
    // thing that reliably works. ElevenLabs audio playback fails on iOS Safari.
    if (kIsWeb) {
      // Try ElevenLabs via Cloud Function first (server-side key)
      try {
        final ok = await _speakElevenLabs(text);
        if (ok) return;
      } catch (_) {}
      // Always fall back to native browser TTS
      await _speakNative(text);
      return;
    }

    // Native mobile app path
    if (_elevenLabsKey.isNotEmpty) {
      final ok = await _speakElevenLabs(text);
      if (ok) return;
    }

    final deviceUp = await _checkDevice();
    if (deviceUp) {
      final ok = await _speakDevice(text);
      if (ok) return;
    }

    await _speakNative(text);
  }

  /// Call ElevenLabs API and play the audio.
  /// On web, routes through Firebase Cloud Function to bypass CORS.
  Future<bool> _speakElevenLabs(String text) async {
    try {
      Uint8List audioBytes;

      if (kIsWeb) {
        // ── Web: proxy through Cloud Function via HTTP ──
        final result = await _callFunction('textToSpeech', {
          'text': text,
          'voiceId': _voiceId,
          'elevenLabsKey': _elevenLabsKey,
        });
        final base64Audio = result['audio'] as String?;
        if (base64Audio == null || base64Audio.isEmpty) return false;
        audioBytes = base64Decode(base64Audio);
      } else {
        // ── Mobile: direct API call ──
        final resp = await http.post(
          Uri.parse('$_elevenLabsBase/text-to-speech/$_voiceId'),
          headers: {
            'xi-api-key': _elevenLabsKey,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          body: jsonEncode({
            'text': text,
            'model_id': 'eleven_multilingual_v2',
            'voice_settings': {
              'stability': 0.55,
              'similarity_boost': 0.75,
              'style': 0.10,
              'use_speaker_boost': true,
            },
          }),
        ).timeout(const Duration(seconds: 20));

        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          debugPrint('[VoiceService] ElevenLabs TTS error ${resp.statusCode}: ${resp.body}');
          return false;
        }
        audioBytes = resp.bodyBytes;
      }

      if (kIsWeb) {
        // On web/iOS Safari, use Blob URL audio playback
        final ok = await _playAudioBytesWeb(audioBytes);
        return ok;
      }

      // Native mobile — use just_audio
      _player = AudioPlayer();
      final dataUri = Uri.dataFromBytes(audioBytes, mimeType: 'audio/mpeg');
      await _player.setAudioSource(AudioSource.uri(dataUri));
      await _player.play();
      return true;
    } catch (e) {
      debugPrint('[VoiceService] ElevenLabs TTS exception: $e');
    }
    return false;
  }

  Future<bool> _speakDevice(String text) async {
    try {
      final resp = await http.post(
        Uri.parse('$_deviceUrl/voice/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'cache': true}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        await _player.stop();
        await _player.setAudioSource(
          AudioSource.uri(Uri.dataFromBytes(resp.bodyBytes, mimeType: 'audio/mpeg')),
        );
        await _player.play();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _speakNative(String text) async {
    try {
      if (!_ttsInitialized) {
        await _flutterTts.setLanguage('en-US');
        await _flutterTts.setSpeechRate(0.45);
        await _flutterTts.setPitch(0.95);
        await _flutterTts.setVolume(1.0);
        _ttsInitialized = true;
      }

      // Wait for speech to complete before returning
      final completer = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
      });
      _flutterTts.setErrorHandler((msg) {
        debugPrint('[VoiceService] Native TTS error: $msg');
        if (!completer.isCompleted) completer.complete();
      });

      await _flutterTts.speak(text);
      await completer.future.timeout(
        Duration(milliseconds: (text.length * 100).clamp(2000, 15000)),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('[VoiceService] Native TTS exception: $e');
    }
  }

  // ── Wake word ──────────────────────────────────────────────────────────────
  /// Start continuous background listening for "Aghieri" (or "Hey Aghieri").
  /// When detected, [onWakeWord] is called and listening pauses for 5s
  /// (giving time for the command listener to start).
  void startWakeWordListening({required void Function() onWakeWord}) {
    _onWakeWord = onWakeWord;
    _wakeWordActive = true;
    _startWakeLoop();
  }

  void stopWakeWordListening() {
    _wakeWordActive = false;
    _stt.stop();
  }

  Future<void> _startWakeLoop() async {
    if (!_wakeWordActive) return;

    if (!_sttReady) {
      _sttReady = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    }
    if (!_sttReady || !_wakeWordActive) return;

    try {
      await _stt.listen(
        onResult: (result) {
          if (!_wakeWordActive) return;
          final raw = result.recognizedWords.toLowerCase();
          if (_containsWakeName(raw)) {
            _wakeWordActive = false;
            _stt.stop();
            _onWakeWord?.call();
            Future.delayed(const Duration(seconds: 5), () {
              if (!_wakeWordActive) {
                _wakeWordActive = true;
                _startWakeLoop();
              }
            });
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        localeId: 'en_US',
      );
    } catch (_) {}

    Future.delayed(const Duration(milliseconds: 500), () {
      if (_wakeWordActive) _startWakeLoop();
    });
  }

  bool _containsWakeName(String transcript) {
    // Accept common mis-transcriptions of "Aghieri"
    const variants = [
      'aghieri', 'agieri', 'ajieri', 'agyeri',
      'alighieri', 'ali jeri',
      'hey aghieri', 'hey agieri',
    ];
    return variants.any((v) => transcript.contains(v));
  }

  // ── Task type → hex color ───────────────────────────────────────────────────
  static const _taskTypeColorHex = {
    'homework': '#A0D8EF',
    'project':  '#D2B48C',
    'study':    '#96C8A2',
    'meeting':  '#CD79DD',
    'lab':      '#A4FFCA',
    'reading':  '#96C8A2',
    'exam':     '#4A90E2',
    'personal': '#88D498',
    'work':     '#A0D8EF',
  };

  // ── Agentic command ────────────────────────────────────────────────────────
  Future<String> sendCommand(String transcript, {String? taskContext}) async {
    if (transcript.trim().isEmpty) return '';
    _setVoiceState(VoiceState.thinking);
    InteractionTracker.instance.track(InteractionType.voiceCommand);

    // If we're in focus on a specific task, wrap the transcript with context
    // so Claude can give task-specific guidance instead of generic chat.
    final effectiveTranscript = taskContext != null && taskContext.isNotEmpty
        ? '$taskContext\n\nUser question: $transcript'
        : transcript;

    final deviceUp = await _checkDevice();

    if (deviceUp) {
      final result = await _commandDevice(effectiveTranscript);
      if (result.isNotEmpty) {
        _setVoiceState(VoiceState.idle);
        return result;
      }
    }

    if (kIsWeb || _claudeApiKey.isNotEmpty) {
      final result = await _commandClaude(effectiveTranscript);
      if (result.isNotEmpty) {
        // Check if Claude returned a task-creation JSON action
        final handled = await _tryHandleTaskAction(result);
        if (handled != null) {
          await speak(handled);
          _setVoiceState(VoiceState.idle);
          return handled;
        }
        await speak(result);
        _setVoiceState(VoiceState.idle);
        return result;
      }
    }

    const fallback = "I couldn't reach the server right now. "
        "Your request has been noted — I'll sync when we reconnect.";
    await _speakNative(fallback);
    _setVoiceState(VoiceState.idle);
    return fallback;
  }

  /// If [response] contains a create_task JSON action, parse it, create the
  /// task, and return a spoken confirmation. Returns null if not a task action.
  Future<String?> _tryHandleTaskAction(String response) async {
    // Find JSON anywhere in the response
    final jsonMatch = RegExp(r'\{[^{}]*"action"\s*:\s*"create_task"[^{}]*\}')
        .firstMatch(response);
    if (jsonMatch == null) return null;

    try {
      final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      if (json['action'] != 'create_task') return null;

      final title = json['title'] as String? ?? '';
      if (title.isEmpty) return null;

      final taskType = json['taskType'] as String? ?? 'personal';
      final dueDate = json['dueDate'] as String?;
      final scheduledTime = json['scheduledTime'] as String?;
      final color = _taskTypeColorHex[taskType] ?? '#88D498';

      final task = await TaskService.instance.createTask(
        title: title,
        color: color,
        dueDate: dueDate,
        taskType: taskType,
        scheduledTime: scheduledTime,
      );

      if (task != null) {
        return "Done. I've added $title to your tasks.";
      } else {
        return "I understood the task, but something went wrong saving it. Try again in a moment.";
      }
    } catch (e) {
      debugPrint('[VoiceService] Task action parse error: $e');
      return null; // Not valid JSON or not a task action — treat as conversation
    }
  }

  Future<String> _commandDevice(String transcript) async {
    try {
      final resp = await http.post(
        Uri.parse('$_deviceUrl/voice/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'transcript': transcript}),
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data     = jsonDecode(resp.body) as Map<String, dynamic>;
        final response = (data['response'] as String?) ?? '';
        if (response.isNotEmpty) await _speakDevice(response);
        return response;
      }
    } catch (_) {}
    return '';
  }

  String get _systemPrompt {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return 'You are Aghieri, a calm ADHD productivity companion. '
        'Keep responses short, warm, and unhurried. No exclamation points. '
        'No urgency language. Speak in natural, short sentences.\n\n'
        'TASK CREATION RULES:\n'
        'When the user wants to create or add a task:\n'
        '1. If they give you a title in their message, you already have a title. Do NOT re-ask for it.\n'
        '2. Ask only ONE follow-up question at a time for missing info: type, due date, or time.\n'
        '3. Valid types: homework, project, study, meeting, lab, reading, exam, personal, work.\n'
        '4. If the user says "skip", "no", "none", "that\'s it", or similar for any field, move on.\n'
        '5. After at most 3 exchanges (or sooner if you have title + type), CREATE the task immediately.\n'
        '6. To create, output ONLY this JSON with no other text:\n'
        '{"action":"create_task","title":"...","taskType":"...","dueDate":"YYYY-MM-DD","scheduledTime":"HH:mm"}\n'
        '7. Omit dueDate/scheduledTime if not provided. Default taskType to "personal" if unclear.\n'
        '8. IMPORTANT: Do not keep asking questions forever. Be decisive. Create the task quickly.\n'
        'Today is $today.\n\n'
        'For anything that is not task creation, respond normally as conversation.';
  }

  Future<String> _commandClaude(String transcript) async {
    // Add user message to history
    _conversationHistory.add({'role': 'user', 'content': transcript});

    try {
      String responseText = '';

      if (kIsWeb) {
        // ── Web: proxy through Cloud Function via HTTP ──
        final result = await _callFunction('voiceCommand', {
          'messages': _conversationHistory,
          'claudeKey': _claudeApiKey,
        });
        responseText = (result['response'] as String?) ?? '';
      } else {
        // ── Mobile: direct API call ──
        final resp = await http.post(
          Uri.parse(_claudeEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': _claudeApiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': 'claude-haiku-4-5-20251001',
            'max_tokens': 256,
            'system': _systemPrompt,
            'messages': _conversationHistory,
          }),
        ).timeout(const Duration(seconds: 20));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          responseText = ((data['content'] as List?)?.first as Map?)?['text'] as String? ?? '';
        } else {
          debugPrint('[VoiceService] Claude API error ${resp.statusCode}: ${resp.body}');
        }
      }

      // Add assistant response to history
      if (responseText.isNotEmpty) {
        _conversationHistory.add({'role': 'assistant', 'content': responseText});
        // Keep history manageable (last 20 messages)
        if (_conversationHistory.length > 20) {
          _conversationHistory.removeRange(0, _conversationHistory.length - 20);
        }
      }

      return responseText;
    } catch (e) {
      debugPrint('[VoiceService] Claude API exception: $e');
      return '';
    }
  }

  Future<String> askClaude(String question) async {
    final deviceUp = await _checkDevice();
    if (deviceUp) {
      try {
        final resp = await http.post(
          Uri.parse('$_deviceUrl/voice/ask'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'question': question}),
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          return (jsonDecode(resp.body)['answer'] as String?) ?? '';
        }
      } catch (_) {}
    }
    if (kIsWeb || _claudeApiKey.isNotEmpty) return _commandClaude(question);
    return '';
  }
}
