import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/file_service.dart';
import 'package:im_app/core/models.dart';

import 'support.dart';

class UploadApi extends FixtureApi {
  final calls = <(String, dynamic)>[];
  @override
  Future<dynamic> get(String path, {Json? query}) async {
    if (path.startsWith('/message/verifyUploadToken/')) {
      return {'verify': 'ticket', 'minioFilePath': 'test/file'};
    }
    if (path == '/message/checkUploaded') return [0];
    return super.get(path, query: query);
  }

  @override
  Future<dynamic> post(String path, {dynamic data, Json? query}) async {
    calls.add((path, data));
    return path == '/message/send'
        ? {...asJson(data), 'remoteUrl': 'http://test.invalid/file'}
        : null;
  }

  @override
  Future<Response<dynamic>> response(
    String method,
    String path, {
    dynamic data,
    Json? query,
    ResponseType? type,
    CancelToken? cancelToken,
    bool authenticated = true,
  }) async {
    calls.add((path, data));
    return Response(
      requestOptions: RequestOptions(),
      statusCode: 200,
      data: {'code': 1},
    );
  }
}

void main() {
  test('file upload skips uploaded chunks, merges first and announces the same saved message ID', () async {
    SharedPreferences.setMockInitialValues({});
    final api = UploadApi();
    final socket = FakeSocket();
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: api,
      connection: socket,
    );
    await app.acceptUser({'id': '100', 'username': '测试用户'});
    final bytes = Uint8List(FileService.chunkSize + 3);
    var completed = 0.0;
    await FileService(app).send(
      app.conversations.single,
      PlatformFile(name: 'sample.bin', size: bytes.length, bytes: bytes),
      onProgress: (v) => completed = v,
    );
    expect(api.calls.map((c) => c.$1), [
      '/message/uploadChunk',
      '/message/merge',
      '/message/send',
    ]);
    final chunk = api.calls[0].$2 as FormData;
    expect(Map.fromEntries(chunk.fields)['chunkIndex'], '1');
    expect(chunk.files.single.value.length, 3);
    final saved = asJson(api.calls[2].$2);
    expect(socket.sent.single.$2['id'], saved['id']);
    expect(socket.sent.single.$2['remoteUrl'], 'http://test.invalid/file');
    expect(completed, 1);
    await app.logout();
    app.dispose();
  });
}
