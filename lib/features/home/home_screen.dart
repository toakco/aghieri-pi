import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../models/task_model.dart';
import '../../models/user_profile.dart';
import '../../services/interaction_tracker.dart';
import '../../services/schedule_optimizer.dart';
import '../../services/task_service.dart';
import '../../services/profile_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/circular_display/circular_arc_display.dart';
import '../../widgets/device_controls.dart';
import '../../widgets/now_playing_card.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  List<TaskModel> _tasks = [];
  UserProfile _profile = const UserProfile();
  bool _loading = true;
  ConnectivityStatus _connectivity = ConnectivityStatus.online;
  StreamSubscription? _connectSub;
  // Voice triggered directly via VoiceService when circle is tapped
  bool _isListening = false;
  late TabController _tabCtrl;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      setState(() => _tabIndex = _tabCtrl.index);
      _loadForTab(_tabCtrl.index);
    });
    _load();
    _connectivity = VoiceService.instance.currentStatus;
    _connectSub = VoiceService.instance.statusStream.listen((s) {
      if (mounted) setState(() => _connectivity = s);
    });

    // Wake-word detection disabled by default — tap the mic button to talk.
    // To enable always-on wake word, user can toggle it in settings.
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    VoiceService.instance.stopWakeWordListening();
    _connectSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Auto-mark overdue tasks for rescheduling
    await TaskService.instance.checkOverdueTasks();
    final tasks   = await TaskService.instance.getTodayTasks();
    final profile = await ProfileService.instance.getProfile();
    if (mounted) {
      setState(() { _tasks = tasks; _profile = profile; _loading = false; });
    }
  }

  Future<void> _loadForTab(int tab) async {
    List<TaskModel> tasks;
    switch (tab) {
      case 1:
        tasks = await TaskService.instance.getWeekTasks();
      case 2:
        tasks = await TaskService.instance.getMonthTasks();
      case 3:
        tasks = await TaskService.instance.getYearTasks();
      default:
        tasks = await TaskService.instance.getTodayTasks();
    }
    if (mounted) setState(() => _tasks = tasks);
  }

  double _circleSize(BuildContext context) {
    final s = MediaQuery.of(context).size;
    return min(s.width - 48, s.height * 0.55);
  }

  bool _voiceSessionActive = false;

  void _stopVoice() {
    _voiceSessionActive = false;
    VoiceService.instance.stop();
    VoiceService.instance.clearConversation();
    if (mounted) setState(() => _isListening = false);
  }

  Future<void> _activateVoice() async {
    if (_voiceSessionActive) return;
    _voiceSessionActive = true;
    VoiceService.instance.clearConversation();

    // iOS Safari requires audio unlock from user gesture context
    await VoiceService.instance.unlockAudio();

    // Activate listening animation on the ring
    if (mounted) setState(() => _isListening = true);

    int silenceCount = 0;

    try {
      while (_voiceSessionActive && mounted) {
        final transcript = await VoiceService.instance.listen(
          onInterim: (_) {},
          timeout: const Duration(seconds: 10),
        );
        if (!mounted) break;

        if (transcript.isEmpty) {
          silenceCount++;
          if (silenceCount >= 2) break;
          continue;
        }

        silenceCount = 0;

        // Brief visual feedback — ring stays animated
        // Send to Claude — speaks response via TTS
        final response = await VoiceService.instance.sendCommand(transcript);
        if (!mounted) break;

        if (response.isNotEmpty) {
          _load();
          // Wait for TTS to finish before re-listening
          await Future.delayed(const Duration(seconds: 3));
        }

        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('[Home] Voice session error: $e');
    } finally {
      _voiceSessionActive = false;
      VoiceService.instance.clearConversation();
      if (mounted) setState(() => _isListening = false);
    }
  }

  int _parseTime(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  TaskModel? get _activeTask =>
      _tasks.isEmpty ? null : _tasks.firstWhere((t) => t.isActive, orElse: () => _tasks.first);

  @override
  Widget build(BuildContext context) {
    final greeting = _greeting(_profile.displayName);
    final now = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Scaffold(
      backgroundColor: AghieriColors.bg,
      body: SafeArea(
        child: _loading
            ? const _HomeShimmer()
            : RefreshIndicator(
                onRefresh: _load,
                color: AghieriColors.accent,
                backgroundColor: AghieriColors.surface,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top bar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(now, style: AghieriTextStyles.caption()),
                                    const SizedBox(width: 8),
                                    _ConnectivityDot(status: _connectivity),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.alarm_outlined,
                                          color: AghieriColors.textSecondary, size: 20),
                                      onPressed: () => context.push('/alarms'),
                                      tooltip: 'Alarms',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.person_outline,
                                          color: AghieriColors.textSecondary),
                                      onPressed: () => context.push('/profile'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(greeting, style: AghieriTextStyles.heading(size: 22))
                                .animate()
                                .fadeIn(duration: 500.ms)
                                .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                            const SizedBox(height: 32),

                            // Circular arc display + task overlay dots
                            Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                // Background tap → voice (task dots absorb their own taps)
                                onTap: () {
                                  if (_voiceSessionActive) {
                                    _stopVoice();
                                  } else {
                                    _activateVoice();
                                  }
                                },
                                onLongPress: () => context.push('/aquarium'),
                                child: SizedBox(
                                  width: _circleSize(context),
                                  height: _circleSize(context),
                                  child: Stack(
                                    children: [
                                      Hero(
                                        tag: 'circular-display',
                                        child: CircularArcDisplay(
                                          tasks: _tasks,
                                          activeTask: _activeTask,
                                          size: _circleSize(context),
                                          wakeTime: _profile.wakeTime,
                                          sleepTime: _profile.sleepTime,
                                          uiMode: 'abstract',
                                          tabIndex: _tabIndex,
                                          isListening: _isListening,
                                        ),
                                      ),
                                      // Tappable task dots positioned on the ring
                                      ..._buildTaskDots(context),
                                    ],
                                  ),
                                ),
                              ),
                            ).animate().fadeIn(
                              delay: 180.ms,
                              duration: 600.ms,
                              curve: Curves.easeOut,
                            ).scale(
                              begin: const Offset(0.94, 0.94),
                              end: const Offset(1, 1),
                              delay: 180.ms,
                              duration: 600.ms,
                              curve: Curves.easeOutCubic,
                            ),

                            // Now playing card
                            const NowPlayingCard(),

                            const SizedBox(height: 16),

                            // Time-period tabs
                            Row(
                              children: [
                                Expanded(
                                  child: TabBar(
                                    controller: _tabCtrl,
                                    isScrollable: true,
                                    tabAlignment: TabAlignment.start,
                                    labelColor: AghieriColors.textPrimary,
                                    unselectedLabelColor: AghieriColors.textSecondary,
                                    labelStyle: AghieriTextStyles.label(size: 13),
                                    unselectedLabelStyle: AghieriTextStyles.label(size: 13),
                                    indicatorColor: AghieriColors.accent,
                                    indicatorSize: TabBarIndicatorSize.label,
                                    dividerColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                                    tabs: const [
                                      Tab(text: 'Today'),
                                      Tab(text: 'Week'),
                                      Tab(text: 'Month'),
                                      Tab(text: 'Year'),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.push('/tasks'),
                                  child: Text('All',
                                      style: AghieriTextStyles.caption(color: AghieriColors.accent)),
                                ),
                              ],
                            ).animate().fadeIn(delay: 320.ms, duration: 400.ms),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),

                    // Task cards — staggered entrance
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: _tasks.isEmpty
                          ? SliverToBoxAdapter(
                              child: _EmptyState(onAddTask: () => context.push('/tasks')),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _TaskCard(
                                    task: _tasks[i],
                                    onTap: () => context.push('/focus/${_tasks[i].id}'),
                                    onComplete: () => _completeTask(_tasks[i]),
                                  ).animate().fadeIn(
                                    delay: (380 + i * 80).ms,
                                    duration: 400.ms,
                                    curve: Curves.easeOut,
                                  ).slideY(
                                    begin: 0.06,
                                    end: 0,
                                    delay: (380 + i * 80).ms,
                                    duration: 400.ms,
                                    curve: Curves.easeOut,
                                  ),
                                ),
                                childCount: _tabIndex == 0
                                    ? min(_tasks.length, 3)
                                    : _tasks.length,
                              ),
                            ),
                    ),

                    // Reschedule prompts
                    if (_tasks.any((t) => t.needsReschedule))
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                          child: _ReschedulePrompt(
                            tasks: _tasks.where((t) => t.needsReschedule).toList(),
                            onReschedule: (task) => _showRescheduleSheet(task),
                          ),
                        ),
                      ),

                    // Device control bar — above FAB space
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(0, 20, 0, 0),
                        child: DeviceControlBar(),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'add',
        onPressed: () => context.push('/tasks/new').then((_) => _load()),
        backgroundColor: AghieriColors.surface,
        child: const Icon(Icons.add, color: AghieriColors.textPrimary),
      ),
    );
  }

  /// Build tappable task indicator dots positioned on the ring around the moon.
  /// Each dot absorbs its own tap → navigate to task. Background tap → voice.
  List<Widget> _buildTaskDots(BuildContext context) {
    if (_tasks.isEmpty) return [];

    final sz = _circleSize(context);
    final cx = sz / 2;
    final cy = sz / 2;
    // Dots sit just outside the moon (moonR = sz*0.44), on the voice ring gap
    final dotR = sz * 0.485;
    final dotSize = 10.0;

    final now = DateTime.now();
    final wakeMin = _parseTime(_profile.wakeTime);
    final sleepMin = _parseTime(_profile.sleepTime);
    int dayDur = sleepMin - wakeMin;
    if (dayDur <= 0) dayDur += 1440;

    // Period for non-today tabs
    late final DateTime periodStart;
    late final int totalMins;
    if (_tabIndex == 0) {
      periodStart = DateTime(now.year, now.month, now.day);
      totalMins = dayDur;
    } else if (_tabIndex == 1) {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      periodStart = DateTime(monday.year, monday.month, monday.day);
      totalMins = 7 * 1440;
    } else if (_tabIndex == 2) {
      periodStart = DateTime(now.year, now.month, 1);
      final dim = DateTime(now.year, now.month + 1, 0).day;
      totalMins = dim * 1440;
    } else {
      periodStart = DateTime(now.year, 1, 1);
      final diy = DateTime(now.year + 1, 1, 1).difference(periodStart).inDays;
      totalMins = diy * 1440;
    }

    final dots = <Widget>[];
    final nowMin = now.hour * 60 + now.minute;

    for (final task in _tasks) {
      double frac;
      if (_tabIndex == 0) {
        final startMin = task.scheduledTime != null
            ? _parseTime(task.scheduledTime!)
            : nowMin;
        int elapsed = startMin - wakeMin;
        if (elapsed < 0) elapsed += 1440;
        frac = (elapsed / dayDur).clamp(0.0, 1.0);
      } else {
        DateTime taskDate = now;
        if (task.dueDate != null) {
          final p = task.dueDate!.split('-');
          if (p.length >= 3) {
            taskDate = DateTime(
                int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
          }
        }
        final taskMin = task.scheduledTime != null
            ? _parseTime(task.scheduledTime!)
            : wakeMin;
        final fromPeriod =
            taskDate.difference(periodStart).inDays * 1440 + taskMin;
        frac = (fromPeriod / totalMins).clamp(0.0, 1.0);
      }

      // Arc spans π → 2π (upper semicircle, left→top→right)
      final angle = pi + frac * pi;
      final dx = cx + dotR * cos(angle) - dotSize / 2;
      final dy = cy + dotR * sin(angle) - dotSize / 2;

      dots.add(Positioned(
        left: dx,
        top: dy,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('/focus/${task.id}'),
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.color,
              boxShadow: [
                BoxShadow(
                  color: task.color.withOpacity(0.7),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return dots;
  }

  String _greeting(String name) {
    final hour = DateTime.now().hour;
    final prefix = hour < 12 ? 'Good morning'
        : hour < 17 ? 'Good afternoon'
        : 'Good evening';
    return name.isNotEmpty ? '$prefix, $name.' : prefix;
  }

  Future<void> _completeTask(TaskModel task) async {
    await TaskService.instance.completeStep(task.id);
    _load();
  }

  void _showRescheduleSheet(TaskModel task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AghieriColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RescheduleSheet(task: task, onDone: _load),
    );
  }
}

// ── Components ────────────────────────────────────────────────────────────────

class _TaskCard extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  const _TaskCard({required this.task, required this.onTap, required this.onComplete});

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_)   => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..scale(_pressed ? 0.978 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _pressed
              ? AghieriColors.surfaceHigh
              : AghieriColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: task.isActive
                ? task.color.withOpacity(0.35)
                : Colors.transparent,
            width: 1,
          ),
          boxShadow: task.isActive
              ? [
                  BoxShadow(
                    color: task.color.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Row(
          children: [
            // Color bar with glow
            Container(
              width: 3, height: 48,
              decoration: BoxDecoration(
                color: task.color,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: task.color.withOpacity(0.50),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: AghieriTextStyles.body(size: 15, weight: FontWeight.w500),
                  ),
                  if (task.currentStep != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      task.currentStep!.text,
                      style: AghieriTextStyles.caption(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (task.steps.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: task.progress),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          backgroundColor: AghieriColors.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation(task.color),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Complete step button
            GestureDetector(
              onTap: widget.onComplete,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                    child: child,
                  ),
                  child: Icon(
                    task.isComplete
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    key: ValueKey(task.isComplete),
                    color: task.isComplete
                        ? task.color
                        : task.color.withOpacity(0.45),
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddTask;
  const _EmptyState({required this.onAddTask});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 32),
        Text('No tasks today.', style: AghieriTextStyles.body(color: AghieriColors.textSecondary)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onAddTask,
          child: Text('Add one', style: AghieriTextStyles.body(color: AghieriColors.accent)),
        ),
      ],
    );
  }
}

class _ReschedulePrompt extends StatelessWidget {
  final List<TaskModel> tasks;
  final void Function(TaskModel) onReschedule;
  const _ReschedulePrompt({required this.tasks, required this.onReschedule});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AghieriColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AghieriColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A few things from yesterday',
              style: AghieriTextStyles.body(size: 14, weight: FontWeight.w500)),
          const SizedBox(height: 8),
          ...tasks.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: t.color, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Text(t.title, style: AghieriTextStyles.caption())),
                TextButton(
                  onPressed: () => onReschedule(t),
                  child: Text('Find a spot', style: AghieriTextStyles.caption(color: AghieriColors.accent)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _RescheduleSheet extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onDone;
  const _RescheduleSheet({required this.task, required this.onDone});

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  List<Map<String, String>> _slots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    // Use schedule optimizer for smart slot suggestions
    try {
      final optimized = await ScheduleOptimizer.instance.suggestTomorrowSlots(widget.task);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dateStr = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      final slots = optimized.map((s) => {
        'label': '${s.formatted} — ${s.reason}',
        'date': dateStr,
        'time': s.start,
      }).toList();
      if (mounted) setState(() { _slots = slots; _loading = false; });
    } catch (_) {
      // Fallback to hardcoded
      final slots = await TaskService.instance.getRescheduleSlots(widget.task.id, widget.task.title);
      if (mounted) setState(() { _slots = slots; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"${widget.task.title}" didn\'t make it today.',
              style: AghieriTextStyles.body(size: 15)),
          const SizedBox(height: 4),
          Text('No pressure — want to find a spot?',
              style: AghieriTextStyles.caption()),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AghieriColors.accent))
          else
            ..._slots.map((slot) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await TaskService.instance.rescheduleTask(
                      widget.task.id, slot['date'] ?? '');
                    if (context.mounted) { Navigator.pop(context); widget.onDone(); }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AghieriColors.accent, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(slot['label'] ?? '', style: AghieriTextStyles.body(size: 15)),
                ),
              ),
            )),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Not now', style: AghieriTextStyles.caption()),
          ),
        ],
      ),
    );
  }
}

