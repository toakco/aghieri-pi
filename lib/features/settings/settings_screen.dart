import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/device_entry.dart';
import '../../models/user_profile.dart';
import '../../services/notification_service.dart';
import '../../services/profile_service.dart';
import '../../services/voice_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _deviceIpCtrl = TextEditingController();

  _TestState _deviceTest = _TestState.idle;
  _TestState _voiceTest  = _TestState.idle;
  bool _wifiAutoConnect  = true;
  UserProfile _profile = const UserProfile();

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = await ProfileService.instance.getProfile();
    if (!mounted) return;
    setState(() {
      _deviceIpCtrl.text = prefs.getString('device_ip') ?? '192.168.1.100';
      _wifiAutoConnect   = prefs.getBool('wifi_auto_connect') ?? true;
      _profile = profile;
    });
    // Auto-register this device if not already in profile
    _ensureThisDeviceRegistered(profile);
  }

  Future<void> _ensureThisDeviceRegistered(UserProfile profile) async {
    final token = NotificationService.instance.token;
    if (token == null) return;
    final alreadyRegistered = profile.devices.any((d) => d.fcmToken == token);
    if (alreadyRegistered) return;
    // Register current device as 'phone' by default
    final newDevice = DeviceEntry(
      id: const Uuid().v4(),
      name: 'My Phone',
      type: 'phone',
      fcmToken: token,
    );
    final updated = profile.copyWith(devices: [...profile.devices, newDevice]);
    await ProfileService.instance.saveProfile(updated);
    if (mounted) setState(() => _profile = updated);
  }

  Future<void> _saveDevice(DeviceEntry device) async {
    final idx = _profile.devices.indexWhere((d) => d.id == device.id);
    List<DeviceEntry> updated;
    if (idx >= 0) {
      updated = [..._profile.devices];
      updated[idx] = device;
    } else {
      updated = [..._profile.devices, device];
    }
    final newProfile = _profile.copyWith(devices: updated);
    await ProfileService.instance.saveProfile(newProfile);
    if (mounted) setState(() => _profile = newProfile);
  }

  Future<void> _deleteDevice(String id) async {
    final updated = _profile.devices.where((d) => d.id != id).toList();
    final newProfile = _profile.copyWith(devices: updated);
    await ProfileService.instance.saveProfile(newProfile);
    if (mounted) setState(() => _profile = newProfile);
  }

  @override
  void dispose() {
    _deviceIpCtrl.dispose();
    super.dispose();
  }

  // ── Save & test device IP ──────────────────────────────────────────────────
  Future<void> _saveDeviceIp() async {
    final ip = _deviceIpCtrl.text.trim();
    setState(() => _deviceTest = _TestState.loading);
    await VoiceService.instance.configure(deviceIp: ip);

    try {
      final resp = await http.get(
        Uri.parse('http://$ip:8000/health'),
      ).timeout(const Duration(seconds: 5));
      setState(() => _deviceTest =
          resp.statusCode == 200 ? _TestState.success : _TestState.failure);
    } catch (_) {
      setState(() => _deviceTest = _TestState.failure);
    }
  }

  // ── Test voice ─────────────────────────────────────────────────────────────
  Future<void> _testVoice() async {
    setState(() => _voiceTest = _TestState.loading);
    try {
      await VoiceService.instance.speak('Hello. I am Aghieri, your productivity companion.');
      if (mounted) setState(() => _voiceTest = _TestState.success);
    } catch (_) {
      if (mounted) setState(() => _voiceTest = _TestState.failure);
    }
  }

  Future<void> _toggleWifiAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_auto_connect', value);
    setState(() => _wifiAutoConnect = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      appBar: AppBar(
        backgroundColor: AghieriColors.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AghieriColors.textSecondary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings', style: AghieriTextStyles.heading(size: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [

          // ── Voice ─────────────────────────────────────────────────────────
          _Section(
            label: 'Voice',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.record_voice_over_outlined,
                            color: AghieriColors.accent, size: 20),
                        const SizedBox(width: 12),
                        Text('Antonio',
                            style: AghieriTextStyles.body(
                                size: 15, weight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 32),
                      child: Text(
                        'Lively, engaging — Aghieri\'s default voice',
                        style: AghieriTextStyles.caption(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.only(left: 32),
                      child: Row(
                        children: [
                          _TestButton(
                            label: 'Test voice',
                            state: _voiceTest,
                            onTap: _testVoice,
                          ),
                          const SizedBox(width: 12),
                          if (_voiceTest == _TestState.success)
                            _StatusBadge(
                              text: 'Voice active',
                              color: AghieriColors.accent,
                            ),
                          if (_voiceTest == _TestState.failure)
                            _StatusBadge(
                              text: 'Voice unavailable',
                              color: const Color(0xFFE08080),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _SimpleTile(
                icon: Icons.mic_none_rounded,
                title: 'Test microphone',
                subtitle: 'Speaks back what you say',
                onTap: () async {
                  final t = await VoiceService.instance.listen();
                  if (t.isNotEmpty) {
                    await VoiceService.instance.speak('I heard: $t');
                  }
                },
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
            ],
          ).animate().fadeIn(delay: 80.ms, duration: 300.ms),

          const SizedBox(height: 20),

          // ── Connectivity ──────────────────────────────────────────────────
          _Section(
            label: 'Connectivity',
            children: [
              _SimpleTile(
                icon: Icons.wifi_outlined,
                title: 'WiFi auto-connect',
                subtitle: 'Automatically find Aghieri device on local network',
                trailing: Switch.adaptive(
                  value: _wifiAutoConnect,
                  onChanged: _toggleWifiAutoConnect,
                  activeColor: AghieriColors.accent,
                ),
              ),
              _SettingsTile(
                icon: Icons.device_hub_outlined,
                title: 'Device IP Address',
                subtitle: 'Manual connection to your Aghieri device',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _deviceIpCtrl,
                      style: AghieriTextStyles.body(size: 14),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\.]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: '192.168.1.100',
                        prefixText: 'http://',
                        suffixText: ':8000',
                      ),
                      onSubmitted: (_) => _saveDeviceIp(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _TestButton(
                          label: 'Save & ping',
                          state: _deviceTest,
                          onTap: _saveDeviceIp,
                        ),
                        const SizedBox(width: 12),
                        if (_deviceTest == _TestState.success)
                          _StatusBadge(
                            text: 'Reachable',
                            color: AghieriColors.accent,
                          ),
                        if (_deviceTest == _TestState.failure)
                          _StatusBadge(
                            text: 'Not found',
                            color: const Color(0xFFE08080),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _SimpleTile(
                icon: Icons.signal_wifi_statusbar_4_bar_outlined,
                title: 'Connection status',
                trailing: _ConnectivityBadge(
                    status: VoiceService.instance.currentStatus),
              ),
              _SimpleTile(
                icon: Icons.qr_code_2_rounded,
                title: 'Pair phone to device',
                subtitle: 'Scan QR on Aghieri device to log in',
                onTap: () => _showPairingInfo(context),
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
            ],
          ).animate().fadeIn(delay: 100.ms, duration: 300.ms),

          const SizedBox(height: 20),

          // ── Data ─────────────────────────────────────────────────────────
          _Section(
            label: 'Data',
            children: [
              _SimpleTile(
                icon: Icons.insights_outlined,
                title: 'Your data',
                subtitle: 'Activity insights and analytics',
                onTap: () => context.push('/portfolio'),
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
              _SimpleTile(
                icon: Icons.integration_instructions_outlined,
                title: 'Integrations',
                subtitle: 'Google Calendar · Notion',
                onTap: () => context.push('/integrations'),
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
              _SimpleTile(
                icon: Icons.account_circle_outlined,
                title: 'Sign in',
                subtitle: 'Sync across phone, web, and device',
                onTap: () => context.push('/sign-in'),
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
              _SimpleTile(
                icon: Icons.replay_outlined,
                title: 'Redo onboarding',
                subtitle: 'Re-pick preferences and display style',
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('aghieri_onboarded');
                  if (context.mounted) context.go('/onboarding');
                },
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
              _SimpleTile(
                icon: Icons.delete_outline,
                title: 'Clear all data',
                subtitle: 'Removes all tasks, alarms, and profile',
                onTap: () => _confirmClear(context),
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
            ],
          ).animate().fadeIn(delay: 150.ms, duration: 300.ms),

          const SizedBox(height: 20),

          // ── Devices ──────────────────────────────────────────────────────
          _DevicesSection(
            devices: _profile.devices,
            onSave: _saveDevice,
            onDelete: _deleteDevice,
          ).animate().fadeIn(delay: 170.ms, duration: 300.ms),

          const SizedBox(height: 20),

          // ── Legal ────────────────────────────────────────────────────────
          _Section(
            label: 'Legal',
            children: [
              _SimpleTile(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                onTap: () => _showTermsDialog(context),
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
              _SimpleTile(
                icon: Icons.shield_outlined,
                title: 'Privacy Policy',
                onTap: () => _showPrivacyDialog(context),
                trailing: const Icon(Icons.chevron_right,
                    color: AghieriColors.textSecondary, size: 18),
              ),
            ],
          ).animate().fadeIn(delay: 200.ms, duration: 300.ms),

          const SizedBox(height: 20),

          // ── About ────────────────────────────────────────────────────────
          _Section(
            label: 'About',
            children: [
              _SimpleTile(
                icon: Icons.info_outline,
                title: 'Aghieri',
                subtitle: 'v1.0.0 · TOAKCO LLC · DS-483 Capstone',
              ),
            ],
          ).animate().fadeIn(delay: 250.ms, duration: 300.ms),
        ],
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AghieriColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Terms of Service',
            style: AghieriTextStyles.heading(size: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Text(
              'Last updated: April 2026\n\n'
              '1. Acceptance of Terms\n'
              'By using Aghieri, you agree to these terms. Aghieri is an ADHD-focused productivity '
              'companion designed to help you manage tasks, focus sessions, and daily routines.\n\n'
              '2. Privacy & Data\n'
              'Aghieri processes voice commands locally on your device when possible. '
              'Cloud processing (Claude AI, ElevenLabs) is used for natural language understanding '
              'and voice synthesis. No conversation data is stored on external servers beyond '
              'the duration of processing.\n\n'
              '3. Health Disclaimer\n'
              'Aghieri is not a medical device and does not provide medical advice. '
              'It is a productivity tool designed with ADHD-friendly principles. '
              'Consult a healthcare professional for medical guidance.\n\n'
              '4. Data Storage\n'
              'Your tasks, preferences, and profile are stored in Firebase (Google Cloud) '
              'under your anonymous account. You can delete all data at any time from Settings.\n\n'
              '5. Third-Party Services\n'
              'Aghieri integrates with Google Calendar and Notion with your explicit permission. '
              'These integrations are read-only and can be disconnected at any time.\n\n'
              '6. Intellectual Property\n'
              'Aghieri is a product of TOAKCO LLC, developed as part of the DS-483 Capstone '
              'at NC State University. All rights reserved.',
              style: AghieriTextStyles.body(
                  size: 13, color: AghieriColors.textSecondary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: AghieriTextStyles.body(color: AghieriColors.accent)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AghieriColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Privacy Policy',
            style: AghieriTextStyles.heading(size: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Text(
              'Last updated: April 2026\n\n'
              'Your privacy matters. Here\'s how Aghieri handles your data:\n\n'
              'What we collect:\n'
              '• Profile info you provide during onboarding (name, preferences)\n'
              '• Tasks and focus session data you create\n'
              '• Voice input (processed in real-time, not stored)\n\n'
              'What we don\'t collect:\n'
              '• Location data\n'
              '• Contact lists\n'
              '• Browsing history\n'
              '• Data from other apps\n\n'
              'Where data lives:\n'
              '• On your device (SharedPreferences)\n'
              '• Firebase Cloud Firestore (synced tasks & profile)\n'
              '• Calendar/Notion data stays with those services\n\n'
              'Third-party processing:\n'
              '• Anthropic (Claude AI) — processes voice commands\n'
              '• ElevenLabs — generates voice responses\n'
              '• Google Firebase — authentication & storage\n\n'
              'Your rights:\n'
              '• Delete all data anytime from Settings\n'
              '• Disconnect integrations anytime\n'
              '• No data is sold or shared with advertisers',
              style: AghieriTextStyles.body(
                  size: 13, color: AghieriColors.textSecondary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: AghieriTextStyles.body(color: AghieriColors.accent)),
          ),
        ],
      ),
    );
  }

  void _showPairingInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AghieriColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Device Pairing', style: AghieriTextStyles.heading(size: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  color: AghieriColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AghieriColors.accent.withOpacity(0.3)),
                ),
                child: const Center(
                  child: Icon(Icons.qr_code_2_rounded,
                      size: 80, color: AghieriColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'When your Aghieri device is powered on, it displays '
              'a QR code on its LED ring. Scan it with your phone camera '
              'to pair automatically.',
              style: AghieriTextStyles.body(
                  size: 13, color: AghieriColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              'The device and phone must be on the same WiFi network.',
              style: AghieriTextStyles.caption(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it',
                style: AghieriTextStyles.body(color: AghieriColors.accent)),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AghieriColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear all data?',
            style: AghieriTextStyles.heading(size: 16)),
        content: Text(
          'This removes your profile, tasks, and alarms. '
          'It cannot be undone.',
          style: AghieriTextStyles.body(
              size: 14, color: AghieriColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AghieriTextStyles.caption()),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (context.mounted) {
                Navigator.pop(context);
                context.go('/onboarding');
              }
            },
            child: Text('Clear',
                style: AghieriTextStyles.body(
                    size: 14, color: const Color(0xFFE08080))),
          ),
        ],
      ),
    );
  }
}

// ── Layout components ─────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _Section({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label.toUpperCase(),
              style: AghieriTextStyles.label(size: 11)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AghieriColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: children
                .asMap()
                .entries
                .map((e) => Column(
                      children: [
                        e.value,
                        if (e.key < children.length - 1)
                          const Divider(
                            height: 1,
                            indent: 52,
                            color: AghieriColors.surfaceHigh,
                          ),
                      ],
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AghieriColors.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AghieriTextStyles.body(size: 14)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: AghieriTextStyles.caption(),
                          maxLines: 2),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SimpleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SimpleTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: AghieriColors.accent.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AghieriColors.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AghieriTextStyles.body(size: 14)),
                    if (subtitle != null)
                      Text(subtitle!, style: AghieriTextStyles.caption()),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status widgets ────────────────────────────────────────────────────────────

enum _TestState { idle, loading, success, failure }

class _TestButton extends StatelessWidget {
  final String label;
  final _TestState state;
  final VoidCallback onTap;

  const _TestButton({
    required this.label,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: state == _TestState.loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: state == _TestState.loading
              ? AghieriColors.surfaceHigh
              : AghieriColors.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: state == _TestState.loading
                ? Colors.transparent
                : AghieriColors.accent.withOpacity(0.4),
          ),
        ),
        child: state == _TestState.loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AghieriColors.accent,
                ),
              )
            : Text(label,
                style: AghieriTextStyles.body(
                    size: 13, color: AghieriColors.accent)),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(text,
          style: AghieriTextStyles.caption(color: color)),
    );
  }
}

class _ServiceStatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool status;

  const _ServiceStatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AghieriColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AghieriTextStyles.body(size: 14)),
                Text(subtitle, style: AghieriTextStyles.caption()),
              ],
            ),
          ),
          Icon(
            status ? Icons.check_circle : Icons.cancel_outlined,
            color: status ? AghieriColors.accent : const Color(0xFFE08080),
            size: 18,
          ),
        ],
      ),
    );
  }
}

