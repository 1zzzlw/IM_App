import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_preview_desktop_stub.dart'
    if (dart.library.io) 'media_preview_desktop.dart';

/// 预览仅作为 HTTP 文件上传，不进入消息 JSON。图片使用 Flutter 解码，
/// 移动端视频首帧由平台媒体 API 提取，Windows 通过本机 FFmpeg 提取。
class MediaPreview {
  static const _channel = MethodChannel('im_app/media_preview');

  static Future<Uint8List> create(Uint8List bytes, int type, String? path) async {
    if (type == 3) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        if (path == null || path.isEmpty) throw StateError('无法读取视频文件路径');
        return createDesktopVideoPreview(path);
      }
      if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
        // 其他 Flutter 平台保留原有视频发送能力，使用轻量视频占位封面。
        return _videoPlaceholder();
      }
      if (path == null || path.isEmpty) throw StateError('无法读取视频文件路径');
      final cover = await _channel.invokeMethod<Uint8List>('videoThumbnail', {'path': path});
      if (cover == null || cover.isEmpty) throw StateError('视频封面生成失败');
      return cover;
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      final source = await ui.ImageDescriptor.encoded(buffer);
      descriptor = source;
      final scale = 320 / (source.width > source.height ? source.width : source.height);
      final decoder = await source.instantiateCodec(
        targetWidth: scale < 1 ? (source.width * scale).round().clamp(1, 320).toInt() : source.width,
        targetHeight: scale < 1 ? (source.height * scale).round().clamp(1, 320).toInt() : source.height,
      );
      codec = decoder;
      final frame = (await decoder.getNextFrame()).image;
      image = frame;
      final encoded = await frame.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) throw StateError('图片预览生成失败');
      return encoded.buffer.asUint8List(encoded.offsetInBytes, encoded.lengthInBytes);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static Future<Uint8List> _videoPlaceholder() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xff26364a), ui.BlendMode.src);
    final play = ui.Path()..moveTo(140, 62)..lineTo(140, 118)..lineTo(188, 90)..close();
    canvas.drawPath(play, ui.Paint()..color = const ui.Color(0xffd4e6fa));
    final picture = recorder.endRecording();
    final image = await picture.toImage(320, 180);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('视频占位封面生成失败');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}