// ── Shimmer loading placeholder ───────────────────────────────────────────────

class _HomeShimmer extends StatefulWidget {
  const _HomeShimmer();

  @override
  State<_HomeShimmer> createState() => _HomeShimmerState();
}

class _HomeShimmerState extends State<_HomeShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final shimmer = _anim.value;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date bar
              _ShimmerBox(width: 120, height: 14, shimmer: shimmer),
              const SizedBox(height: 10),
              _ShimmerBox(width: w * 0.55, height: 22, shimmer: shimmer),
              const SizedBox(height: 32),
              // Circle placeholder
              Center(
                child: Builder(builder: (ctx) {
                  final s = MediaQuery.of(ctx).size;
                  final sz = min(s.width - 48, s.height * 0.55);
                  return _ShimmerBox(width: sz, height: sz, radius: sz / 2, shimmer: shimmer);
                }),
              ),
              const SizedBox(height: 32),
              _ShimmerBox(width: 80, height: 16, shimmer: shimmer),
              const SizedBox(height: 14),
              // Task card placeholders
              for (int i = 0; i < 3; i++) ...[
                _ShimmerBox(width: double.infinity, height: 72,
                    radius: 16, shimmer: shimmer),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final double shimmer;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 8,
    required this.shimmer,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor  = AghieriColors.surface;
    final shineColor = AghieriColors.surfaceHigh;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: Color.lerp(baseColor, shineColor,
            0.5 + 0.5 * sin(shimmer * 2 * pi)),
      ),
    );
  }
}

// ── Connectivity dot ──────────────────────────────────────────────────────────
/// Tiny status indicator: green = device online, blue = wifi only, grey = offline
class _ConnectivityDot extends StatelessWidget {
  final ConnectivityStatus status;
  const _ConnectivityDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;
    switch (status) {
      case ConnectivityStatus.deviceOnline:
        color   = AghieriColors.accent;
        tooltip = 'Device connected';
      case ConnectivityStatus.online:
        color   = const Color(0xFF7BB8D4);
        tooltip = 'Online — device not found';
      case ConnectivityStatus.offline:
        color   = AghieriColors.textSecondary;
        tooltip = 'Offline';
    }

    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: status != ConnectivityStatus.offline
              ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 4, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}
