import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

/// VideoWidget
///
/// A reusable video player widget that:
/// - Loads a network video using `video_player`.
/// - Wraps it with Chewie for Material controls.
/// - Shows a 16:9 loading placeholder while initializing.
/// - Displays a friendly error message if initialization fails.
class VideoWidget extends StatefulWidget {
  final String videoUrl;

  const VideoWidget({super.key, required this.videoUrl});

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  late final VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _init();
  }

  Future<void> _init() async {
    try {
      await _videoPlayerController.initialize();
      if (!mounted) return;

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControlsOnInitialize: false,
        // Provide a user-friendly error message if playback fails.
        errorBuilder: (context, message) => Container(
          color: Colors.black,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(
            message.isNotEmpty ? message : 'Failed to load video.',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Error state
    if (_initError != null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'Unable to play this video.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    // Loading state
    if (!_videoPlayerController.value.isInitialized || _chewieController == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Use the actual video aspect ratio when available.
    final aspectRatio = _videoPlayerController.value.aspectRatio == 0
        ? (16 / 9)
        : _videoPlayerController.value.aspectRatio;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }
}
