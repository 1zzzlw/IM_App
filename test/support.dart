import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:im_app/core/api_client.dart';
import 'package:im_app/core/im_socket.dart';
import 'package:im_app/core/models.dart';
import 'package:im_app/core/session_storage.dart';

class MemoryStorage extends SessionStorage {
  MemoryStorage(super.preferences);
  Json session = {};
  @override
  Future<Json> readSession() async => session;
  @override
  Future<void> saveSession(Json value) async {
    session = value;
  }

  @override
  Future<void> clearSession() async {
    session = {};
  }
}

class FakeSocket extends ImSocket {
  final sent = <(int, Json)>[];
  @override
  Future<void> connect(
    String address,
    Future<String> Function() readToken,
  ) async {
    state = ConnectionState.online;
  }

  @override
  void send(int type, Json body) {
    sent.add((type, Map.of(body)));
  }
}

typedef Handler = FutureOr<ResponseBody> Function(RequestOptions options);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Handler handler;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(
  dynamic data, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    'content-type': ['application/json'],
    ...headers,
  },
);
ResponseBody success(dynamic data) => jsonResponse({'code': 1, 'data': data});

class FixtureApi extends ApiClient {
  FixtureApi() : super('http://test.invalid') {
    accessToken = 'access';
    refreshToken = 'refresh';
    userId = '100';
    dio.httpClientAdapter = FakeAdapter((options) => success([]));
  }
  @override
  Future<dynamic> get(String path, {Json? query}) async {
    return switch (path) {
      '/conversation/init/list' => [
        {
          'id': '200_100',
          'targetId': '200',
          'name': '测试好友',
          'type': 0,
          'status': 1,
          'unreadCount': 2,
          'latestMsg': '周末一起去看海吧',
          'latestMsgTime': '2026-10-26 10:00:00',
        },
      ],
      '/friend/init/list' => [
        {'friendId': '200', 'username': '测试好友', 'relationStatus': 1},
      ],
      '/wallet/info' => {'balance': '28.50', 'freezeBalance': '0'},
      _ => [],
    };
  }

  @override
  Future<dynamic> put(String path, {dynamic data, Json? query}) async => null;
  @override
  Future<Uint8List> captcha() async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNIqfjwHwAF3ALMblD4QwAAAABJRU5ErkJggg==',
  );
}
