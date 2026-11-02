import 'dart:typed_data';

Future<Uint8List> createDesktopVideoPreview(String path) =>
    Future.error(UnsupportedError('当前平台不支持本地 FFmpeg 视频封面提取'));
