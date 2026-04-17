import 'package:flutter/material.dart';

class SubCategory {
  final String id;
  final String name;

  const SubCategory({required this.id, required this.name});

  factory SubCategory.fromJson(Map<String, dynamic> j) => SubCategory(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  SubCategory copyWith({String? name}) =>
      SubCategory(id: id, name: name ?? this.name);
}

class TaskCategory {
  final String id;
  final String name;
  final String icon; // Material icon name
  final String colorHex;
  final List<SubCategory> subCategories;

  const TaskCategory({
    required this.id,
    required this.name,
    this.icon = 'folder',
    this.colorHex = '#6AAEE8',
    this.subCategories = const [],
  });

  Color get color {
    try {
      final hex = colorHex.replaceAll('#', '');
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}
    return const Color(0xFF6AAEE8);
  }

  IconData get iconData => _iconMap[icon] ?? Icons.folder_outlined;

  factory TaskCategory.fromJson(Map<String, dynamic> j) => TaskCategory(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        icon: j['icon'] ?? 'folder',
        colorHex: j['color_hex'] ?? '#6AAEE8',
        subCategories: ((j['sub_categories'] as List?) ?? [])
            .map((s) => SubCategory.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color_hex': colorHex,
        'sub_categories': subCategories.map((s) => s.toJson()).toList(),
      };

  TaskCategory copyWith({
    String? name,
    String? icon,
    String? colorHex,
    List<SubCategory>? subCategories,
  }) =>
      TaskCategory(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        colorHex: colorHex ?? this.colorHex,
        subCategories: subCategories ?? this.subCategories,
      );

  static const List<TaskCategory> defaults = [
    TaskCategory(
      id: 'personal',
      name: 'Personal',
      icon: 'person',
      colorHex: '#6AAEE8',
      subCategories: [
        SubCategory(id: 'notes', name: 'Notes'),
        SubCategory(id: 'reminders', name: 'Reminders'),
      ],
    ),
    TaskCategory(
      id: 'school',
      name: 'School',
      icon: 'school',
      colorHex: '#8AE86A',
      subCategories: [
        SubCategory(id: 'homework', name: 'Homework'),
        SubCategory(id: 'notes', name: 'Notes'),
      ],
    ),
    TaskCategory(
      id: 'work',
      name: 'Work',
      icon: 'work',
      colorHex: '#E8856A',
      subCategories: [
        SubCategory(id: 'tasks', name: 'Tasks'),
        SubCategory(id: 'meetings', name: 'Meetings'),
      ],
    ),
    TaskCategory(
      id: 'creative',
      name: 'Creative',
      icon: 'palette',
      colorHex: '#C46AE8',
      subCategories: [
        SubCategory(id: 'projects', name: 'Projects'),
        SubCategory(id: 'ideas', name: 'Ideas'),
      ],
    ),
  ];
}

// Static references so the icon tree-shaker keeps these glyphs
const _kPerson  = Icons.person_outline;
const _kSchool  = Icons.school_outlined;
const _kWork    = Icons.work_outline;
const _kPalette = Icons.palette_outlined;
const _kFolder  = Icons.folder_outlined;
const _kBook    = Icons.menu_book_rounded;
const _kCode    = Icons.code_rounded;
const _kFitness = Icons.fitness_center_rounded;
const _kMusic   = Icons.music_note_rounded;
const _kHome    = Icons.home_outlined;
const _kScience = Icons.science_outlined;
const _kStar    = Icons.star_outline_rounded;
const _kHeart   = Icons.favorite_outline;
const _kBolt    = Icons.bolt_rounded;
const _kCamera  = Icons.camera_alt_outlined;
const _kTravel  = Icons.flight_outlined;

const Map<String, IconData> _iconMap = {
  'person': _kPerson,
  'school': _kSchool,
  'work': _kWork,
  'palette': _kPalette,
  'folder': _kFolder,
  'book': _kBook,
  'code': _kCode,
  'fitness': _kFitness,
  'music': _kMusic,
  'home': _kHome,
  'science': _kScience,
  'star': _kStar,
  'heart': _kHeart,
  'bolt': _kBolt,
  'camera': _kCamera,
  'travel': _kTravel,
};

/// All available icon keys for the picker
const List<String> availableIcons = [
  'person', 'school', 'work', 'palette', 'folder', 'book',
  'code', 'fitness', 'music', 'home', 'science', 'star',
  'heart', 'bolt', 'camera', 'travel',
];

/// Get IconData from icon key
IconData iconFromKey(String key) => _iconMap[key] ?? Icons.folder_outlined;
