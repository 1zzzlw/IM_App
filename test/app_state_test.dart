import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/im_protocol.dart';
import 'package:im_app/core/models.dart';

import 'support.dart';

void main() {
  test('desktop defaults use loopback while Android uses emulator host', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(AppState.defaultHttp, 'http://127.0.0.1:81');
    expect(AppState.defaultWs, 'ws://127.0.0.1/ws');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AppState.defaultHttp, 'http://10.0.2.2:81');
    expect(AppState.defaultWs, 'ws://10.0.2.2/ws');
  });
  test('explicitly saved connection address is retained', () async {
    SharedPreferences.setMockInitialValues({
      'im.http': 'http://192.168.1.50:81',
      'im.ws': 'ws://192.168.1.50/ws',
    });
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      connection: FakeSocket(),
    );
    expect(app.httpUrl, 'http://192.168.1.50:81');
    expect(app.wsUrl, 'ws://192.168.1.50/ws');
    app.dispose();
  });
  test('received duplicate frame increments unread only once and ACK completes pending send', () async {
    SharedPreferences.setMockInitialValues({});
    final socket = FakeSocket();
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: FixtureApi(),
      connection: socket,
    );
    await app.acceptUser({'id': '100', 'username': '测试用户'});
    expect(app.conversations.single.id, '200_100');
    final message = await app.send(app.conversations.single, '测试消息');
    expect(message.status, 0);
    expect(socket.sent.single.$1, 1);
    socket.frames.add(
      ImFrame(16, 0, {
        'tempId': message.id,
        'messageId': message.id,
        'status': 0,
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(message.status, 1);
    final incoming = {
      'id': '999',
      'conversationId': '200_100',
      'senderId': '200',
      'msgType': 1,
      'content': '收到',
      'sendTime': '2026-10-26 11:00:00',
    };
    socket.frames.add(ImFrame(2, 0, Map.of(incoming)));
    socket.frames.add(ImFrame(2, 0, Map.of(incoming)));
    await Future<void>.delayed(Duration.zero);
    expect(app.messages['200_100']!.where((m) => m.id == '999').length, 1);
    expect(app.conversations.single.unread, 3);
    await app.logout();
    app.dispose();
  });
  test('opening hidden friend conversation reuses backend ID without duplicate INSERT', () async {
    SharedPreferences.setMockInitialValues({});
    final api = FixtureApi();
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: api,
      connection: FakeSocket(),
    );
    app.user = ImUser({'id': '100'});
    final conversation = await app.conversationFor(
      Contact({'friendId': '200', 'username': '好友'}),
    );
    expect(conversation.id, '200_100');
    expect((api.dio.httpClientAdapter as FakeAdapter).requests, isEmpty);
    await app.logout();
    app.dispose();
  });
  test(
    'logout saves cache under server and account and clears credentials',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = MemoryStorage(await SharedPreferences.getInstance());
      final app = AppState(
        storage,
        client: FixtureApi(),
        connection: FakeSocket(),
      );
      await app.acceptUser({'id': '100', 'username': '测试用户'});
      final key = app.cacheKey;
      await app.logout();
      expect(storage.readCache(key)['conversations'], isNotEmpty);
      expect(storage.session, isEmpty);
      expect(app.api.accessToken, isEmpty);
      expect(app.messages, isEmpty);
      app.user = ImUser({'id': '200'});
      expect(storage.readCache(app.cacheKey), isEmpty);
      app.dispose();
    },
  );
}
