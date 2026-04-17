import 'package:flutter/material.dart';

class TaskStep {
  final String id;
  final String text;
  final bool completed;

  const TaskStep({required this.id, required this.text, this.completed = false});

  factory TaskStep.fromJson(Map<String, dynamic> j) => TaskStep(
    id: j['id'] ?? '',
    text: j['text'] ?? '',
    completed: j['completed'] ?? false,
  );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'completed': completed};

  TaskStep copyWith({bool? completed}) =>
    TaskStep(id: id, text: text, completed: completed ?? this.completed);
}


class TaskModel {
  final String id;
  final String? uid;
  final String title;
  final Color color;
  final List<TaskStep> steps;
  final String? dueDate;
  final String? endDate;       // for multi-day tasks — last day of the range
  final String status;        // pending | active | complete | deferred | needs_reschedule
  final String source;        // manual | voice | upload | calendar | notion
  final String taskType;      // homework | project | study | meeting | lab | reading | exam | personal | work
  final String? scheduledTime;    // '14:00' — when during the day this task starts
  final String? scheduledEndTime; // '15:30' — when this task ends
  final String? categoryId;
  final String? subCategoryId;
  final int priority;          // 1 = low, 2 = medium, 3 = high
  final String? calendarEventId;
  final String? notionPageId;
  final String createdAt;
  final String? completedAt;
  final int currentStepIndex;

  const TaskModel({
    required this.id,
    this.uid,
    required this.title,
    required this.color,
    this.steps = const [],
    this.dueDate,
    this.endDate,
    this.status = 'pending',
    this.source = 'manual',
    this.taskType = 'personal',
    this.scheduledTime,
    this.scheduledEndTime,
    this.priority = 2,
    this.categoryId,
    this.subCategoryId,
    this.calendarEventId,
    this.notionPageId,
    required this.createdAt,
    this.completedAt,
    this.currentStepIndex = 0,
  });

  factory TaskModel.fromJson(Map<String, dynamic> j) {
    Color c = const Color(0xFF6AAEE8);
    try {
      final hex = (j['color'] as String?)?.replaceAll('#', '');
      if (hex != null && hex.length == 6) {
        c = Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}

    return TaskModel(
      id: j['id'] ?? '',
      uid: j['uid'],
      title: j['title'] ?? 'Untitled',
      color: c,
      steps: ((j['steps'] as List?) ?? [])
          .map((s) => TaskStep.fromJson(s as Map<String, dynamic>))
          .toList(),
      dueDate: j['due_date'],
      endDate: j['end_date'],
      status: j['status'] ?? 'pending',
      source: j['source'] ?? 'manual',
      taskType: j['task_type'] ?? 'personal',
      scheduledTime: j['scheduled_time'],
      scheduledEndTime: j['scheduled_end_time'],
      priority: j['priority'] ?? 2,
      categoryId: j['category_id'],
      subCategoryId: j['sub_category_id'],
      calendarEventId: j['calendar_event_id'],
      notionPageId: j['notion_page_id'],
      createdAt: j['created_at'] ?? DateTime.now().toIso8601String(),
      completedAt: j['completed_at'],
      currentStepIndex: j['current_step_index'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    'title': title,
    'color': '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
    'steps': steps.map((s) => s.toJson()).toList(),
    'due_date': dueDate,
    'end_date': endDate,
    'status': status,
    'source': source,
    'task_type': taskType,
    'scheduled_time': scheduledTime,
    'scheduled_end_time': scheduledEndTime,
    'priority': priority,
    'category_id': categoryId,
    'sub_category_id': subCategoryId,
    'calendar_event_id': calendarEventId,
    'notion_page_id': notionPageId,
    'created_at': createdAt,
    'completed_at': completedAt,
    'current_step_index': currentStepIndex,
  };

  TaskModel copyWith({
    String? title,
    Color? color,
    List<TaskStep>? steps,
    String? dueDate,
    String? endDate,
    String? status,
    String? taskType,
    String? scheduledTime,
    String? scheduledEndTime,
    int? priority,
    String? categoryId,
    String? subCategoryId,
    int? currentStepIndex,
    String? completedAt,
  }) => TaskModel(
    id: id, uid: uid,
    title: title ?? this.title,
    color: color ?? this.color,
    steps: steps ?? this.steps,
    dueDate: dueDate ?? this.dueDate,
    endDate: endDate ?? this.endDate,
    status: status ?? this.status,
    source: source,
    taskType: taskType ?? this.taskType,
    scheduledTime: scheduledTime ?? this.scheduledTime,
    scheduledEndTime: scheduledEndTime ?? this.scheduledEndTime,
    priority: priority ?? this.priority,
    categoryId: categoryId ?? this.categoryId,
    subCategoryId: subCategoryId ?? this.subCategoryId,
    calendarEventId: calendarEventId,
    notionPageId: notionPageId,
    createdAt: createdAt,
    completedAt: completedAt ?? this.completedAt,
    currentStepIndex: currentStepIndex ?? this.currentStepIndex,
  );

  TaskStep? get currentStep =>
      currentStepIndex < steps.length ? steps[currentStepIndex] : null;

  int get completedSteps => steps.where((s) => s.completed).length;
  double get progress =>
      steps.isEmpty ? 0 : completedSteps / steps.length;

  bool get isMultiDay => endDate != null && endDate != dueDate;
  bool get isActive => status == 'active';
  bool get isComplete => status == 'complete';
  bool get needsReschedule => status == 'needs_reschedule';
}
