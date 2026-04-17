import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// ClaudeService — routes agentic commands through the device backend.
/// The device holds the Anthropic API key; this client never touches it directly.
/// On web/demo fallback, mock responses are returned so the UI stays functional.
class ClaudeService {
  ClaudeService._();
  static final instance = ClaudeService._();

  static const _base = 'http://192.168.1.100:8000';
  bool _deviceAvailable = true;

  // ── Agentic voice command ─────────────────────────────────────────────────
  /// Send a user transcript to the device's Claude pipeline.
  /// Returns the spoken response text + any tool results.
  Future<AgentResult> sendCommand(String transcript) async {
    if (!_deviceAvailable) return _mockCommand(transcript);

    try {
      final resp = await http.post(
        Uri.parse('$_base/voice/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'transcript': transcript, 'source': 'mobile'}),
      ).timeout(const Duration(seconds: 25));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return AgentResult(
          response: data['response'] as String? ?? '',
          toolCalled: data['tool_called'] as String?,
          taskId: data['task_id'] as String?,
        );
      }
    } catch (_) {
      _deviceAvailable = false;
    }

    return _mockCommand(transcript);
  }

  // ── Generic chat ──────────────────────────────────────────────────────────
  /// Send a freeform prompt to the device's Claude pipeline.
  /// Returns the response text, or empty string on failure.
  Future<String> chat(String prompt) async {
    if (!_deviceAvailable) return '';

    try {
      final resp = await http.post(
        Uri.parse('$_base/voice/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['response'] as String? ?? '';
      }
    } catch (_) {}
    return '';
  }

  // ── Instruction parsing ───────────────────────────────────────────────────
  /// Upload text from a file/photo and return extracted tasks.
  Future<List<Map<String, dynamic>>> parseInstruction(String content, {String source = 'text'}) async {
    if (kIsWeb) {
      // On web: route through Cloud Function (server-side key). Raw HTTP avoids
      // the cloud_functions package to dodge a known Int64 dart2js bug.
      try {
        final user = FirebaseAuth.instance.currentUser;
        final token = await user?.getIdToken();
        if (token == null) return [];
        final resp = await http.post(
          Uri.parse('https://us-central1-aghieri-7a8ce.cloudfunctions.net/breakdownTask'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'data': {'content': content, 'source': source}}),
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final result = body['result'] as Map<String, dynamic>? ?? {};
          final tasks = (result['tasks'] as List?) ?? [];
          return tasks.map((t) => Map<String, dynamic>.from(t as Map)).toList();
        }
      } catch (_) {}
      return [];
    }
    try {
      final resp = await http.post(
        Uri.parse('$_base/instruction/parse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': content, 'source': source}),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final tasks = (data['tasks'] as List?) ?? [];
        return tasks.map((t) => Map<String, dynamic>.from(t as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Schedule suggestion ───────────────────────────────────────────────────
  /// Ask Claude to suggest reschedule options for an overdue task.
  Future<String> suggestReschedule(String taskTitle) async {
    if (!_deviceAvailable) {
      return 'I see $taskTitle didn\'t make it today. Would 10am or 3pm tomorrow work better?';
    }

    try {
      final resp = await http.post(
        Uri.parse('$_base/voice/reschedule-suggestion'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'task_title': taskTitle}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['suggestion'] as String? ?? '';
      }
    } catch (_) {}

    // Graceful fallback
    return '$taskTitle didn\'t get finished today. Want to find it a spot tomorrow?';
  }

  // ── Portfolio suggestions ─────────────────────────────────────────────────
  /// Request weekly UI/behavior suggestions from the device's portfolio analyzer.
  Future<List<Map<String, dynamic>>> getPortfolioSuggestions() async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/profile/suggestions'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final suggestions = (data['suggestions'] as List?) ?? [];
        return suggestions.map((s) => Map<String, dynamic>.from(s as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Special commands ──────────────────────────────────────────────────────
  Future<void> triggerLaststand() async {
    try {
      await http.post(Uri.parse('$_base/special/laststand'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> triggerOrder66() async {
    try {
      await http.post(Uri.parse('$_base/special/order66'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> triggerBumski(String currentTaskId) async {
    try {
      await http.post(
        Uri.parse('$_base/special/bumski'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'task_id': currentTaskId}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // ── Mock fallback (offline / demo mode) ───────────────────────────────────
  AgentResult _mockCommand(String transcript) {
    final lower = transcript.toLowerCase();

    if (lower.contains('add') || lower.contains('create') || lower.contains('new task')) {
      return const AgentResult(
        response: 'I\'ve added that to your list.',
        toolCalled: 'create_task',
      );
    }
    if (lower.contains('complete') || lower.contains('done') || lower.contains('finish')) {
      return const AgentResult(
        response: 'Marked as done. Well done.',
        toolCalled: 'complete_task',
      );
    }
    if (lower.contains('today') || lower.contains('what\'s on')) {
      return const AgentResult(
        response: 'Let me pull up your tasks for today.',
        toolCalled: 'get_todays_tasks',
      );
    }
    if (lower.contains('aquarium') || lower.contains('fish')) {
      return const AgentResult(
        response: 'Opening the aquarium.',
        toolCalled: 'open_aquarium',
      );
    }

    return const AgentResult(
      response: 'I\'m here. The device isn\'t connected right now, but I heard you.',
    );
  }
}

// ── Result model ──────────────────────────────────────────────────────────────

class AgentResult {
  final String response;
  final String? toolCalled;
  final String? taskId;

  const AgentResult({
    required this.response,
    this.toolCalled,
    this.taskId,
  });
}

// ── Special command detector ───────────────────────────────────────────────────

/// Checks a transcript for special power commands.
/// Returns null if no command matched.
SpecialCommand? detectSpecialCommand(String transcript) {
  final t = transcript.trim().toLowerCase();
  if (t == '/laststand' || t == 'laststand' || t == 'last stand') {
    return SpecialCommand.laststand;
  }
  if (t == 'order 66' || t == 'order66') {
    return SpecialCommand.order66;
  }
  if (t == '/bumski' || t == 'bumski') {
    return SpecialCommand.bumski;
  }
  if (t == '/aquarium' || t == 'aquarium mode') {
    return SpecialCommand.aquarium;
  }
  return null;
}

enum SpecialCommand { laststand, order66, bumski, aquarium }
