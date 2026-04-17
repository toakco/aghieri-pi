import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/theme/app_theme.dart';

/// Polls /device/status and provides a compact control row:
/// mute toggle | volume slider | sleep | power-off.
///
/// Used as a floating control bar on HomeScreen and FocusScreen.
class DeviceControlBar extends StatefulWidget {
  const DeviceControlBar({super.key});

  @override
  State<DeviceControlBar> createState() => _DeviceControlBarState();
}

class _DeviceControlBarState extends State<DeviceControlBar> {
  static const _base = 'http://192.168.1.100:8000';

  bool   _muted  = false;
  int    _volume = 80;
  bool   _asleep = false;
  bool   _online = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return; // No local device on web — skip all polling
    _fetchStatus();
    // Poll every 5 seconds to stay in sync with physical button presses
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/device/status'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _muted  = data['muted']  as bool? ?? false;
            _volume = data['volume'] as int?  ?? 80;
            _asleep = data['asleep'] as bool? ?? false;
            _online = true;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _online = false);
    }
  }

  Future<void> _toggleMute() async {
    HapticFeedback.lightImpact();
    try {
      final resp = await http
          .post(Uri.parse('$_base/device/mute'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _muted = data['muted'] as bool? ?? !_muted);
      }
    } catch (_) {}
  }

  Future<void> _setVolume(int level) async {
    setState(() => _volume = level);
    try {
      await http.post(
        Uri.parse('$_base/device/volume'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'level': level}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _toggleSleep() async {
    HapticFeedback.lightImpact();
    try {
      final endpoint = _asleep ? 'wake' : 'sleep';
      final resp = await http
          .post(Uri.parse('$_base/device/$endpoint'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _asleep = data['asleep'] as bool? ?? !_asleep);
      }
    } catch (_) {}
  }

  Future<void> _confirmShutdown() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ShutdownDialog(),
    );
    if (confirmed == true) {
      try {
        await http
            .post(Uri.parse('$_base/device/shutdown'))
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_online) {
      // Show a minimal offline indicator — don't take up space when not connected
      return const _OfflineChip();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AghieriColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _muted
              ? const Color(0xFFD48810).withOpacity(0.5)  // amber when muted
              : AghieriColors.surfaceHigh,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Mute toggle ────────────────────────────────────────────────────
          _ControlButton(
            icon: _muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
            color: _muted ? const Color(0xFFD48810) : AghieriColors.textSecondary,
            tooltip: _muted ? 'Unmute' : 'Mute',
            onTap: _toggleMute,
          ),
          const SizedBox(width: 6),

          // ── Volume slider ──────────────────────────────────────────────────
          Expanded(
            child: Row(
              children: [
                Icon(
                  _volume == 0
                      ? Icons.volume_off_rounded
                      : _volume < 50
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  color: AghieriColors.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: AghieriColors.accent,
                      inactiveTrackColor: AghieriColors.surfaceHigh,
                      thumbColor: AghieriColors.accent,
                      overlayColor: AghieriColors.accent.withOpacity(0.15),
                    ),
                    child: Slider(
                      value: _volume.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 10,
                      onChanged: (v) => setState(() => _volume = v.round()),
                      onChangeEnd: (v) => _setVolume(v.round()),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${_volume}%',
                    style: AghieriTextStyles.caption(size: 11),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // ── Sleep toggle ───────────────────────────────────────────────────
          _ControlButton(
            icon: _asleep ? Icons.bedtime_rounded : Icons.bedtime_outlined,
            color: _asleep ? AghieriColors.accent : AghieriColors.textSecondary,
            tooltip: _asleep ? 'Wake device' : 'Sleep',
            onTap: _toggleSleep,
          ),
          const SizedBox(width: 2),

          // ── Power ──────────────────────────────────────────────────────────
          _ControlButton(
            icon: Icons.power_settings_new_rounded,
            color: AghieriColors.textSecondary,
            tooltip: 'Shut down device',
            onTap: _confirmShutdown,
          ),
        ],
      ),
    );
  }
}

// ── Compact icon button ───────────────────────────────────────────────────────

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_)   => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed
                ? AghieriColors.surfaceHigh
                : Colors.transparent,
          ),
          child: Icon(widget.icon, color: widget.color, size: 18),
        ),
      ),
    );
  }
}

// ── Offline indicator ─────────────────────────────────────────────────────────

class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AghieriColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AghieriColors.surfaceHigh),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF5A5A6A),
              ),
            ),
            const SizedBox(width: 7),
            Text('Device offline',
                style: AghieriTextStyles.caption(size: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Shutdown confirmation dialog ──────────────────────────────────────────────

class _ShutdownDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AghieriColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Shut down Aghieri?',
          style: AghieriTextStyles.body(size: 16, weight: FontWeight.w500)),
      content: Text(
        'The device will power off. You can wake it by pressing the power button.',
        style: AghieriTextStyles.caption(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: AghieriTextStyles.caption()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Shut down',
              style: AghieriTextStyles.caption(color: AghieriColors.accent)),
        ),
      ],
    );
  }
}
