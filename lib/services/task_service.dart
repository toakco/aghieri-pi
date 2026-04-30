import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/task_model.dart';
import 'auth_service.dart';
import 'interaction_tracker.dart';

/// TaskService — CRUD for tasks.
///
/// Primary store: Firestore  `users/{uid}/tasks/{taskId}`
/// Device Pi sync is secondary (called opportunistically, never awaited).
class TaskService {
  TaskService._();
  static final instance = TaskService._();

  late final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('users').doc(AuthService.instance.uid).collection('tasks');

  // ── Helpers ────────────────────────────────────────────────────────────────

  TaskModel _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    data['id'] = doc.id;
    return TaskModel.fromJson(data);
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Today's tasks: status != complete, filtered/sorted in Dart (no index needed).
  Future<List<TaskModel>> getTodayTasks() async {
    try {
      final today = DateTime.now();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final snap = await _tasks.get();
      debugPrint('[Tasks] getTodayTasks: fetched ${snap.docs.length} docs');

      final results = snap.docs
          .map(_fromDoc)
          .where((t) => t.status != 'complete')
          .where((t) =>
              t.dueDate == null ||
              t.dueDate!.isEmpty ||
              t.dueDate!.startsWith(dateStr) ||
              t.dueDate!.compareTo(dateStr) <= 0)
          .toList()
        ..sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
      debugPrint('[Tasks] getTodayTasks: returning ${results.length} tasks');
      return results;
    } catch (e) {
      debugPrint('[Tasks] getTodayTasks error: $e');
      return [];
    }
  }

  Future<List<TaskModel>> getAllTasks() async {
    try {
      final snap = await _tasks.get();
      debugPrint('[Tasks] getAllTasks: fetched ${snap.docs.length} docs');
      final results = snap.docs.map(_fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      return results;
    } catch (e) {
      debugPrint('[Tasks] getAllTasks error: $e');
      return [];
    }
  }

  Future<List<TaskModel>> getWeekTasks() async {
    return _getTasksInRange(Duration(days: 7));
  }

  Future<List<TaskModel>> getMonthTasks() async {
    return _getTasksInRange(Duration(days: 30));
  }

  Future<List<TaskModel>> getYearTasks() async {
    return _getTasksInRange(Duration(days: 365));
  }

  Future<List<TaskModel>> _getTasksInRange(Duration range) async {
    try {
      final cutoff = DateTime.now().subtract(range).toIso8601String();
      final snap = await _tasks.get();
      final results = snap.docs
          .map(_fromDoc)
          .where((t) => (t.createdAt ?? '').compareTo(cutoff) >= 0)
          .toList()
        ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      return results;
    } catch (e) {
      debugPrint('[Tasks] _getTasksInRange error: $e');
      return [];
    }
  }

  Future<TaskModel?> getTask(String id) async {
    try {
      final doc = await _tasks.doc(id).get();
      if (doc.exists) return _fromDoc(doc);
    } catch (e) {
      debugPrint('[Tasks] getTask error: $e');
    }
    return null;
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<TaskModel?> createTask({
    required String title,
    String? color,
    String? dueDate,
    String? endDate,
    String? taskType,
    String? scheduledTime,
    String? scheduledEndTime,
    List<Map<String, dynamic>>? steps,
    int priority = 2,
    String? categoryId,
    String? subCategoryId,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final data = <String, dynamic>{
        'uid': AuthService.instance.uid,
        'title': title,
        'color': color ?? '#6AAEE8',
        'steps': steps ?? [],
        'due_date': dueDate,
        'end_date': endDate,
        'status': 'pending',
        'source': 'manual',
        'task_type': taskType ?? 'personal',
        'scheduled_time': scheduledTime,
        'scheduled_end_time': scheduledEndTime,
        'priority': priority,
        'category_id': categoryId,
        'sub_category_id': subCategoryId,
        'created_at': now,
        'current_step_index': 0,
      };
      final ref = await _tasks.add(data);
      data['id'] = ref.id;
      InteractionTracker.instance.track(InteractionType.taskCreated,
          meta: {'category': categoryId ?? taskType});
      return TaskModel.fromJson(data);
    } catch (e) {
      debugPrint('[Tasks] createTask error: $e');
      return null;
    }
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  Future<bool> updateTask(String taskId, Map<String, dynamic> fields) async {
    try {
      await _tasks.doc(taskId).update(fields);
      return true;
    } catch (e) {
      debugPrint('[Tasks] updateTask error: $e');
      return false;
    }
  }

  Future<bool> completeStep(String taskId) async {
    try {
      final doc  = await _tasks.doc(taskId).get();
      if (!doc.exists) return false;
      final task = _fromDoc(doc);

      final steps = task.steps.toList();
      final idx   = task.currentStepIndex;
      if (idx < steps.length) {
        steps[idx] = steps[idx].copyWith(completed: true);
      }
      final nextIdx = (idx + 1).clamp(0, steps.length);
      final allDone = steps.every((s) => s.completed);

      await _tasks.doc(taskId).update({
        'steps': steps.map((s) => s.toJson()).toList(),
        'current_step_index': nextIdx,
        if (allDone) 'status': 'complete',
        if (allDone) 'completed_at': DateTime.now().toIso8601String(),
      });
      InteractionTracker.instance.track(InteractionType.stepCompleted);
      if (allDone) {
        InteractionTracker.instance.track(InteractionType.taskCompleted);
      }
      return true;
    } catch (e) {
      debugPrint('[Tasks] completeStep error: $e');
      return false;
    }
  }

  Future<bool> completeTask(String taskId) async {
    try {
      await _tasks.doc(taskId).update({
        'status': 'complete',
        'completed_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('[Tasks] completeTask error: $e');
      return false;
    }
  }

  Future<bool> startFocus(String taskId) async =>
      updateTask(taskId, {'status': 'active'});

  Future<bool> endFocus(String taskId) async =>
      updateTask(taskId, {'status': 'pending'});

  Future<bool> rescheduleTask(String taskId, String newDate) async =>
      updateTask(taskId, {
        'due_date': newDate,
        'status': 'pending',
      });

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<bool> deleteTask(String taskId) async {
    try {
      await _tasks.doc(taskId).delete();
      return true;
    } catch (e) {
      debugPrint('[Tasks] deleteTask error: $e');
      return false;
    }
  }

  // ── Auto-reschedule overdue tasks ────────────────────────────────────────────

  /// Check for overdue pending tasks and mark them as needs_reschedule.
  /// Called on app launch / home screen load.
  Future<void> checkOverdueTasks() async {
    try {
      final today = DateTime.now();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final snap = await _tasks.get();

      for (final doc in snap.docs) {
        final task = _fromDoc(doc);
        if (task.status != 'pending' && task.status != 'active') continue;
        if (task.dueDate != null && task.dueDate!.compareTo(dateStr) < 0) {
          // Task is overdue — mark for reschedule
          await _tasks.doc(task.id).update({
            'status': 'needs_reschedule',
          });
        }
      }
    } catch (e) {
      debugPrint('[Tasks] checkOverdueTasks error: $e');
    }
  }

  // ── Reschedule slots (calendar fallback) ───────────────────────────────────

  Future<List<Map<String, String>>> getRescheduleSlots(
      String taskId, String title) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final d = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    return [
      {'date': '${d}T10:00:00', 'label': 'Tomorrow at 10am'},
      {'date': '${d}T15:00:00', 'label': 'Tomorrow at 3pm'},
    ];
  }
}
