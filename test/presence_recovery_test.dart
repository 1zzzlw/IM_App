import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_agent/core/app_state.dart';
import 'package:lumina_agent/core/im_protocol.dart';
import 'package:lumina_agent/core/im_socket.dart' as im;
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  test('登录主动获取在线列表，延迟回包及断线重连后更新好友状态', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final connections = <WebSocket>[];
    final closing = <WebSocket>{};
    var requests = 0;
    var heartbeats = 0;
    server.listen((request) async {
      final channel = await WebSocketTransformer.upgrade(request);
      connections.add(channel);
      final number = connections.length;
      channel.listen((raw) async {
        final frame = ImProtocol.decode(raw as List<int>);
        if (frame.type == 0) {
          heartbeats++;
          channel.add(ImProtocol.encode(0, 0, {}));
          return;
        }
        if (frame.type != 19) return;
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!closing.contains(channel) &&
            channel.readyState == WebSocket.open) {
          channel.add(
            ImProtocol.encode(10, 0, {
              'friendIdList': number == 1 ? ['200'] : <String>[],
            }),
          );
        }
      });
    });
    SharedPreferences.setMockInitialValues({
      'im.ws': 'ws://127.0.0.1:${server.port}/ws',
    });
    final socket = im.ImSocket();
    final forwardedTypes = <int>[];
    final forwarded = socket.frames.stream.listen(
      (frame) => forwardedTypes.add(frame.type),
    );
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: FixtureApi(),
      connection: socket,
    );
    Future<ImFrame> nextFrame(int type) => socket.frames.stream
        .firstWhere((frame) => frame.type == type)
        .timeout(const Duration(seconds: 8));
    try {
      final initial = nextFrame(10);
      await app.acceptUser({'id': '100', 'username': '测试用户'});
      await initial;
      expect(requests, 1);
      expect(heartbeats, 1);
      expect(forwardedTypes, isNot(contains(0)));
      expect(app.onlineUsers, {'200'});

      final offline = nextFrame(11);
      connections.first.add(ImProtocol.encode(11, 0, {'userId': '200'}));
      await offline;
      expect(app.onlineUsers, isEmpty);
      final online = nextFrame(9);
      connections.first.add(ImProtocol.encode(9, 0, {'userId': '200'}));
      await online;
      expect(app.onlineUsers, {'200'});

      final lost = socket.states.stream.firstWhere(
        (state) => state == im.ConnectionState.reconnecting,
      );
      final recovered = nextFrame(10);
      closing.add(connections.first);
      await connections.first.close(WebSocketStatus.goingAway);
      await lost;
      expect(app.onlineUsers, isEmpty);
      await recovered;
      expect(connections.length, 2);
      expect(app.onlineUsers, isEmpty);
      expect(socket.state, im.ConnectionState.online);
    } finally {
      await forwarded.cancel();
      closing.addAll(connections);
      await app.logout();
      app.dispose();
      for (final connection in connections) {
        await connection.close();
      }
      await server.close(force: true);
    }
  });
}
