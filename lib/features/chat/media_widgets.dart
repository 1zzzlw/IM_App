import 'package:material_ui/material_ui.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/components.dart';
import '../../ui/theme.dart';

Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return;
  await runAction(context, () async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('无法打开链接');
    }
  });
}

class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF151923),
    appBar: AppBar(
      iconTheme: const IconThemeData(color: Colors.white),
      backgroundColor: Colors.transparent,
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Image.network(
          url,
          errorBuilder: (_, error, stack) =>
              const Text('图片加载失败', style: TextStyle(color: Colors.white)),
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}

class AudioMessage extends StatefulWidget {
  const AudioMessage({super.key, required this.url});
  final String url;
  @override
  State<AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<AudioMessage> {
  final player = AudioPlayer();
  bool loaded = false;
  bool busy = false;
  Future<void> toggle() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (!loaded) {
        await player.setUrl(widget.url);
        loaded = true;
      }
      if (!mounted) return;
      if (player.playing) {
        await player.pause();
      } else {
        if (player.processingState == ProcessingState.completed) {
          await player.seek(Duration.zero);
        }
        player.play().catchError((Object e) {
          if (mounted) toast(context, '音频播放失败：$e');
        });
      }
    } catch (e) {
      if (mounted) toast(context, '音频播放失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
    stream: player.playerStateStream,
    builder: (context, snapshot) => InkWell(
      onTap: toggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                snapshot.data?.playing == true
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 25,
              ),
            const SizedBox(width: 8),
            const Icon(Icons.graphic_eq_rounded, size: 26),
            const SizedBox(width: 10),
            StreamBuilder<Duration?>(
              stream: player.durationStream,
              builder: (_, s) =>
                  Text(s.data == null ? '语音消息' : '${s.data!.inSeconds}″'),
            ),
          ],
        ),
      ),
    ),
  );
}

class VideoPreviewPage extends StatefulWidget {
  const VideoPreviewPage({super.key, required this.url});
  final String url;
  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  late final VideoPlayerController player;
  String? error;
  @override
  void initState() {
    super.initState();
    player = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    player
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = e.toString());
        });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: '视频',
    child: error != null
        ? EmptyState(
            title: '无法播放此视频',
            description: error!,
            action: TextButton(
              onPressed: () => openLink(context, widget.url),
              child: const Text('使用其他应用打开'),
            ),
          )
        : !player.value.isInitialized
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : Center(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: player,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: value.aspectRatio,
                    child: VideoPlayer(player),
                  ),
                  const SizedBox(height: 18),
                  VideoProgressIndicator(
                    player,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                  ),
                  IconButton.filled(
                    onPressed: () =>
                        value.isPlaying ? player.pause() : player.play(),
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  Text(
                    '${value.position.inSeconds} / ${value.duration.inSeconds} 秒',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
  );
}
