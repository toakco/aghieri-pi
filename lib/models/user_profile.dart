import 'category_model.dart';
import 'device_entry.dart';

class UserProfile {
  final String? uid;
  final String name;
  final String preferredName;
  final String? pronouns;
  final List<String> interests;
  final String adhdComfort;
  final String schedulePreference;  // morning | night_owl | flexible
  final String wakeTime;            // '07:00'
  final String sleepTime;           // '23:00'
  final bool voiceEnabled;
  final bool onboardingComplete;
  final String uiMode;              // 'day_clock' | 'task_progress' | 'abstract'
  final String typographyMode;      // 'default' | 'classic' | 'adaptive'
  final DateTime? tosAcceptedAt;
  final String? avatarUrl;
  final List<TaskCategory> categories;
  final List<DeviceEntry> devices;
  final Map<String, String> topicPlaylists; // interest/topic → Spotify playlist URI

  const UserProfile({
    this.uid,
    this.name = '',
    this.preferredName = '',
    this.pronouns,
    this.interests = const [],
    this.adhdComfort = 'prefer not to say',
    this.schedulePreference = 'flexible',
    this.wakeTime = '07:00',
    this.sleepTime = '23:00',
    this.voiceEnabled = true,
    this.onboardingComplete = false,
    this.uiMode = 'abstract',
    this.typographyMode = 'default',
    this.tosAcceptedAt,
    this.avatarUrl,
    this.categories = const [],
    this.devices = const [],
    this.topicPlaylists = const {},
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    uid: j['uid'],
    name: j['name'] ?? '',
    preferredName: j['preferred_name'] ?? '',
    pronouns: j['pronouns'],
    interests: List<String>.from(j['interests'] ?? []),
    adhdComfort: j['adhd_comfort'] ?? 'prefer not to say',
    schedulePreference: j['schedule_preference'] ?? 'flexible',
    wakeTime: j['wake_time'] ?? '07:00',
    sleepTime: j['sleep_time'] ?? '23:00',
    voiceEnabled: j['voice_enabled'] ?? true,
    onboardingComplete: j['onboarding_complete'] ?? false,
    uiMode: j['ui_mode'] ?? 'abstract',
    typographyMode: j['typography_mode'] ?? 'default',
    tosAcceptedAt: j['tos_accepted_at'] != null
        ? (j['tos_accepted_at'] is DateTime
            ? j['tos_accepted_at'] as DateTime
            : DateTime.tryParse(j['tos_accepted_at'].toString()))
        : null,
    avatarUrl: j['avatar_url'] as String?,
    categories: ((j['categories'] as List?) ?? [])
        .map((c) => TaskCategory.fromJson(c as Map<String, dynamic>))
        .toList(),
    devices: ((j['devices'] as List?) ?? [])
        .map((d) => DeviceEntry.fromJson(d as Map<String, dynamic>))
        .toList(),
    topicPlaylists: Map<String, String>.from(j['topic_playlists'] as Map? ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'preferred_name': preferredName,
    'pronouns': pronouns,
    'interests': interests,
    'adhd_comfort': adhdComfort,
    'schedule_preference': schedulePreference,
    'wake_time': wakeTime,
    'sleep_time': sleepTime,
    'voice_enabled': voiceEnabled,
    'onboarding_complete': onboardingComplete,
    'ui_mode': uiMode,
    'typography_mode': typographyMode,
    'tos_accepted_at': tosAcceptedAt?.toIso8601String(),
    'avatar_url': avatarUrl,
    'categories': categories.map((c) => c.toJson()).toList(),
    'devices': devices.map((d) => d.toJson()).toList(),
    'topic_playlists': topicPlaylists,
  };

  UserProfile copyWith({
    String? name,
    String? preferredName,
    String? pronouns,
    List<String>? interests,
    String? adhdComfort,
    String? schedulePreference,
    String? wakeTime,
    String? sleepTime,
    bool? voiceEnabled,
    bool? onboardingComplete,
    String? uiMode,
    String? typographyMode,
    DateTime? tosAcceptedAt,
    String? avatarUrl,
    List<TaskCategory>? categories,
    List<DeviceEntry>? devices,
    Map<String, String>? topicPlaylists,
  }) => UserProfile(
    uid: uid,
    name: name ?? this.name,
    preferredName: preferredName ?? this.preferredName,
    pronouns: pronouns ?? this.pronouns,
    interests: interests ?? this.interests,
    adhdComfort: adhdComfort ?? this.adhdComfort,
    schedulePreference: schedulePreference ?? this.schedulePreference,
    wakeTime: wakeTime ?? this.wakeTime,
    sleepTime: sleepTime ?? this.sleepTime,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    uiMode: uiMode ?? this.uiMode,
    typographyMode: typographyMode ?? this.typographyMode,
    tosAcceptedAt: tosAcceptedAt ?? this.tosAcceptedAt,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    categories: categories ?? this.categories,
    devices: devices ?? this.devices,
    topicPlaylists: topicPlaylists ?? this.topicPlaylists,
  );

  String get displayName => preferredName.isNotEmpty ? preferredName : name;
}

// ── Interest Options (onboarding) ─────────────────────────────────────────────
const kInterestOptions = [
  'Music', 'Art', 'Technology', 'Sports', 'News',
  'Science', 'Film', 'Gaming', 'Business', 'Nature',
  'Food', 'Travel', 'Books', 'Health', 'Design',
];
