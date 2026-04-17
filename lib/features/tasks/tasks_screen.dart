import 'dart:async';
import 'dart:io' show File;
import 'dart:math';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/task_model.dart';
import '../../models/category_model.dart';
import '../../services/auth_service.dart';
import '../../services/claude_service.dart';
import '../../services/profile_service.dart';
import '../../services/task_service.dart';
import '../../services/voice_service.dart';


class TasksScreen extends StatefulWidget {
  final bool openNew;
  const TasksScreen({super.key, this.openNew = false});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  List<TaskModel> _tasks = [];
  bool _loading = true;
  late AnimationController _blobCtrl;

  @override
  void initState() {
    super.initState();
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _load();
    if (widget.openNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNewTaskDialog());
    }
  }

  @override
  void dispose() {
    _blobCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tasks = await TaskService.instance.getAllTasks();
    if (mounted) setState(() { _tasks = tasks; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AghieriColors.textSecondary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Tasks', style: AghieriTextStyles.heading(size: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AghieriColors.accent),
            onPressed: _showNewTaskDialog,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _blobCtrl,
        builder: (_, __) => Stack(
        children: [
          // Animated liquid gradient background
          Positioned.fill(
            child: CustomPaint(
              painter: _LiquidBlobPainter(animT: _blobCtrl.value),
            ),
          ),
          // Content layer
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AghieriColors.accent))
              : _tasks.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                      itemCount: _tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _TaskRow(
                        task: _tasks[i],
                        onTap: () => context.push('/focus/${_tasks[i].id}'),
                        onComplete: () async {
                          await TaskService.instance.completeStep(_tasks[i].id);
                          _load();
                        },
                        onDelete: () async {
                          await TaskService.instance.deleteTask(_tasks[i].id);
                          _load();
                        },
                      ).animate().fadeIn(delay: (i * 40).ms),
                    ),
        ],
      )),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No tasks yet.',
              style: AghieriTextStyles.body(color: AghieriColors.textSecondary)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _showNewTaskDialog,
            child: Text('Add one',
                style: AghieriTextStyles.body(color: AghieriColors.accent)),
          ),
        ],
      ),
    );
  }

  void _showNewTaskDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim, secAnim) => _NewTaskDialog(onCreated: _load),
      transitionBuilder: (ctx, anim, secAnim, child) {
        final curve = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curve),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

// ── Task row ──────────────────────────────────────────────────────────────────

class _TaskRow extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _TaskRow({
    required this.task,
    required this.onTap,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = AghieriColors.taskTypeColors[task.taskType] ??
        AghieriColors.accent;

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF2A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline,
            color: Color(0xFFE88A6A), size: 22),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return true;
      },
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: task.isActive
                  ? task.color.withOpacity(0.5)
                  : Colors.white.withOpacity(0.10),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Color bar
              Container(
                width: 4, height: 44,
                decoration: BoxDecoration(
                  color: task.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + type chip row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: AghieriTextStyles.body(
                              size: 15,
                              weight: FontWeight.w500,
                              color: task.isComplete
                                  ? AghieriColors.textSecondary
                                  : AghieriColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Type chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: typeColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: typeColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                task.taskType,
                                style: AghieriTextStyles.label(
                                    size: 10, color: typeColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (task.steps.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: task.progress,
                        backgroundColor: AghieriColors.surfaceHigh,
                        valueColor: AlwaysStoppedAnimation(task.color),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(task.progress * task.steps.length).round()} / ${task.steps.length} steps',
                        style: AghieriTextStyles.caption(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onComplete,
                child: Icon(
                  task.isComplete
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color:
                      task.isComplete ? task.color : AghieriColors.textSecondary,
                  size: 22,
                ),
              ),
            ],
          ),       // Row
        ),         // Container
      ),           // BackdropFilter
      ),           // ClipRRect
      ),           // GestureDetector
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return iso;
    }
  }

  String _formatScheduled(String t) {
    try {
      final parts = t.split(':');
      final h = int.parse(parts[0]);
      final m = parts[1];
      final ampm = h >= 12 ? 'PM' : 'AM';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:$m $ampm';
    } catch (_) {
      return t;
    }
  }
}

