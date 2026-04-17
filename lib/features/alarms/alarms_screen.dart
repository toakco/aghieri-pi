import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../services/alarm_service.dart';

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen> {
  List<Alarm> get _alarms => AlarmService.instance.alarms;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      appBar: AppBar(
        backgroundColor: AghieriColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Alarms', style: AghieriTextStyles.heading(size: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AghieriColors.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AghieriColors.accent),
            onPressed: () => _showAlarmSheet(),
          ),
        ],
      ),
      body: _alarms.isEmpty
          ? _EmptyAlarms(onAdd: _showAlarmSheet)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: _alarms.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final alarm = _alarms[i];
                return _AlarmTile(
                  key: ValueKey(alarm.id),
                  alarm: alarm,
                  onToggle: (v) async {
                    await AlarmService.instance.toggle(alarm.id, v);
                    setState(() {});
                  },
                  onDelete: () async {
                    await AlarmService.instance.delete(alarm.id);
                    setState(() {});
                  },
                  onPreview: () => AlarmService.instance.preview(alarm),
                ).animate().fadeIn(delay: (i * 60).ms, duration: 300.ms)
                    .slideY(begin: 0.05, end: 0, delay: (i * 60).ms, duration: 300.ms);
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add-alarm',
        backgroundColor: AghieriColors.accent,
        foregroundColor: AghieriColors.bg,
        onPressed: _showAlarmSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showAlarmSheet({Alarm? editing}) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AghieriColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AlarmSheet(
        existing: editing,
        onSave: (alarm) async {
          if (editing != null) {
            await AlarmService.instance.delete(editing.id);
          }
          await AlarmService.instance.add(alarm);
          setState(() {});
        },
      ),
    );
  }
}

// ── Alarm tile ────────────────────────────────────────────────────────────────
class _AlarmTile extends StatelessWidget {
  final Alarm alarm;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  const _AlarmTile({
    super.key,
    required this.alarm,
    required this.onToggle,
    required this.onDelete,
    required this.onPreview,
  });

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  static const _wakeUpAmber = Color(0xFFFFA726);

