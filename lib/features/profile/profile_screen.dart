import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/category_model.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile _profile = const UserProfile();
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile     = await ProfileService.instance.getProfile();
    final suggestions = await ProfileService.instance.getSuggestions();
    if (mounted) {
      setState(() {
        _profile     = profile;
        _suggestions = suggestions;
        _loading     = false;
      });
    }
  }

  Future<void> _pickAvatar() async {
    final uid = AuthService.instance.uid;
    if (uid == 'local') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sign in to add a profile photo.',
              style: AghieriTextStyles.body(size: 14)),
          backgroundColor: AghieriColors.surface,
        ));
      }
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;

    setState(() => _uploadingAvatar = true);
    try {
      final ref = FirebaseStorage.instance.ref('users/$uid/avatar.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await ProfileService.instance.saveProfile(
        _profile.copyWith(avatarUrl: url),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not upload: ${e.toString().split(']').last.trim()}',
              style: AghieriTextStyles.body(size: 13)),
          backgroundColor: AghieriColors.surface,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AghieriColors.bg,
      appBar: AppBar(
        backgroundColor: AghieriColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AghieriColors.textSecondary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Profile', style: AghieriTextStyles.heading(size: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined,
                color: AghieriColors.textSecondary, size: 20),
            onPressed: () => context.push('/portfolio'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: AghieriColors.textSecondary, size: 20),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AghieriColors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
              children: [
                // Name + pronouns + tappable avatar
                _ProfileHeader(
                  profile: _profile,
                  onAvatarTap: _pickAvatar,
                  uploading: _uploadingAvatar,
                ).animate().fadeIn(),

                const SizedBox(height: 28),
                const Divider(color: AghieriColors.surfaceHigh),
                const SizedBox(height: 20),

                // Interests
                if (_profile.interests.isNotEmpty) ...[
                  Text('Interests', style: AghieriTextStyles.label(size: 12)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _profile.interests.map((i) => _Chip(label: i)).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // Categories
                _CategoriesSection(
                  categories: _profile.categories.isNotEmpty
                      ? _profile.categories
                      : TaskCategory.defaults,
                  onUpdate: (cats) async {
                    await ProfileService.instance.saveProfile(
                      _profile.copyWith(categories: cats),
                    );
                    _load();
                  },
                ),
                const SizedBox(height: 24),

                // Aghieri suggestions
                if (_suggestions.isNotEmpty) ...[
                  Text('From Aghieri', style: AghieriTextStyles.label(size: 12)),
                  const SizedBox(height: 10),
                  ..._suggestions.asMap().entries.map((e) => _SuggestionCard(
                    suggestion: e.value,
                    onDismiss: () async {
                      final id = e.value['id'] as String? ?? '';
                      await ProfileService.instance.dismissSuggestion(id);
                      _load();
                    },
                  ).animate().fadeIn(delay: (e.key * 60).ms)),
                  const SizedBox(height: 24),
                ],

                // Privacy note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AghieriColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your data', style: AghieriTextStyles.body(
                          size: 13, weight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Text(
                        'Aghieri tracks when you create tasks and how you use the app — '
                        'never what you say or behavioral scores. '
                        'You can delete everything from Settings.',
                        style: AghieriTextStyles.caption(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback? onAvatarTap;
  final bool uploading;
  const _ProfileHeader({required this.profile, this.onAvatarTap, this.uploading = false});

  @override
  Widget build(BuildContext context) {
    final hasAvatar = profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;
    return Row(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AghieriColors.surface,
                  border: Border.all(
                      color: AghieriColors.accent.withOpacity(0.4), width: 1),
                ),
                child: hasAvatar
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: profile.avatarUrl!,
                          width: 56, height: 56,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Center(
                            child: Text(
                              profile.displayName.isNotEmpty
                                  ? profile.displayName[0].toUpperCase()
                                  : 'A',
                              style: AghieriTextStyles.heading(size: 22),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Center(
                            child: Text(
                              profile.displayName.isNotEmpty
                                  ? profile.displayName[0].toUpperCase()
                                  : 'A',
                              style: AghieriTextStyles.heading(size: 22),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          profile.displayName.isNotEmpty
                              ? profile.displayName[0].toUpperCase()
                              : 'A',
                          style: AghieriTextStyles.heading(size: 22),
                        ),
                      ),
              ),
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: AghieriColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AghieriColors.bg, width: 2),
                  ),
                  child: uploading
                      ? const Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt, size: 9, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.displayName.isNotEmpty ? profile.displayName : 'Aghieri',
              style: AghieriTextStyles.heading(size: 18),
            ),
            if (profile.pronouns != null && profile.pronouns!.isNotEmpty)
              Text(profile.pronouns!,
                  style: AghieriTextStyles.caption()),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AghieriColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AghieriColors.surfaceHigh),
      ),
      child: Text(label, style: AghieriTextStyles.caption()),
    );
  }
}

// ── Categories Section ───────────────────────────────────────────────────────

class _CategoriesSection extends StatelessWidget {
  final List<TaskCategory> categories;
  final void Function(List<TaskCategory>) onUpdate;