// ── New task dialog — 3-step centered ────────────────────────────────────────

class _NewTaskDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _NewTaskDialog({required this.onCreated});

  @override
  State<_NewTaskDialog> createState() => _NewTaskDialogState();
}

class _NewTaskDialogState extends State<_NewTaskDialog> {
  final _pageCtrl = PageController();
  int _step = 0; // 0=category, 1=title, 2=description, 3=time, 4=confirm

  // Collected data
  Color _color = const Color(0xFF6AAEE8);
  String _taskType = 'personal';
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  TimeOfDay? _scheduledTime;
  TimeOfDay? _scheduledEndTime;
  DateTime _selectedDate = DateTime.now();
  DateTime? _selectedEndDate;
  bool _isMultiDay = false;
  int _selectedPriority = 2; // 1=low, 2=medium, 3=high
  bool _saving = false;

  // Categories
  List<TaskCategory> _categories = TaskCategory.defaults;
  TaskCategory? _selectedCategory;
  SubCategory? _selectedSubCategory;

  // AI steps
  List<TaskStep> _generatedSteps = [];
  bool _generatingSteps = false;

  // File upload
  String? _uploadedFileName;
  String? _uploadedFileUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final profile = await ProfileService.instance.getProfile();
      if (mounted && profile.categories.isNotEmpty) {
        setState(() => _categories = profile.categories);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _pageCtrl.animateToPage(step,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    String? scheduledStr;
    if (_scheduledTime != null) {
      final h = _scheduledTime!.hour.toString().padLeft(2, '0');
      final m = _scheduledTime!.minute.toString().padLeft(2, '0');
      scheduledStr = '$h:$m';
    }
    String? scheduledEndStr;
    if (_scheduledEndTime != null) {
      final h = _scheduledEndTime!.hour.toString().padLeft(2, '0');
      final m = _scheduledEndTime!.minute.toString().padLeft(2, '0');
      scheduledEndStr = '$h:$m';
    }

    // Format due date
    final dueDateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    String? endDateStr;
    if (_selectedEndDate != null) {
      endDateStr = '${_selectedEndDate!.year}-${_selectedEndDate!.month.toString().padLeft(2, '0')}-${_selectedEndDate!.day.toString().padLeft(2, '0')}';
    }

    await TaskService.instance.createTask(
      title: _titleCtrl.text.trim(),
      color: '#${_color.value.toRadixString(16).substring(2).toUpperCase()}',
      dueDate: dueDateStr,
      endDate: endDateStr,
      taskType: _taskType,
      scheduledTime: scheduledStr,
      scheduledEndTime: scheduledEndStr,
      steps: _generatedSteps.isEmpty
          ? null
          : _generatedSteps.map((s) => s.toJson()).toList(),
      priority: _selectedPriority,
      categoryId: _selectedCategory?.id,
      subCategoryId: _selectedSubCategory?.id,
    );

    if (mounted) {
      Navigator.of(context).pop();
      widget.onCreated();
    }
  }

  // ── Voice handlers ────────────────────────────────────────────────────────

  Future<void> _voiceStep0() async {
    final result = await VoiceService.instance.listen();
    if (result.isEmpty || !mounted) return;
    final lower = result.toLowerCase();
    for (final cat in _categories) {
      if (lower.contains(cat.name.toLowerCase())) {
        setState(() {
          _selectedCategory = cat;
          _selectedSubCategory = null;
          _taskType = cat.id;
          _color = cat.color;
        });
        _goTo(1);
        return;
      }
    }
  }

  Future<void> _voiceStep1() async {
    final result = await VoiceService.instance.listen();
    if (result.isNotEmpty && mounted) {
      setState(() => _titleCtrl.text = result.trim());
      _goTo(2);
    }
  }

  Future<void> _voiceStep2() async {
    final result = await VoiceService.instance.listen();
    if (result.isEmpty || !mounted) return;
    final lower = result.toLowerCase();

    // Parse time from speech
    final re = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?');
    final m = re.firstMatch(lower);
    if (m != null) {
      int h = int.tryParse(m.group(1) ?? '') ?? -1;
      final min = int.tryParse(m.group(2) ?? '0') ?? 0;
      final mer = m.group(3);
      if (h >= 0) {
        if (mer == 'pm' && h < 12) h += 12;
        if (mer == 'am' && h == 12) h = 0;
        setState(() {
          _scheduledTime = TimeOfDay(
              hour: h.clamp(0, 23), minute: min.clamp(0, 59));
        });
        _goTo(4);
      }
    }

    // "tomorrow morning/afternoon/evening"
    if (lower.contains('morning') && _scheduledTime == null) {
      setState(() => _scheduledTime = const TimeOfDay(hour: 9, minute: 0));
      _goTo(4);
    } else if (lower.contains('afternoon') && _scheduledTime == null) {
      setState(() => _scheduledTime = const TimeOfDay(hour: 14, minute: 0));
      _goTo(4);
    } else if (lower.contains('evening') && _scheduledTime == null) {
      setState(() => _scheduledTime = const TimeOfDay(hour: 19, minute: 0));
      _goTo(4);
    }
  }

  // ── AI step generation ──────────────────────────────────────────────────

  Future<void> _generateSteps() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _generatingSteps = true);

