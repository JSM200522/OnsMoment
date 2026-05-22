import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/kleuren.dart';

/// Herbruikbare videospeler voor de ontvanger-popup.
/// - Toont het eerste frame als thumbnail (geen autoplay — iOS Safari-regel).
/// - Grote ronde peach play-knop in het midden.
/// - Tik = play (geluid aan); tik tijdens afspelen = pause.
/// - Bij einde verschijnt de play-knop weer voor herhalen.
/// - Bij init-fout: film-icoon-placeholder, popup blijft sluitbaar.
class VideoSpeler extends StatefulWidget {
  final String url;
  const VideoSpeler({super.key, required this.url});

  @override
  State<VideoSpeler> createState() => _VideoSpelerState();
}

class _VideoSpelerState extends State<VideoSpeler> {
  VideoPlayerController? _ctrl;
  bool _klaar = false;
  bool _fout = false;
  bool _speelt = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _ctrl = c;
      await c.initialize();
      c.addListener(_luister);
      if (mounted) setState(() => _klaar = true);
    } catch (e) {
      debugPrint('video-decode faalde: $e');
      if (mounted) setState(() => _fout = true);
    }
  }

  void _luister() {
    final c = _ctrl;
    if (c == null || !mounted) return;
    // Einde bereikt → terug naar begin zodat de play-knop weer verschijnt.
    if (c.value.duration > Duration.zero
        && c.value.position >= c.value.duration
        && !c.value.isPlaying) {
      c.seekTo(Duration.zero);
      if (_speelt) setState(() => _speelt = false);
      return;
    }
    if (c.value.isPlaying != _speelt) {
      setState(() => _speelt = c.value.isPlaying);
    }
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.setVolume(1.0);
      c.play();
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_luister);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fout) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(16)),
        child: const Center(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_rounded, size: 64, color: kPeach),
            SizedBox(height: 8),
            Text('Video kon niet geladen worden',
                style: TextStyle(fontSize: 14, color: kBrown)),
          ])),
      );
    }
    final c = _ctrl;
    if (!_klaar || c == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: kPeachPale,
            borderRadius: BorderRadius.circular(16)),
        child: const Center(child: CircularProgressIndicator(color: kPeach)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio,
        child: Stack(children: [
          Positioned.fill(child: VideoPlayer(c)),
          Positioned.fill(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: _speelt
                ? const SizedBox()
                : Center(child: Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(
                        color: kPeach.withOpacity(0.92),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 16)]),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: kWhite, size: 48))),
          )),
        ]),
      ),
    );
  }
}