// ── Devices section ───────────────────────────────────────────────────────────

IconData _deviceIcon(String type) => switch (type) {
      'phone'   => Icons.smartphone_outlined,
      'laptop'  => Icons.laptop_mac_outlined,
      'desktop' => Icons.desktop_mac_outlined,
      'tablet'  => Icons.tablet_outlined,
      _         => Icons.devices_outlined,
    };

class _DevicesSection extends StatelessWidget {
  final List<DeviceEntry> devices;
  final void Function(DeviceEntry) onSave;
  final void Function(String) onDelete;

  const _DevicesSection({
    required this.devices,
    required this.onSave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DEVICES', style: AghieriTextStyles.label(size: 11)),
              GestureDetector(
                onTap: () => _showDeviceSheet(context, null),
                child: const Icon(Icons.add, color: AghieriColors.accent, size: 18),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AghieriColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: devices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No devices added. Tap + to register this device.',
                    style: AghieriTextStyles.caption(),
                  ),
                )
              : Column(
                  children: devices.asMap().entries.map((e) {
                    final device = e.value;
                    return Column(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showDeviceSheet(context, device),
                            borderRadius: BorderRadius.circular(16),
                            splashColor: AghieriColors.accent.withOpacity(0.08),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(_deviceIcon(device.type),
                                      color: AghieriColors.textSecondary, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(device.name,
                                            style: AghieriTextStyles.body(size: 14)),
                                        Text(device.type,
                                            style: AghieriTextStyles.caption()),
                                      ],
                                    ),
                                  ),
                                  if (device.fcmToken != null)
                                    const Icon(Icons.notifications_active_outlined,
                                        color: AghieriColors.accent, size: 16),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right,
                                      color: AghieriColors.textSecondary, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (e.key < devices.length - 1)
                          const Divider(
                              height: 1, indent: 52, color: AghieriColors.surfaceHigh),
                      ],
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  void _showDeviceSheet(BuildContext context, DeviceEntry? existing) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AghieriColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DeviceSheet(
        existing: existing,
        onSave: onSave,
        onDelete: existing != null ? () => onDelete(existing.id) : null,
      ),
    );
  }
}