    final desc = _descCtrl.text.trim();
    final prompt = desc.isNotEmpty
        ? 'Task: $title\nDescription: $desc'
        : 'Task: $title';

    try {
      final parsed = await ClaudeService.instance.parseInstruction(prompt, source: 'step_gen');
      if (parsed.isNotEmpty && mounted) {
        // parseInstruction returns list of tasks; extract steps from the first
        final taskData = parsed.first;
        final rawSteps = (taskData['steps'] as List?) ?? [];
        setState(() {
          _generatedSteps = rawSteps.asMap().entries.map((e) {
            if (e.value is Map<String, dynamic>) {
              return TaskStep.fromJson(e.value);
            }
            return TaskStep(
              id: '${e.key}',
              text: e.value.toString(),
            );
          }).toList();
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _generatingSteps = false);
  }

  void _removeStep(int index) {
    setState(() => _generatedSteps.removeAt(index));
  }

  void _reorderStep(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final step = _generatedSteps.removeAt(oldIndex);
      _generatedSteps.insert(newIndex, step);
    });
  }

  // ── File upload ───────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'txt', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    setState(() { _uploading = true; _uploadedFileName = file.name; });

    try {
      final uid = AuthService.instance.uid;
      final ref = FirebaseStorage.instance
          .ref('users/$uid/uploads/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      await ref.putFile(File(file.path!));
      final url = await ref.getDownloadURL();
      if (mounted) setState(() => _uploadedFileUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() { _uploadedFileName = null; _uploadedFileUrl = null; });
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  void _removeFile() {
    setState(() { _uploadedFileName = null; _uploadedFileUrl = null; });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AghieriColors.accent,
            surface: AghieriColors.surface,
            onSurface: AghieriColors.textPrimary,
          ),
          dialogBackgroundColor: AghieriColors.surfaceHigh,
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate ?? _selectedDate.add(const Duration(days: 1)),
      firstDate: _selectedDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AghieriColors.accent,
            surface: AghieriColors.surface,
            onSurface: AghieriColors.textPrimary,
          ),
          dialogBackgroundColor: AghieriColors.surfaceHigh,
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedEndDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AghieriColors.accent,
            surface: AghieriColors.surface,
            onSurface: AghieriColors.textPrimary,
          ),
          timePickerTheme: const TimePickerThemeData(
            backgroundColor: AghieriColors.surfaceHigh,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _scheduledTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    final initial = _scheduledEndTime ??
        (_scheduledTime != null
            ? TimeOfDay(
                hour: (_scheduledTime!.hour + 1).clamp(0, 23),
                minute: _scheduledTime!.minute,
              )
            : TimeOfDay.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AghieriColors.accent,
            surface: AghieriColors.surface,
            onSurface: AghieriColors.textPrimary,
          ),
          timePickerTheme: const TimePickerThemeData(
            backgroundColor: AghieriColors.surfaceHigh,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _scheduledEndTime = picked);
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day) {
      return 'Tomorrow';
    }
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _formatTod(TimeOfDay t) {
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h12:$min $p';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          decoration: BoxDecoration(
            color: AghieriColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AghieriColors.surfaceHigh,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                child: Row(
                  children: [
                    Text(
                      _stepTitle(_step),
                      style: AghieriTextStyles.heading(size: 18),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: AghieriColors.textSecondary, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Step dots
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _step == i ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? AghieriColors.accent
                          : AghieriColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )),
                ),
              ),

