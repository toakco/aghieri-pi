class DeviceEntry {
  final String id;
  final String name;
  final String type; // phone | laptop | desktop | tablet
  final String? fcmToken;
  final bool isActive;

  const DeviceEntry({
    required this.id,
    required this.name,
    required this.type,
    this.fcmToken,
    this.isActive = true,
  });

  factory DeviceEntry.fromJson(Map<String, dynamic> j) => DeviceEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String? ?? 'phone',
        fcmToken: j['fcm_token'] as String?,
        isActive: j['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'fcm_token': fcmToken,
        'is_active': isActive,
      };

  DeviceEntry copyWith({
    String? name,
    String? type,
    String? fcmToken,
    bool? isActive,
  }) =>
      DeviceEntry(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        fcmToken: fcmToken ?? this.fcmToken,
        isActive: isActive ?? this.isActive,
      );
}
