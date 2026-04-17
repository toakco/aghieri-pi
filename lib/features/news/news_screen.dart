import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../voice/voice_button.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  List<Map<String, dynamic>> _articles = [];
  bool _loading = true;
  String _activeFilter = 'All';

  static const _base = 'http://192.168.1.100:8000';
  static const _cacheKey = 'aghieri_news_cache';
  static const _cacheTimeKey = 'aghieri_news_cache_time';

  static const _filters = ['All', 'ADHD', 'Productivity', 'Wellness', 'Research'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Try cache first for instant display
    final cached = await _loadCache();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _articles = cached;
        _loading = false;
      });
    }

    // Try device API
    final deviceArticles = await _fetchFromDevice();
    if (deviceArticles.isNotEmpty) {
      await _saveCache(deviceArticles);
      if (mounted) setState(() { _articles = deviceArticles; _loading = false; });
      return;
    }

    // Try RSS feeds
    final rssArticles = await _fetchFromRSS();
    if (rssArticles.isNotEmpty) {
      final combined = [...rssArticles, ..._curatedArticles()];
      await _saveCache(combined);
      if (mounted) setState(() { _articles = combined; _loading = false; });
      return;
    }

    // Fallback to curated content
    final curated = _curatedArticles();
    if (mounted) setState(() { _articles = curated; _loading = false; });
  }

  Future<List<Map<String, dynamic>>> _fetchFromDevice() async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/integrations/news'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['articles'] as List? ?? [];
        return list.map((a) => Map<String, dynamic>.from(a as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchFromRSS() async {
    // Fetch from ADDitude Magazine RSS (public ADHD resource)
    try {
      final resp = await http
          .get(Uri.parse('https://api.rss2json.com/v1/api.json?rss_url=https://www.additudemag.com/feed/'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = data['items'] as List? ?? [];
        return items.take(10).map((item) {
          final m = item as Map<String, dynamic>;
          return {
            'title': m['title'] ?? '',
            'summary': _cleanHtml(m['description'] ?? ''),
            'source': 'ADDitude Magazine',
            'topic': 'ADHD',
            'url': m['link'] ?? '',
            'date': m['pubDate'] ?? '',
            'thumbnail': m['thumbnail'] ?? '',
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  String _cleanHtml(String html) {
    // Strip HTML tags and truncate
    final stripped = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return stripped.length > 200 ? '${stripped.substring(0, 200)}...' : stripped;
  }

  List<Map<String, dynamic>> _curatedArticles() {
    return [
      {
        'title': 'Understanding Executive Function and ADHD',
        'summary': 'Executive dysfunction is neurological, not motivational. Research shows ADHD brains process task initiation differently — understanding this changes how we design productivity tools.',
        'source': 'Curated by Aghieri',
        'topic': 'ADHD',
        'url': '',
      },
      {
        'title': 'Why Streaks and Gamification Backfire for ADHD',
        'summary': '43% of adults with ADHD report that productivity apps increase their anxiety. Streaks create shame spirals. Badges lose meaning. The most effective approach: remove the scoreboard entirely.',
        'source': 'Curated by Aghieri',
        'topic': 'Productivity',
      },
      {
        'title': 'Calm Technology: Designing for Peripheral Attention',
        'summary': 'Mark Weiser and John Seely Brown proposed that the best technology moves between the center and periphery of attention. Ambient light communicates without demanding focus.',
        'source': 'Weiser & Brown, 1996',
        'topic': 'Research',
      },
      {
        'title': 'The Science of Body Doubling',
        'summary': 'Working alongside another person — even silently — can dramatically improve task initiation for ADHD minds. The mechanism isn\'t accountability, it\'s co-regulation.',
        'source': 'Curated by Aghieri',
        'topic': 'ADHD',
      },
      {
        'title': 'Processing Fluency: Why Simpler Interfaces Work Better',
        'summary': 'Fewer visual elements mean lower cognitive load. For ADHD users, each additional button, badge, or notification competes for limited executive bandwidth.',
        'source': 'Curated by Aghieri',
        'topic': 'Research',
      },
      {
        'title': 'Voice-First Interfaces for Reduced Friction',
        'summary': 'Typing requires sustained attention and motor planning. Speaking a task aloud externalizes working memory instantly, reducing the executive load of getting started.',
        'source': 'Curated by Aghieri',
        'topic': 'Productivity',
      },
      {
        'title': 'ADHD and the Myth of Laziness',
        'summary': 'Campbell et al. (2024) found that ADHD-related task avoidance correlates with neurological dopamine regulation differences, not character flaws. Shame-free design respects this.',
        'source': 'Campbell et al., 2024',
        'topic': 'Research',
      },
      {
        'title': 'Ambient Light as a Cognitive Aid',
        'summary': 'Davis et al. (2017) showed that peripheral ambient lighting reduces cognitive load compared to screen-based notifications. Light registers in peripheral vision without demanding focal attention.',
        'source': 'Davis et al., 2017',
        'topic': 'Wellness',
      },
    ];
  }

  List<Map<String, dynamic>> get _filteredArticles {
    if (_activeFilter == 'All') return _articles;
    return _articles.where((a) {
      final topic = (a['topic'] as String? ?? '').toLowerCase();
      return topic == _activeFilter.toLowerCase();
    }).toList();
  }

  Future<void> _saveCache(List<Map<String, dynamic>> articles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(articles));
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final time = prefs.getInt(_cacheTimeKey) ?? 0;
      // Cache valid for 6 hours
      if (raw != null && DateTime.now().millisecondsSinceEpoch - time < 6 * 3600 * 1000) {
        final list = jsonDecode(raw) as List;
        return list.map((a) => Map<String, dynamic>.from(a as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _openArticle(Map<String, dynamic> article) async {
    final url = article['url'] as String? ?? '';
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredArticles;

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
        title: Text('Today', style: AghieriTextStyles.heading(size: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AghieriColors.textSecondary, size: 20),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: _loading && _articles.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AghieriColors.accent))
          : Column(
              children: [
                // Filter chips
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final filter = _filters[i];
                      final active = filter == _activeFilter;
                      return GestureDetector(
                        onTap: () => setState(() => _activeFilter = filter),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? AghieriColors.accent.withOpacity(0.15) : AghieriColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: active ? AghieriColors.accent.withOpacity(0.4) : AghieriColors.surfaceHigh,
                            ),
                          ),
                          child: Text(
                            filter,
                            style: AghieriTextStyles.label(
                              size: 12,
                              color: active ? AghieriColors.accent : AghieriColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 8),

                // Articles list
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text('Nothing in this category yet.',
                              style: AghieriTextStyles.body(color: AghieriColors.textSecondary)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: AghieriColors.surfaceHigh, height: 1),
                          itemBuilder: (_, i) => _ArticleCard(
                            article: filtered[i],
                            onTap: () => _openArticle(filtered[i]),
                          ).animate().fadeIn(delay: (i * 50).ms),
                        ),
                ),
              ],
            ),
      floatingActionButton: VoiceButton(onTranscript: (_) {}),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final Map<String, dynamic> article;
  final VoidCallback onTap;
  const _ArticleCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title     = article['title'] as String? ?? '';
    final summary   = article['summary'] as String? ?? '';
    final source    = article['source'] as String? ?? '';
    final topic     = article['topic'] as String? ?? '';
    final url       = article['url'] as String? ?? '';
    final thumbnail = article['thumbnail'] as String? ?? '';

    return GestureDetector(
      onTap: url.isNotEmpty ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (topic.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        topic.toUpperCase(),
                        style: AghieriTextStyles.label(size: 10, color: AghieriColors.accent),
                      ),
                    ),
                  Text(title,
                      style: AghieriTextStyles.body(size: 15, weight: FontWeight.w500)),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(summary,
                        style: AghieriTextStyles.body(
                            size: 13, color: AghieriColors.textSecondary),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (source.isNotEmpty)
                        Text(source, style: AghieriTextStyles.caption(size: 11)),
                      if (url.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.open_in_new_rounded,
                            size: 12, color: AghieriColors.accent.withOpacity(0.6)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (thumbnail.isNotEmpty) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  thumbnail,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