              // Pages
              SizedBox(
                height: 340,
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _Step0Category(
                      categories: _categories,
                      selectedCategory: _selectedCategory,
                      selectedSubCategory: _selectedSubCategory,
                      onCategoryChanged: (cat) => setState(() {
                        _selectedCategory = cat;
                        _selectedSubCategory = null;
                        _taskType = cat.id;
                        _color = cat.color;
                      }),
                      onSubCategoryChanged: (sub) =>
                          setState(() => _selectedSubCategory = sub),
                      onVoice: _voiceStep0,
                      onNext: () => _goTo(1),
                    ),
                    _Step1Title(
                      controller: _titleCtrl,
                      onVoice: _voiceStep1,
                      onNext: () {
                        if (_titleCtrl.text.trim().isNotEmpty) {
                          _goTo(2);
                          // Auto-generate steps when title is provided
                          if (_generatedSteps.isEmpty && !_generatingSteps) {
                            _generateSteps();
                          }
                        }
                      },
                    ),
                    _Step2Description(
                      controller: _descCtrl,
                      generatedSteps: _generatedSteps,
                      generatingSteps: _generatingSteps,
                      uploadedFileName: _uploadedFileName,
                      uploading: _uploading,
                      onGenerateSteps: _generateSteps,
                      onRemoveStep: _removeStep,
                      onReorderStep: _reorderStep,
                      onPickFile: _pickFile,
                      onRemoveFile: _removeFile,
                      onVoice: _voiceStep1,
                      onNext: () => _goTo(3),
                      onSkip: () => _goTo(3),
                    ),
                    _Step3Time(
                      selectedDate: _selectedDate,
                      selectedDateLabel: _formatDate(_selectedDate),
                      selectedEndDate: _selectedEndDate,
                      selectedEndDateLabel: _selectedEndDate != null
                          ? _formatDate(_selectedEndDate!)
                          : null,
                      isMultiDay: _isMultiDay,
                      priority: _selectedPriority,
                      scheduledTime: _scheduledTime,
                      scheduledEndTime: _scheduledEndTime,
                      onPickDate: _pickDate,
                      onPickEndDate: _pickEndDate,
                      onToggleMultiDay: (v) =>
                          setState(() {
                            _isMultiDay = v;
                            if (!v) _selectedEndDate = null;
                          }),
                      onPriorityChanged: (p) =>
                          setState(() => _selectedPriority = p),
                      onPickTime: _pickTime,
                      onPickEndTime: _pickEndTime,
                      onVoice: _voiceStep2,
                      onNext: () => _goTo(4),
                      onSkip: () => _goTo(4),
                    ),
                    _Step4Confirm(
                      color: _color,
                      taskType: _taskType,
                      title: _titleCtrl.text,
                      stepsCount: _generatedSteps.length,
                      saving: _saving,
                      onEdit: () => _goTo(0),
                      onSave: _save,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _stepTitle(int step) {
    switch (step) {
      case 0: return 'Category';
      case 1: return 'Task title';
      case 2: return 'Details';
      case 3: return 'When?';
      case 4: return 'Looks good?';
      default: return 'New Task';
    }
  }
}

// ── Step 0: Category Picker ──────────────────────────────────────────────────

class _Step0Category extends StatelessWidget {
  final List<TaskCategory> categories;
  final TaskCategory? selectedCategory;
  final SubCategory? selectedSubCategory;
  final ValueChanged<TaskCategory> onCategoryChanged;
  final ValueChanged<SubCategory> onSubCategoryChanged;
  final Future<void> Function() onVoice;
  final VoidCallback onNext;

  const _Step0Category({
    required this.categories,
    required this.selectedCategory,
    required this.selectedSubCategory,
    required this.onCategoryChanged,
    required this.onSubCategoryChanged,
    required this.onVoice,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category grid
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Category cards
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 2.4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (_, i) {
                    final cat = categories[i];
                    final selected = selectedCategory?.id == cat.id;
                    return GestureDetector(
                      onTap: () => onCategoryChanged(cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: selected
                              ? cat.color.withOpacity(0.18)
                              : AghieriColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? cat.color : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(cat.iconData,
                                size: 18,
                                color: selected
                                    ? cat.color
                                    : AghieriColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              cat.name,
                              style: AghieriTextStyles.label(
                                size: 13,
                                color: selected
                                    ? cat.color
                                    : AghieriColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Subcategory chips (shown when a category is selected)
                if (selectedCategory != null &&
                    selectedCategory!.subCategories.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Subcategory',
                      style: AghieriTextStyles.label(
                          size: 11, color: AghieriColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        selectedCategory!.subCategories.map((sub) {
                      final sel = selectedSubCategory?.id == sub.id;
                      return GestureDetector(
                        onTap: () => onSubCategoryChanged(sub),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? selectedCategory!.color.withOpacity(0.18)
                                : AghieriColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel
                                  ? selectedCategory!.color
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            sub.name,
                            style: AghieriTextStyles.label(
                              size: 12,
                              color: sel
                                  ? selectedCategory!.color
                                  : AghieriColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Mic + Next
          Row(
            children: [
              _MicCircleButton(onListen: onVoice),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step 1: Title ─────────────────────────────────────────────────────────────

class _Step1Title extends StatelessWidget {
  final TextEditingController controller;
  final Future<void> Function() onVoice;
  final VoidCallback onNext;

  const _Step1Title({
    required this.controller,
    required this.onVoice,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            autofocus: true,
            style: AghieriTextStyles.body(size: 18),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'What needs doing?',
              hintStyle: AghieriTextStyles.body(
                  size: 18, color: AghieriColors.textSecondary),
            ),
            onSubmitted: (_) => onNext(),
            textInputAction: TextInputAction.done,
          ),
          const Spacer(),
          Row(
            children: [
              _MicCircleButton(onListen: onVoice),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step 2: Description + AI Steps + File Upload ────────────────────────────

class _Step2Description extends StatelessWidget {
  final TextEditingController controller;
  final List<TaskStep> generatedSteps;
  final bool generatingSteps;
  final String? uploadedFileName;
  final bool uploading;
  final Future<void> Function() onGenerateSteps;
  final void Function(int) onRemoveStep;
  final void Function(int, int) onReorderStep;
  final Future<void> Function() onPickFile;
  final VoidCallback onRemoveFile;
  final Future<void> Function() onVoice;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Step2Description({
    required this.controller,
    required this.generatedSteps,
    required this.generatingSteps,
    this.uploadedFileName,
    required this.uploading,
    required this.onGenerateSteps,
    required this.onRemoveStep,
    required this.onReorderStep,
    required this.onPickFile,
    required this.onRemoveFile,
    required this.onVoice,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // Description text field
          SizedBox(
            height: 80,
            child: TextField(
              controller: controller,
              maxLines: 3,
              style: AghieriTextStyles.body(size: 14),
              decoration: InputDecoration(
                hintText: 'Add notes or description...',
                hintStyle: AghieriTextStyles.body(
                    size: 14, color: AghieriColors.textSecondary),
                filled: true,
                fillColor: AghieriColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Action row: Break it down + Upload
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: generatingSteps ? null : onGenerateSteps,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AghieriColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AghieriColors.accent.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (generatingSteps)
                          const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                              color: AghieriColors.accent,
                              strokeWidth: 1.5,
                            ),
                          )
                        else
                          const Icon(Icons.auto_awesome,
                              size: 14, color: AghieriColors.accent),
                        const SizedBox(width: 6),
                        Text(
                          'Break it down',
                          style: AghieriTextStyles.label(
                              size: 11, color: AghieriColors.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: uploading ? null : onPickFile,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AghieriColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: uploading
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                            color: AghieriColors.textSecondary,
                            strokeWidth: 1.5,
                          ),
                        )
                      : const Icon(Icons.attach_file_rounded,
                          size: 16, color: AghieriColors.textSecondary),
                ),
              ),
            ],
          ),
          // Uploaded file chip
          if (uploadedFileName != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 12, color: AghieriColors.accent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    uploadedFileName!,
                    style: AghieriTextStyles.caption(
                        color: AghieriColors.accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onRemoveFile,
                  child: const Icon(Icons.close,
                      size: 14, color: AghieriColors.textSecondary),
                ),
              ],
            ),
          ],
          // Generated steps list
          if (generatedSteps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: generatedSteps.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}.',
                        style: AghieriTextStyles.caption(
                            color: AghieriColors.accent),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          generatedSteps[i].text,
                          style: AghieriTextStyles.body(size: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => onRemoveStep(i),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 12, color: AghieriColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else
            const Spacer(),
          // Bottom row
          Row(
            children: [
              _MicCircleButton(onListen: onVoice),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSkip,
                child: Text('Skip',
                    style: AghieriTextStyles.caption(
                        color: AghieriColors.textSecondary)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Time ──────────────────────────────────────────────────────────────

class _Step3Time extends StatelessWidget {
  final DateTime selectedDate;
  final String selectedDateLabel;
  final DateTime? selectedEndDate;
  final String? selectedEndDateLabel;
  final bool isMultiDay;
  final int priority;
  final TimeOfDay? scheduledTime;
  final TimeOfDay? scheduledEndTime;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickEndDate;
  final ValueChanged<bool> onToggleMultiDay;
  final ValueChanged<int> onPriorityChanged;
  final Future<void> Function() onPickTime;
  final Future<void> Function() onPickEndTime;
  final Future<void> Function() onVoice;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _Step3Time({
    required this.selectedDate,
    required this.selectedDateLabel,
    this.selectedEndDate,
    this.selectedEndDateLabel,
    required this.isMultiDay,
    required this.priority,
    required this.scheduledTime,
    required this.scheduledEndTime,
    required this.onPickDate,
    required this.onPickEndDate,
    required this.onToggleMultiDay,
    required this.onPriorityChanged,
    required this.onPickTime,
    required this.onPickEndTime,
    required this.onVoice,
    required this.onNext,
    required this.onSkip,
  });

  String _fmt(TimeOfDay t) {
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h12:$min $p';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          Text(
            'When does this happen?',
            style: AghieriTextStyles.body(color: AghieriColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Start date picker
          GestureDetector(
            onTap: onPickDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AghieriColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AghieriColors.accent.withOpacity(0.45),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: AghieriColors.accent),
                  const SizedBox(width: 10),
                  Text(isMultiDay ? 'Start date' : 'Date',
                      style: AghieriTextStyles.caption(
                          color: AghieriColors.textSecondary)),
                  const Spacer(),
                  Text(
                    selectedDateLabel,
                    style: AghieriTextStyles.body(
                        size: 15,
                        weight: FontWeight.w500,
                        color: AghieriColors.accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Multi-day toggle
          GestureDetector(
            onTap: () => onToggleMultiDay(!isMultiDay),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: isMultiDay
                        ? AghieriColors.accent.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isMultiDay
                          ? AghieriColors.accent
                          : AghieriColors.textSecondary,
                    ),
                  ),
                  child: isMultiDay
                      ? const Icon(Icons.check, size: 12, color: AghieriColors.accent)
                      : null,
                ),
                const SizedBox(width: 8),
                Text('Multi-day task',
                    style: AghieriTextStyles.caption(
                        color: AghieriColors.textSecondary)),
              ],
            ),
          ),
          // End date picker (shown when multi-day)
          if (isMultiDay) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onPickEndDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: AghieriColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selectedEndDate != null
                        ? AghieriColors.accent.withOpacity(0.45)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded,
                        size: 16, color: AghieriColors.accent),
                    const SizedBox(width: 10),
                    Text('End date',
                        style: AghieriTextStyles.caption(
                            color: AghieriColors.textSecondary)),
                    const Spacer(),
                    Text(
                      selectedEndDateLabel ?? 'Pick end date',
                      style: AghieriTextStyles.body(
                          size: 15,
                          weight: FontWeight.w500,
                          color: selectedEndDate != null
                              ? AghieriColors.accent
                              : AghieriColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Start/end time
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onPickTime,
                  child: _TimeTile(
                    label: 'Starts',
                    time: scheduledTime != null ? _fmt(scheduledTime!) : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onPickEndTime,
                  child: _TimeTile(
                    label: 'Ends',
                    time: scheduledEndTime != null ? _fmt(scheduledEndTime!) : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Priority picker (1-3 scale)
          Row(
            children: [
              Text('Importance',
                  style: AghieriTextStyles.caption(
                      color: AghieriColors.textSecondary)),
              const Spacer(),
              ...List.generate(3, (i) {
                final level = i + 1;
                final selected = priority == level;
                final labels = ['Low', 'Medium', 'High'];
                final colors = [
                  const Color(0xFF88D498),
                  const Color(0xFFFFE888),
                  const Color(0xFFE88A6A),
                ];
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => onPriorityChanged(level),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? colors[i].withOpacity(0.20)
                            : AghieriColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? colors[i]
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        labels[i],
                        style: AghieriTextStyles.label(
                          size: 11,
                          color: selected
                              ? colors[i]
                              : AghieriColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              _MicCircleButton(onListen: onVoice),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSkip,
                child: Text('Skip',
                    style: AghieriTextStyles.caption(
                        color: AghieriColors.textSecondary)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final String? time;
  const _TimeTile({required this.label, this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: AghieriColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: time != null
              ? AghieriColors.accent.withOpacity(0.45)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Text(label,
              style: AghieriTextStyles.caption(
                  color: AghieriColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            time ?? '--:--',
            style: time != null
                ? AghieriTextStyles.heading(
                    size: 20,
                    weight: FontWeight.w600,
                    color: AghieriColors.accent)
                : AghieriTextStyles.body(
                    color: AghieriColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Confirm ───────────────────────────────────────────────────────────

class _Step4Confirm extends StatelessWidget {
  final Color color;
  final String taskType;
  final String title;
  final int stepsCount;
  final bool saving;
  final VoidCallback onEdit;
  final Future<void> Function() onSave;

  const _Step4Confirm({
    required this.color,
    required this.taskType,
    required this.title,
    this.stepsCount = 0,
    required this.saving,
    required this.onEdit,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor =
        AghieriColors.taskTypeColors[taskType] ?? AghieriColors.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          // Preview card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AghieriColors.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        taskType,
                        style: AghieriTextStyles.label(
                            size: 10, color: typeColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title.isNotEmpty ? title : '(no title)',
                  style: AghieriTextStyles.heading(size: 18),
                  textAlign: TextAlign.center,
                ),
                if (stepsCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$stepsCount steps',
                    style: AghieriTextStyles.caption(color: AghieriColors.accent),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: onEdit,
                child: Text(
                  'Edit',
                  style: AghieriTextStyles.body(
                      color: AghieriColors.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: saving ? null : onSave,
                  child: saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: AghieriColors.bg, strokeWidth: 2))
                      : const Text('Looks good'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Mic circle button ──────────────────────────────────────────────────────────

class _MicCircleButton extends StatefulWidget {
  final Future<void> Function() onListen;
  const _MicCircleButton({required this.onListen});

  @override
  State<_MicCircleButton> createState() => _MicCircleButtonState();
}

class _MicCircleButtonState extends State<_MicCircleButton> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (_active) return;
        setState(() => _active = true);
        try {
          await widget.onListen();
        } finally {
          if (mounted) setState(() => _active = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active
              ? AghieriColors.accent.withOpacity(0.2)
              : AghieriColors.surfaceHigh,
          border: Border.all(
            color: _active ? AghieriColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Icon(
          _active ? Icons.mic : Icons.mic_none_rounded,
          color: _active ? AghieriColors.accent : AghieriColors.textSecondary,
          size: 22,
        ),
      ),
    );
  }
}

// ── Lava Lamp Background Painter ─────────────────────────────────────────────
/// Full-coverage lava lamp effect — saturated purple/magenta/pink/red.
/// Colors fill the entire canvas and blend smoothly like liquid.
class _LiquidBlobPainter extends CustomPainter {
  final double animT;

  _LiquidBlobPainter({required this.animT});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final t = animT * 2 * pi;

    // 1. Base gradient fill — covers everything, no dark gaps
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFF6A00D7), // deep purple
            Color(0xFFCC00FF), // magenta
            Color(0xFFFF1493), // hot pink
            Color(0xFF8B00FF), // purple
          ],
        ).createShader(rect),
    );

    // 2. Large lava blobs — fully opaque cores, heavy blur for smooth merging
    // Each blob drifts in a slow lissajous path
    final blobs = [
      // (baseX, baseY, driftX, driftY, phaseX, phaseY, radius, color)
      (0.25, 0.20, 0.12, 0.10, 0.0, 0.3, 0.50, const Color(0xFFFF00FF)),  // magenta
      (0.75, 0.25, 0.10, 0.12, 0.5, 0.0, 0.45, const Color(0xFFFF4500)),  // red-orange
      (0.50, 0.55, 0.15, 0.12, 0.3, 0.6, 0.55, const Color(0xFFFFB6C1)),  // light pink
      (0.20, 0.75, 0.10, 0.08, 0.2, 0.7, 0.48, const Color(0xFF8B00FF)),  // purple
      (0.80, 0.70, 0.08, 0.10, 0.8, 0.4, 0.42, const Color(0xFFFF1493)),  // hot pink
      (0.50, 0.15, 0.12, 0.06, 0.6, 0.1, 0.40, const Color(0xFFFF6B00)),  // orange
    ];

    for (final (bx, by, dx, dy, px, py, r, color) in blobs) {
      final cx = w * (bx + dx * sin(t * 0.8 + px * 2 * pi));
      final cy = h * (by + dy * sin(t * 0.6 + py * 2 * pi));
      final radius = w * r;
      final center = Offset(cx, cy);

      // Inner saturated core
      canvas.drawCircle(
        center,
        radius * 0.55,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color,
              color.withOpacity(0.7),
              color.withOpacity(0.0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 0.55))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.4),
      );

      // Outer soft spread — blends with neighbors
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withOpacity(0.6),
              color.withOpacity(0.25),
              color.withOpacity(0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.7),
      );
    }

    // 3. Secondary drift blobs — slower, larger, more transparent for depth
    final cx2 = w * (0.35 + 0.18 * sin(t * 0.3));
    final cy2 = h * (0.40 + 0.15 * cos(t * 0.4));
    canvas.drawCircle(
      Offset(cx2, cy2),
      w * 0.6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFF69B4).withOpacity(0.45),
            const Color(0xFFCC00FF).withOpacity(0.2),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx2, cy2), radius: w * 0.6))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.25),
    );

    final cx3 = w * (0.65 + 0.14 * cos(t * 0.25));
    final cy3 = h * (0.65 + 0.12 * sin(t * 0.35));
    canvas.drawCircle(
      Offset(cx3, cy3),
      w * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFF4500).withOpacity(0.35),
            const Color(0xFFFF1493).withOpacity(0.15),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx3, cy3), radius: w * 0.55))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.22),
    );

    // 4. Slight dark vignette at edges for depth
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.15),
          ],
          stops: const [0.6, 1.0],
        ).createShader(Rect.fromCircle(
          center: Offset(w * 0.5, h * 0.4),
          radius: max(w, h) * 0.7,
        )),
    );
  }

  @override
  bool shouldRepaint(_LiquidBlobPainter old) => old.animT != animT;
}