class _DeviceSheet extends StatefulWidget {
  final DeviceEntry? existing;
  final void Function(DeviceEntry) onSave;
  final VoidCallback? onDelete;

  const _DeviceSheet({this.existing, required this.onSave, this.onDelete});

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  late TextEditingController _nameCtrl;
  late String _type;

  static const _types = ['phone', 'laptop', 'desktop', 'tablet'];
  static const _typeLabels = ['Phone', 'Laptop', 'Desktop', 'Tablet'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _type = widget.existing?.type ?? 'phone';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
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
          Row(
            children: [
              Text(widget.existing == null ? 'Add device' : 'Edit device',
                  style: AghieriTextStyles.heading(size: 18)),
              const Spacer(),
              if (widget.onDelete != null)
                TextButton(
                  onPressed: () {
                    widget.onDelete!();
                    Navigator.pop(context);
                  },
                  child: Text('Remove',
                      style: AghieriTextStyles.caption(
                          color: const Color(0xFFE88A6A))),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            style: AghieriTextStyles.body(size: 15),
            decoration: const InputDecoration(hintText: 'Device name'),
          ),
          const SizedBox(height: 20),
          Text('Device type', style: AghieriTextStyles.label()),
          const SizedBox(height: 10),
          Row(
            children: List.generate(_types.length, (i) {
              final selected = _type == _types[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _type = _types[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? AghieriColors.accent.withOpacity(0.15)
                          : AghieriColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AghieriColors.accent
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(_deviceIcon(_types[i]),
                            color: selected
                                ? AghieriColors.accent
                                : AghieriColors.textSecondary,
                            size: 22),
                        const SizedBox(height: 4),
                        Text(_typeLabels[i],
                            style: AghieriTextStyles.label(
                              size: 10,
                              color: selected
                                  ? AghieriColors.accent
                                  : AghieriColors.textSecondary,
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final name = _nameCtrl.text.trim();
                if (name.isEmpty) return;
                widget.onSave(DeviceEntry(
                  id: widget.existing?.id ?? const Uuid().v4(),
                  name: name,
                  type: _type,
                  fcmToken: widget.existing?.fcmToken ??
                      NotificationService.instance.token,
                ));
                Navigator.pop(context);
              },
              child: const Text('Save device'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityBadge extends StatelessWidget {
  final ConnectivityStatus status;
  const _ConnectivityBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      ConnectivityStatus.deviceOnline => ('Device online', AghieriColors.accent),
      ConnectivityStatus.online       => ('WiFi only',     const Color(0xFF7BB8D4)),
      ConnectivityStatus.offline      => ('Offline',       AghieriColors.textSecondary),
    };
    return _StatusBadge(text: text, color: color);
  }
}
