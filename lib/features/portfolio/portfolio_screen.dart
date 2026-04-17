import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/claude_service.dart';
import '../../services/interaction_tracker.dart';
import '../../services/task_service.dart';
import '../../services/tribe_engine.dart';
import '../../services/profile_service.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  bool _loading = true;
  TribeProfile? _tribe;
  Map<String, int> _typeCounts = {};
  Map<int, int> _hourly = {};
  int _totalTasks = 0;
  int _completedTasks = 0;
  List<Map<String, dynamic>> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracker = InteractionTracker.instance;
    final taskService = TaskService.instance;

    final results = await Future.wait([
      TribeEngine.instance.analyze(),
      tracker.getTypeCounts(days: 14),
      tracker.getHourlyDistribution(days: 14),
      taskService.getAllTasks(),
      ProfileService.instance.getSuggestions(),
    ]);

    final tribe = results[0] as TribeProfile;
    final typeCounts = results[1] as Map<String, int>;
    final hourly = results[2] as Map<int, int>;
    final allTasks = results[3] as List;
    final suggestions = results[4] as List<Map<String, dynamic>>;

    if (mounted) {
      setState(() {
        _tribe = tribe;
        _typeCounts = typeCounts;
        _hourly = hourly;
        _totalTasks = allTasks.length;
        _completedTasks = allTasks.where((t) => t.status == 'complete').length;
        _suggestions = suggestions;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AghieriColors.textSecondary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Insights', style: AghieriTextStyles.heading(size: 18)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AghieriColors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                // TRIBE scores
                if (_tribe != null) _tappableCard(
                  id: 'tribe',
                  name: 'Your Pattern (TRIBE scores)',
                  value: 'Trust ${(_tribe!.trust * 100).toStringAsFixed(0)}, Energy ${(_tribe!.energy * 100).toStringAsFixed(0)}, Impulse ${(_tribe!.impulse * 100).toStringAsFixed(0)}',
                  child: _buildTribeCard(_tribe!),
                ),
                const SizedBox(height: 16),

                // Completion rate
                _tappableCard(
                  id: 'completion',
                  name: 'Task Completion Rate',
                  value: '${_totalTasks > 0 ? (_completedTasks / _totalTasks * 100).toStringAsFixed(0) : 0}% ($_completedTasks/$_totalTasks)',
                  child: _buildCompletionCard(),
                ),
                const SizedBox(height: 16),

                // Activity heatmap
                _tappableCard(
                  id: 'activity',
                  name: 'Activity Distribution',
                  value: '${_hourly.values.fold(0, (a, b) => a + b)} interactions over 14 days',
                  child: _buildActivityCard(),
                ),
                const SizedBox(height: 16),

                // Interaction breakdown
                _tappableCard(
                  id: 'interactions',
                  name: 'Interaction Breakdown',
                  value: '${_typeCounts.values.fold(0, (a, b) => a + b)} total, ${_typeCounts.length} categories',
                  child: _buildBreakdownCard(),
                ),
                const SizedBox(height: 16),

                // AI Suggestions
                if (_suggestions.isNotEmpty) _buildSuggestionsCard(),
              ].animate(interval: 80.ms).fadeIn(duration: 300.ms).slideY(
                  begin: 0.06, end: 0, curve: Curves.easeOut),
            ),
    );
  }

  // ── Tappable card wrapper → insight bottom sheet ─────────────────────────
  Widget _tappableCard({
    required String id,
    required String name,
    required String value,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: () => _showInsightSheet(id: id, name: name, value: value),
      child: child,
    );
  }

  Future<void> _showInsightSheet({
    required String id,
    required String name,
    required String value,
  }) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AghieriColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _InsightDetailSheet(
        metricId: id,
        metricName: name,
        metricValue: value,
      ),
    );
  }

  Widget _buildTribeCard(TribeProfile tribe) {
    return _Card(
      accent: AghieriColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Pattern', style: AghieriTextStyles.heading(size: 16)),
          const SizedBox(height: 16),
          Row(
            children: [
              _TribeMetric('Trust', tribe.trust, AghieriColors.accent),
              _TribeMetric('Energy', tribe.energy, const Color(0xFF8AE86A)),
              _TribeMetric('Impulse', tribe.impulse, const Color(0xFFC46AE8)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(_rhythmIcon(tribe.rhythm),
                  size: 16, color: AghieriColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                _rhythmLabel(tribe.rhythm),
                style: AghieriTextStyles.body(
                    size: 13, color: AghieriColors.textSecondary),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AghieriColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Bandwidth: ${tribe.bandwidth.toStringAsFixed(0)}',
                  style: AghieriTextStyles.label(
                      size: 11, color: AghieriColors.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionCard() {
    final rate =
        _totalTasks > 0 ? (_completedTasks / _totalTasks * 100) : 0.0;
    return _Card(
      accent: const Color(0xFF8AE86A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Completion', style: AghieriTextStyles.heading(size: 16)),
              const Spacer(),
              Text('${rate.toStringAsFixed(0)}%',
                  style: AghieriTextStyles.heading(
                      size: 28, color: const Color(0xFF8AE86A))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _totalTasks > 0 ? _completedTasks / _totalTasks : 0,
              minHeight: 6,
              backgroundColor: AghieriColors.surfaceHigh,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF8AE86A)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_completedTasks of $_totalTasks tasks completed',
            style: AghieriTextStyles.body(
                size: 12, color: AghieriColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    // Find peak hour
    int peakHour = 0;
    int peakCount = 0;
    _hourly.forEach((h, c) {
      if (c > peakCount) {
        peakHour = h;
        peakCount = c;
      }
    });

    return _Card(
      accent: const Color(0xFFC46AE8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity', style: AghieriTextStyles.heading(size: 16)),
          const SizedBox(height: 4),
          if (peakCount > 0)
            Text(
              'Peak: ${_formatHour(peakHour)}',
              style: AghieriTextStyles.body(
                  size: 12, color: AghieriColors.textSecondary),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 60,
            child: CustomPaint(
              size: const Size(double.infinity, 60),
              painter: _HourlyBarPainter(
                hourly: _hourly,
                peakHour: peakHour,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('6am',
                  style: AghieriTextStyles.label(
                      size: 9, color: AghieriColors.textSecondary)),
              Text('12pm',
                  style: AghieriTextStyles.label(
                      size: 9, color: AghieriColors.textSecondary)),
              Text('6pm',
                  style: AghieriTextStyles.label(
                      size: 9, color: AghieriColors.textSecondary)),
              Text('12am',
                  style: AghieriTextStyles.label(
                      size: 9, color: AghieriColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    final entries = _typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = _typeCounts.values.fold(0, (a, b) => a + b);

    return _Card(
      accent: const Color(0xFFE8C96A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Interactions', style: AghieriTextStyles.heading(size: 16)),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text('No data yet',
                style: AghieriTextStyles.body(
                    size: 13, color: AghieriColors.textSecondary))
          else
            ...entries.take(5).map((e) {
              final pct = total > 0 ? e.value / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        _formatTypeName(e.key),
                        style: AghieriTextStyles.label(
                            size: 11, color: AghieriColors.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 4,
                          backgroundColor: AghieriColors.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation(
                              AghieriColors.accent.withOpacity(0.7)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${e.value}',
                        style: AghieriTextStyles.label(
                            size: 11, color: AghieriColors.textPrimary)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSuggestionsCard() {
    return _Card(
      accent: AghieriColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From Aghieri', style: AghieriTextStyles.heading(size: 16)),
          const SizedBox(height: 12),
          ..._suggestions.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AghieriColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['suggestion'] ?? '',
                              style: AghieriTextStyles.body(size: 13)),
                          if (s['reason'] != null)
                            Text(s['reason'],
                                style: AghieriTextStyles.body(
                                    size: 11,
                                    color: AghieriColors.textSecondary)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        final id = s['id'] as String?;
                        if (id != null) {
                          ProfileService.instance.dismissSuggestion(id);
                          setState(() => _suggestions.remove(s));
                        }
                      },
                      child: const Icon(Icons.close,
                          size: 14, color: AghieriColors.textSecondary),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _rhythmLabel(RhythmType r) {
    switch (r) {
      case RhythmType.earlyBird:
        return 'Early bird pattern';
      case RhythmType.nightOwl:
        return 'Night owl pattern';
      case RhythmType.flexible:
        return 'Flexible schedule';
    }
  }

  IconData _rhythmIcon(RhythmType r) {
    switch (r) {
      case RhythmType.earlyBird:
        return Icons.wb_sunny_outlined;
      case RhythmType.nightOwl:
        return Icons.nightlight_outlined;
      case RhythmType.flexible:
        return Icons.schedule_outlined;
    }
  }

  String _formatHour(int h) {
    if (h == 0) return '12 AM';
    if (h == 12) return '12 PM';
    return h > 12 ? '${h - 12} PM' : '$h AM';
  }

  String _formatTypeName(String raw) {
    // camelCase → Title Case
    return raw.replaceAllMapped(
        RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}').trim();
  }
}

// ── Reusable card ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Color accent;
  final Widget child;
  const _Card({required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AghieriColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AghieriColors.surfaceHigh, width: 1),
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ── TRIBE metric widget ──────────────────────────────────────────────────────

class _TribeMetric extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _TribeMetric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: value.clamp(0, 1),
                  strokeWidth: 3,
                  backgroundColor: AghieriColors.surfaceHigh,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Text(
                  '${(value * 100).toStringAsFixed(0)}',
                  style: AghieriTextStyles.label(size: 13, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: AghieriTextStyles.label(
                  size: 10, color: AghieriColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Hourly bar chart painter ─────────────────────────────────────────────────

// ── Insight detail bottom sheet ──────────────────────────────────────────────

class _InsightDetailSheet extends StatefulWidget {
  final String metricId;
  final String metricName;
  final String metricValue;

  const _InsightDetailSheet({
    required this.metricId,
    required this.metricName,
    required this.metricValue,
  });

  @override
  State<_InsightDetailSheet> createState() => _InsightDetailSheetState();
}

class _InsightDetailSheetState extends State<_InsightDetailSheet> {
  String? _description;
  bool _loading = true;
  List<Map<String, dynamic>> _recentActivity = [];

  @override
  void initState() {
    super.initState();
    _loadDescription();
    _loadRecentActivity();
  }

  Future<void> _loadDescription() async {
    // Check Firestore cache first (24h TTL)
    try {
      final uid = AuthService.instance.uid;
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('insight_descriptions')
          .doc(widget.metricId);

      final cached = await docRef.get();
      if (cached.exists) {
        final data = cached.data()!;
        final ts = data['cached_at'] as Timestamp?;
        if (ts != null) {
          final age = DateTime.now().difference(ts.toDate());
          if (age.inHours < 24) {
            if (mounted) {
              setState(() {
                _description = data['description'] as String?;
                _loading = false;
              });
            }
            return;
          }
        }
      }
    } catch (_) {}

    // Generate via Claude
    final prompt =
        'Explain in 2-3 sentences what "${widget.metricName}" tracks, '
        'what behaviors contributed to the current value of ${widget.metricValue}, '
        'and any trends. Calm, factual, non-judgmental. No motivational language.';

    final response = await ClaudeService.instance.chat(prompt);

    final desc = response.isNotEmpty
        ? response
        : _fallbackDescription(widget.metricId);

    // Cache in Firestore
    try {
      final uid = AuthService.instance.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('insight_descriptions')
          .doc(widget.metricId)
          .set({
        'description': desc,
        'cached_at': FieldValue.serverTimestamp(),
        'metric_name': widget.metricName,
        'metric_value': widget.metricValue,
      });
    } catch (_) {}

    if (mounted) {
      setState(() {
        _description = desc;
        _loading = false;
      });
    }
  }

  Future<void> _loadRecentActivity() async {
    try {
      final uid = AuthService.instance.uid;
      final snap = await FirebaseFirestore.instance
          .collection('portfolio')
          .doc(uid)
          .collection('interactions')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      if (mounted) {
        setState(() {
          _recentActivity = snap.docs
              .map((d) => d.data())
              .toList();
        });
      }
    } catch (_) {}
  }

  String _fallbackDescription(String id) {
    switch (id) {
      case 'tribe':
        return 'Your Pattern scores reflect how you interact with tasks and the app over time. Trust measures consistency, Energy reflects capacity, and Impulse tracks reactivity.';
      case 'completion':
        return 'Completion rate shows the proportion of created tasks you\'ve marked as done. A steady rate indicates good scoping; large swings may mean over-committing or batch-clearing.';
      case 'activity':
        return 'Activity distribution maps when you\'re most active throughout the day. Your peak hours suggest when you naturally focus best.';
      case 'interactions':
        return 'Interaction breakdown categorizes how you use the app — voice commands, manual entries, focus sessions, and more. The mix reveals your workflow patterns.';
      default:
        return 'This metric tracks a dimension of your productivity pattern over time.';
    }
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

          // Title
          Text(widget.metricName,
              style: AghieriTextStyles.heading(size: 18)),
          const SizedBox(height: 4),
          Text(widget.metricValue,
              style: AghieriTextStyles.heading(
                  size: 24, color: AghieriColors.accent)),
          const SizedBox(height: 20),

          // AI Description
          if (_loading)
            const SizedBox(
              height: 60,
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AghieriColors.accent),
                ),
              ),
            )
          else if (_description != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AghieriColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _description!,
                style: AghieriTextStyles.body(
                    size: 13, color: AghieriColors.textPrimary),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Recent activity log
          if (_recentActivity.isNotEmpty) ...[
            Text('Recent activity',
                style: AghieriTextStyles.label(
                    color: AghieriColors.textSecondary)),
            const SizedBox(height: 8),
            ...(_recentActivity.take(5).map((a) {
              final type = a['type'] as String? ?? 'unknown';
              final ts = a['timestamp'] as Timestamp?;
              final timeStr = ts != null
                  ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                  : '--:--';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: AghieriColors.accent.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _formatActivityType(type),
                        style: AghieriTextStyles.body(size: 12),
                      ),
                    ),
                    Text(timeStr,
                        style: AghieriTextStyles.label(
                            size: 10, color: AghieriColors.textSecondary)),
                  ],
                ),
              );
            })),
          ],
        ],
      ),
    );
  }

  String _formatActivityType(String raw) {
    return raw.replaceAllMapped(
        RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}').trim();
  }
}

// ── Hourly bar chart painter ─────────────────────────────────────────────────

class _HourlyBarPainter extends CustomPainter {
  final Map<int, int> hourly;
  final int peakHour;

  _HourlyBarPainter({required this.hourly, required this.peakHour});

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal = hourly.values.fold(0, max);
    if (maxVal == 0) return;

    final barW = size.width / 24 - 1;
    for (int h = 0; h < 24; h++) {
      final count = hourly[h] ?? 0;
      final ratio = count / maxVal;
      final barH = ratio * size.height * 0.9;
      final x = h * (size.width / 24);
      final isPeak = h == peakHour;

      final paint = Paint()
        ..color = isPeak
            ? const Color(0xFFC46AE8)
            : AghieriColors.accent.withOpacity(0.4);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barH, barW, barH),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
