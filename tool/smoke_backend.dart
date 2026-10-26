import 'dart:async';
import 'dart:io';

import 'package:im_app/core/api_client.dart';
import 'package:im_app/core/im_socket.dart';
import 'package:im_app/core/models.dart';

/// 使用临时环境变量传入凭据，仅验证真实读接口和握手，不打印响应、Token 或个人信息。
Future<void> main() async {
  final account = Platform.environment['IM_TEST_ACCOUNT'];
  final password = Platform.environment['IM_TEST_PASSWORD'];
  if (account == null || password == null) {
    throw StateError('请提供 IM_TEST_ACCOUNT 和 IM_TEST_PASSWORD 环境变量');
  }
  final api = ApiClient(
    Platform.environment['API_BASE_URL'] ?? 'http://127.0.0.1:81',
  );
  final socket = ImSocket();
  try {
    final captcha = await api.captcha();
    stdout.writeln('captcha: ${captcha.isNotEmpty ? 'PASS' : 'FAIL'}');
    final response = await api.response(
      'POST',
      '/user/login',
      authenticated: false,
      data: {
        'account': account,
        'password': password,
        'verifyCode': Platform.environment['IM_TEST_CODE'] ?? '0000',
      },
    );
    final user = asJson(api.unwrap(response));
    api.userId = str(user['id']);
    if (api.userId.isEmpty ||
        api.accessToken.isEmpty ||
        api.refreshToken.isEmpty) {
      throw StateError('登录响应不完整');
    }
    stdout.writeln('login + token headers: PASS');
    await api.refresh();
    stdout.writeln('refresh token: PASS');
    final result = await Future.wait([
      api.get('/conversation/init/list', query: {'isInit': true}),
      api.get('/friend/init/list', query: {'isInit': true}),
    ]);
    final conversations = asList(result[0]);
    stdout.writeln('conversations: PASS (${conversations.length})');
    stdout.writeln('contacts: PASS (${asList(result[1]).length})');
    if (conversations.isNotEmpty) {
      final messages = asList(
        await api.get(
          '/message/init/list/${conversations.first['id']}',
          query: {'isInit': true},
        ),
      );
      stdout.writeln('message history: PASS (${messages.length})');
    }
    final online = Completer<void>();
    final batch = Completer<void>();
    socket.states.stream.listen((state) {
      if (state == ConnectionState.online && !online.isCompleted) {
        online.complete();
      }
    });
    socket.frames.stream.listen((frame) {
      if (frame.type == 10 && !batch.isCompleted) batch.complete();
    }, onError: (Object _) {});
    await socket.connect(
      Platform.environment['WS_BASE_URL'] ?? 'ws://127.0.0.1/ws',
      () async => api.accessToken,
    );
    try {
      await online.future.timeout(const Duration(seconds: 12));
      socket.send(0, {'action': 'heartbeat'});
      stdout.writeln('websocket binary handshake + heartbeat: PASS');
      await batch.future.timeout(const Duration(seconds: 5));
      stdout.writeln('online list frame: PASS');
    } catch (_) {
      stdout.writeln('websocket: FAIL (handshake/online list unavailable)');
    }
    for (final endpoint in [
      '/moments/list/new',
      '/favorites/list',
      '/wallet/info',
      '/ai-message/conversation/list',
      '/ai-message/config/getConfig',
    ]) {
      try {
        await api.get(
          endpoint,
          query: endpoint.contains('/moments/')
              ? {'lastId': '9223372036854775807'}
              : endpoint.contains('/ai-message/')
              ? {'userId': api.userId}
              : null,
        );
        stdout.writeln('$endpoint: PASS');
      } catch (e) {
        stdout.writeln('$endpoint: FAIL (${e.runtimeType})');
      }
    }
  } finally {
    await socket.dispose();
    api.dio.close(force: true);
  }
}
