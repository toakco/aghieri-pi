import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme/app_theme.dart';
import '../services/music_service.dart';

/// NowPlayingCard — compact music controls shown below the moon clock.
/// Auto-hides 30s after music stops.
class NowPlayingCard extends StatefulWidget {
  const NowPlayingCard({super.key});

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> {
  StreamSubscription<MusicState>? _sub;
  MusicState _state = const MusicState();
  bool _visible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _state = MusicService.instance.currentState;
    _visible = _state.isPlaying || _state.track.isNotEmpty;

    _sub = MusicService.instance.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);

      if (state.isPlaying || state.track.isNotEmpty) {
        _visible = true;
        _hideTimer?.cancel();
      } else {
        // Auto-hide after 30s of no playback
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) setState(() => _visible = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AghieriColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AghieriColors.surfaceHigh),
      ),
      child: Row(
        children: [
          // Music icon
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AghieriColors.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _state.isPlaying ? Icons.music_note : Icons.music_off,
              color: AghieriColors.accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),

          // Track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _state.track.isNotEmpty ? _state.track : 'No track',
                  style: AghieriTextStyles.body(size: 13, weight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_state.artist.isNotEmpty)
                  Text(
                    _state.artist,
                    style: AghieriTextStyles.caption(size: 11),
                    maxLines: 1,
                  ),
              ],
            ),
          ),

          // Controls
          GestureDetector(
            onTap: () {
              if (_state.isPlaying) {
                MusicService.instance.pause();
              } else {
                MusicService.instance.play();
              }
            },
            child: Icon(
              _state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AghieriColors.textPrimary,
              size: 24,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0, duration: 300.ms);
  }
}