  const _CategoriesSection({
    required this.categories,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Categories', style: AghieriTextStyles.label(size: 12)),
            GestureDetector(
              onTap: () => _addCategory(context),
              child: const Icon(Icons.add,
                  color: AghieriColors.accent, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...categories.asMap().entries.map((e) {
          final cat = e.value;
          return GestureDetector(
            onTap: () => _editCategory(context, e.key, cat),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AghieriColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cat.color.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: cat.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(cat.iconData, color: cat.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat.name,
                            style: AghieriTextStyles.body(
                                size: 14, weight: FontWeight.w500)),
                        if (cat.subCategories.isNotEmpty)
                          Text(
                            cat.subCategories.map((s) => s.name).join(', '),
                            style: AghieriTextStyles.caption(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AghieriColors.textSecondary, size: 18),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _addCategory(BuildContext context) {
    final newCat = TaskCategory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Category',
      icon: 'folder',
      colorHex: '#6AAEE8',
    );
    final updated = [...categories, newCat];
    onUpdate(updated);
  }

  void _editCategory(BuildContext context, int index, TaskCategory cat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AghieriColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryEditSheet(
        category: cat,
        onSave: (updated) {
          final list = [...categories];
          list[index] = updated;
          onUpdate(list);
        },
        onDelete: () {
          final list = [...categories];
          list.removeAt(index);
          onUpdate(list);
        },
      ),
    );
  }
}

// ── Category Edit Bottom Sheet ──────────────────────────────────────────────

class _CategoryEditSheet extends StatefulWidget {
  final TaskCategory category;
  final void Function(TaskCategory) onSave;
  final VoidCallback onDelete;

  const _CategoryEditSheet({
    required this.category,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<_CategoryEditSheet> {
  late TextEditingController _nameCtrl;
  late String _icon;
  late String _colorHex;
  late List<SubCategory> _subs;
  final _subCtrl = TextEditingController();

  static const _colors = [
    '#E8856A', '#6AAEE8', '#8AE86A', '#C46AE8',
    '#E8C96A', '#6AE8D4', '#E86AAB', '#A8E86A',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.category.name);
    _icon = widget.category.icon;
    _colorHex = widget.category.colorHex;
    _subs = List.from(widget.category.subCategories);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(widget.category.copyWith(
      name: _nameCtrl.text.trim(),
      icon: _icon,
      colorHex: _colorHex,
      subCategories: _subs,
    ));
    Navigator.pop(context);
  }

  void _addSub() {
    final name = _subCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _subs.add(SubCategory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
      ));
      _subCtrl.clear();
    });
  }

  Color _hexToColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    } catch (_) {}
    return const Color(0xFF6AAEE8);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(_colorHex);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text('Edit Category',
                    style: AghieriTextStyles.heading(size: 16)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.onDelete();
                    Navigator.pop(context);
                  },
                  child: Text('Delete',
                      style: AghieriTextStyles.caption(
                          color: const Color(0xFFE88A6A))),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Name
            TextField(
              controller: _nameCtrl,
              style: AghieriTextStyles.body(size: 16),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: AghieriTextStyles.caption(),
                filled: true,
                fillColor: AghieriColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Color picker
            Text('Color', style: AghieriTextStyles.caption()),
            const SizedBox(height: 8),
            Row(
              children: _colors.map((hex) {
                final c = _hexToColor(hex);
                final selected = _colorHex == hex;
                return GestureDetector(
                  onTap: () => setState(() => _colorHex = hex),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: selected ? 30 : 24,
                    height: selected ? 30 : 24,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: Colors.white.withOpacity(0.6), width: 2)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Icon picker
            Text('Icon', style: AghieriTextStyles.caption()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: availableIcons.map((key) {
                final selected = _icon == key;
                return GestureDetector(
                  onTap: () => setState(() => _icon = key),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withOpacity(0.2)
                          : AghieriColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            selected ? color : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      iconFromKey(key),
                      size: 16,
                      color: selected ? color : AghieriColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Subcategories
            Text('Subcategories', style: AghieriTextStyles.caption()),
            const SizedBox(height: 8),
            ..._subs.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.value.name,
                            style: AghieriTextStyles.body(size: 13)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _subs.removeAt(e.key)),
                        child: const Icon(Icons.close,
                            size: 14, color: AghieriColors.textSecondary),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subCtrl,
                    style: AghieriTextStyles.body(size: 13),
                    decoration: InputDecoration(
                      hintText: 'Add subcategory...',
                      hintStyle: AghieriTextStyles.caption(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: AghieriColors.surfaceHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _addSub(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addSub,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add, size: 16, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Map<String, dynamic> suggestion;
  final VoidCallback onDismiss;

  const _SuggestionCard({required this.suggestion, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final text = suggestion['text'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AghieriColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AghieriColors.accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_outlined,
              color: AghieriColors.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: AghieriTextStyles.body(size: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AghieriColors.textSecondary, size: 18),
            padding: EdgeInsets.zero,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
