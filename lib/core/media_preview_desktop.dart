import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Windows runner 不提供移动端的媒体通道，使用 FFmpeg 输出单张 JPEG。
/// 优先使用应用目录中的 ffmpeg.exe，开发环境可使用 PATH 中的 FFmpeg。
Future<Uint8List> createDesktopVideoPreview(String path) async {
  if (!await File(path).exists()) throw StateError('视频文件不存在，无法生成封面');
  final bundled = File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}ffmpeg.exe');
  final executable = await bundled.exists() ? bundled.path : 'ffmpeg.exe';
  late final Process process;
  try {
    process = await Process.start(executable, [
      '-hide_banner', '-loglevel', 'error', '-nostdin',
      '-i', path, '-map', '0:v:0', '-frames:v', '1', '-an',
      '-vf', 'scale=320:320:force_original_aspect_ratio=decrease',
      '-q:v', '6', '-c:v', 'mjpeg', '-f', 'image2pipe', 'pipe:1',
    ]);
  } on ProcessException {
    throw StateError('无法生成视频封面：请将 FFmpeg 加入 PATH，或把 ffmpeg.exe 放在应用程序目录');
  }
  var completed = false;
  try {
    // 同时读取两个管道，避免 FFmpeg 因输出缓冲区已满而卡住。
    final output = process.stdout.fold<BytesBuilder>(BytesBuilder(copy: false), (builder, chunk) {
      if (builder.length + chunk.length > 1024 * 1024) throw StateError('视频封面超过1MB');
      return builder..add(chunk);
    });
    final results = await Future.wait<Object>([
      process.exitCode,
      output,
      process.stderr.transform(utf8.decoder).join(),
    ]).timeout(const Duration(seconds: 20));
    completed = true;
    if (results[0] != 0) {
      final detail = (results[2] as String).trim();
      throw StateError('视频封面提取失败${detail.isEmpty ? '' : '：$detail'}');
    }
    final cover = (results[1] as BytesBuilder).takeBytes();
    if (cover.isEmpty) throw StateError('视频中没有可用画面，无法生成封面');
    return cover;
  } on TimeoutException {
    throw StateError('视频封面生成超时，请重试');
  } finally {
    // 超时或读取异常时停止子进程，不能在后台继续占用视频文件。
    if (!completed) process.kill();
  }
}