  @override
  Widget build(BuildContext context) {
    final borderColor = alarm.isWakeUp && alarm.enabled
        ? _wakeUpAmber.withOpacity(0.4)
        : alarm.enabled
            ? AghieriColors.accent.withOpacity(0.25)
            : Colors.transparent;

    return Dismissible(
      key: ValueKey('dismissible-${alarm.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF3A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFE08080), size: 22),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        decoration: BoxDecoration(
          color: alarm.enabled
              ? AghieriColors.surface
              : AghieriColors.surface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // Wake-up sun icon
            if (alarm.isWakeUp) ...[
              Icon(
                Icons.wb_sunny_rounded,
                color: alarm.enabled ? _wakeUpAmber : AghieriColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
            ],
            // Time
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarm.time.format(),
                    style: AghieriTextStyles.heading(
                      size: 28,
                      weight: FontWeight.w600,
                      color: alarm.enabled
                          ? AghieriColors.textPrimary
                          : AghieriColors.textSecondary,
                    ),
                  ),
                  if (alarm.label.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      alarm.label,
                      style: AghieriTextStyles.caption(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (alarm.days.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(7, (i) {
                        final on = alarm.days.contains(i);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            _dayLabels[i],
                            style: AghieriTextStyles.label(
                              size: 11,
                              color: on
                                  ? AghieriColors.accent
                                  : AghieriColors.textSecondary,
                            ),
                          ),
                        );
                      }),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Once',
                        style: AghieriTextStyles.caption(color: AghieriColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),

            // Preview + toggle
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.play_circle_outline,
                      color: AghieriColors.textSecondary, size: 20),
                  tooltip: 'Preview',
                  onPressed: onPreview,
                ),
                Switch(
                  value: alarm.enabled,
                  onChanged: onToggle,
                  activeTrackColor: AghieriColors.accent,
                  inactiveTrackColor: AghieriColors.surfaceHigh,
                  thumbColor: WidgetStateProperty.all(AghieriColors.textPrimary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create / edit sheet ───────────────────────────────────────────────────────
class _AlarmSheet extends StatefulWidget {
  final Alarm? existing;
  final void Function(Alarm) onSave;

  const _AlarmSheet({this.existing, required this.onSave});

  @override
  State<_AlarmSheet> createState() => _AlarmSheetState();
}

class _AlarmSheetState extends State<_AlarmSheet> {
  late TimeOfDay _time;
  late TextEditingController _labelCtrl;
  late Set<int> _days;
  late bool _isWakeUp;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _wakeUpAmber = Color(0xFFFFA726);

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _time = ex != null
        ? TimeOfDay(hour: ex.time.hour, minute: ex.time.minute)
        : TimeOfDay.now();
    _labelCtrl = TextEditingController(text: ex?.label ?? '');
    _days = ex != null ? Set<int>.from(ex.days) : {0, 1, 2, 3, 4};
    _isWakeUp = ex?.isWakeUp ?? false;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
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
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 3,
              decoration: BoxDecoration(
                color: AghieriColors.surfaceHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text('New alarm', style: AghieriTextStyles.heading(size: 18)),
          const SizedBox(height: 20),

          // Time picker button
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: AghieriColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AghieriColors.accent.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _time.format(context),
                    style: AghieriTextStyles.heading(
                        size: 36, weight: FontWeight.w600,
                        color: AghieriColors.accent),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.edit_outlined,
                      color: AghieriColors.textSecondary, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Label
          TextField(
            controller: _labelCtrl,
            style: AghieriTextStyles.body(size: 15),
            decoration: const InputDecoration(
              hintText: 'Label (e.g. Good morning)',
            ),
          ),
          const SizedBox(height: 16),

          // Wake-up alarm toggle
          _buildWakeUpToggle(),
          const SizedBox(height: 16),

          // Day selector
          Text('Repeat', style: AghieriTextStyles.label()),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final on = _days.contains(i);
              return GestureDetector(
                onTap: () => setState(() {
                  on ? _days.remove(i) : _days.add(i);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? AghieriColors.accent.withOpacity(0.2)
                        : AghieriColors.surfaceHigh,
                    border: Border.all(
                      color: on ? AghieriColors.accent : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _dayNames[i][0],
                      style: AghieriTextStyles.label(
                        size: 12,
                        color: on ? AghieriColors.accent : AghieriColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // Save
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // Enforce max 5 wake-up alarms
                if (_isWakeUp && widget.existing?.isWakeUp != true) {
                  final wakeCount = AlarmService.instance.alarms
                      .where((a) => a.isWakeUp).length;
                  if (wakeCount >= 5) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Maximum 5 wake-up alarms allowed'),
                      ),
                    );
                    return;
                  }
                }
                final alarm = Alarm(
                  id: widget.existing?.id ?? const Uuid().v4(),
                  label: _labelCtrl.text.trim().isNotEmpty
                      ? _labelCtrl.text.trim()
                      : _time.format(context),
                  time: TimeEntry(_time.hour, _time.minute),
                  days: _days.toList()..sort(),
                  isWakeUp: _isWakeUp,
                );
                widget.onSave(alarm);
                Navigator.pop(context);
              },
              child: const Text('Save alarm'),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildWakeUpToggle() {
    return GestureDetector(
      onTap: () => setState(() => _isWakeUp = !_isWakeUp),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isWakeUp
              ? _wakeUpAmber.withOpacity(0.12)
              : AghieriColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isWakeUp ? _wakeUpAmber.withOpacity(0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.wb_sunny_rounded,
              color: _isWakeUp ? _wakeUpAmber : AghieriColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wake-up alarm',
                    style: AghieriTextStyles.body(
                      size: 14,
                      color: _isWakeUp
                          ? AghieriColors.textPrimary
                          : AghieriColors.textSecondary,
                    ),
                  ),
                  Text(
                    'Morning briefing via AI voice',
                    style: AghieriTextStyles.caption(
                      color: AghieriColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _isWakeUp,
              onChanged: (v) => setState(() => _isWakeUp = v),
              activeTrackColor: _wakeUpAmber,
              inactiveTrackColor: AghieriColors.surfaceHigh,
              thumbColor: WidgetStateProperty.all(
                _isWakeUp ? Colors.white : AghieriColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyAlarms extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyAlarms({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.alarm_outlined,
              color: AghieriColors.textSecondary, size: 48),
          const SizedBox(height: 16),
          Text('No alarms set.',
              style: AghieriTextStyles.body(color: AghieriColors.textSecondary)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onAdd,
            child: Text('Add one', style: AghieriTextStyles.body(color: AghieriColors.accent)),
          ),
        ],
      ),
    );
  }
}
