import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import 'app_state.dart';
import 'models.dart';

/// 复用桌面端的 5 MiB 分片、MD5 校验、上传凭证与合并接口。
class FileService {
  FileService(this.app);
  final AppState app;
  static const chunkSize = 5 * 1024 * 1024;
  Future<void> send(
    Conversation conversation,
    PlatformFile file, {
    required void Function(double) onProgress,
    CancelToken? cancelToken,
    ChatMessage? quote,
  }) async {
    final generationUser = app.user?.id;
    if (generationUser == null) throw Exception('登录状态已失效');
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) throw Exception('文件为空或无法读取');
    if (bytes.length > 50 * 1024 * 1024) throw Exception('移动端暂支持 50 MB 以内的文件');
    final type = fileType(file.name);
    final fileId = md5.convert(bytes).toString();
    final ticket = asJson(
      await app.api.get('/message/verifyUploadToken/$fileId'),
    );
    final uploaded = await app.api.get(
      '/message/checkUploaded',
      query: {'verify': ticket['verify'], 'fileId': fileId},
    );
    final indices = uploaded is List ? uploaded.map(number).toSet() : <int>{};
    final count = (bytes.length / chunkSize).ceil();
    for (var i = 0; i < count; i++) {
      if (app.user?.id != generationUser) throw Exception('登录状态已变化，上传已停止');
      if (cancelToken?.isCancelled ?? false) throw Exception('上传已取消');
      if (!indices.contains(i)) {
        final chunk = Uint8List.sublistView(
          bytes,
          i * chunkSize,
          min((i + 1) * chunkSize, bytes.length),
        );
        app.api.unwrap(
          await app.api.response(
            'POST',
            '/message/uploadChunk',
            cancelToken: cancelToken,
            data: FormData.fromMap({
              'chunkBlob': MultipartFile.fromBytes(
                chunk,
                filename: '${file.name}.part$i',
              ),
              'chunkIndex': i,
              'chunkHash': md5.convert(chunk).toString(),
              'fileId': fileId,
              'fileType': type,
              'verify': ticket['verify'],
            }),
          ),
        );
      }
      onProgress((i + 1) / (count + 1));
    }
    await app.api.post(
      '/message/merge',
      data: {
        'fileHash': fileId,
        'fileName': file.name,
        'fileType': type,
        'minioFilePath': ticket['minioFilePath'],
        'chunkCount': count,
      },
    );
    if (app.user?.id != generationUser) throw Exception('登录状态已变化，上传已停止');
    final body =
        app.messageBody(
          conversation,
          switch (type) {
            2 => '[图片]',
            3 => '[视频]',
            4 => '[语音]',
            _ => '[文件] ${file.name}',
          },
          type,
          quote: quote,
        )..addAll({
          'fileId': fileId,
          'fileName': file.name,
          'fileSize': bytes.length,
          'remotePath': ticket['minioFilePath'],
        });
    final saved = asJson(await app.api.post('/message/send', data: body));
    await app.api.put(
      '/message/updateFileSendStatus',
      query: {'fileId': fileId, 'sendStatus': 1},
    );
    if (app.user?.id != generationUser) return;
    await app.send(
      conversation,
      str(body['content']),
      type: type,
      quote: quote,
      extra: {...body, ...saved, 'sendStatus': 0},
    );
    onProgress(1);
  }

  static int fileType(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp'].contains(ext)) {
      return 2;
    }
    if (['mp4', 'mov', 'm4v', 'webm', 'mkv'].contains(ext)) return 3;
    if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus'].contains(ext)) return 4;
    return 5;
  }
}
