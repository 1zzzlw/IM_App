import 'package:flutter_test/flutter_test.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/im_protocol.dart';
import 'package:im_app/core/message_alert.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  Future<(AppState, FakeSocket, List<MessageAlert>)> fixture() async {
    SharedPreferences.setMockInitialValues({});
    final socket = FakeSocket();
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: FixtureApi(),
      connection: socket,
    );
    await app.acceptUser({'id': '100', 'username': '测试用户'});
    final alerts = <MessageAlert>[];
    final listener = app.messageAlerts.stream.listen(alerts.add);
    addTearDown(() async {
      await listener.cancel();
      await app.logout();
      app.dispose();
    });
    return (app, socket, alerts);
  }

  Future<void> receive(FakeSocket socket, {String sender = '200'}) async {
    socket.frames.add(
      ImFrame(2, 0, {
        'id': '999',
        'conversationId': '200_100',
        'senderId': sender,
        'msgType': 1,
        'content': '新消息',
        'sendTime': '2026-10-28 12:00:00',
      }),
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('普通新消息只提醒一次，重复帧不增加提醒和未读', () async {
    final (app, socket, alerts) = await fixture();
    await receive(socket);
    await receive(socket);
    expect(alerts, hasLength(1));
    expect(alerts.single.title, '测试好友');
    expect(alerts.single.accountId, '100');
    expect(app.conversations.single.unread, 3);
  });

  test('正在查看的会话不弹出提醒', () async {
    final (app, socket, alerts) = await fixture();
    app.activeConversation = '200_100';
    await receive(socket);
    expect(alerts, isEmpty);
    expect(app.conversations.single.unread, 2);
  });

  test('退到后台后即使停留在聊天页，也提醒并累计未读', () async {
    final (app, socket, alerts) = await fixture();
    app.activeConversation = '200_100';
    app.inForeground = false;
    await receive(socket);
    expect(alerts, hasLength(1));
    expect(app.conversations.single.unread, 3);
  });

  test('免打扰会话不发出消息提醒', () async {
    final (app, socket, alerts) = await fixture();
    app.conversations.single.data['isMute'] = 1;
    await receive(socket);
    expect(alerts, isEmpty);
  });

  test('自己的消息回显不发出消息提醒', () async {
    final (_, socket, alerts) = await fixture();
    await receive(socket, sender: '100');
    expect(alerts, isEmpty);
  });
}
