import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/im_protocol.dart';
import 'package:im_app/core/models.dart';
import 'package:im_app/features/chat/chat_page.dart';
import 'package:im_app/ui/components.dart';
import 'package:im_app/ui/theme.dart';

import 'support.dart';

Json message(String id, String content, String time) => {
  'id': id,
  'conversationId': '200_100',
  'senderId': '200',
  'msgType': 1,
  'content': content,
  'sendTime': time,
  'sendStatus': 1,
};

class HistoryApi extends FixtureApi {
  List<Json> history = [];
  List<Json> older = [];

  @override
  Future<dynamic> get(String path, {Json? query}) async {
    if (path.startsWith('/message/init/list/')) return history;
    if (path == '/message/pull/list') return older;
    return super.get(path, query: query);
  }
}

void main() {
  late AppState app;
  late MemoryStorage storage;
  late HistoryApi api;
  late FakeSocket socket;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = MemoryStorage(await SharedPreferences.getInstance());
    api = HistoryApi();
    socket = FakeSocket();
    app = AppState(storage, client: api, connection: socket);
    await app.acceptUser({'id': '100', 'username': '测试用户'});
  });
  tearDown(() => app.dispose());

  testWidgets('REST, realtime and outgoing messages render chronologically', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    api.history = [message('1001', '123', '2026-10-26 17:30:01')];
    await app.loadLatest('200_100');
    // Fastjson 的 WS 时间带 T；本地发送和 Jackson 历史接口的时间带空格。
    socket.frames.add(
      ImFrame(2, 0, message('1002', '你好', '2026-10-26T17:30:02')),
    );
    await tester.pump();
    for (final (id, text, time) in [
      ('1003', '😀', '2026-10-26 17:31:00'),
      ('1004', '😊😊', '2026-10-26 17:31:01'),
    ]) {
      await app.send(
        app.conversations.single,
        text,
        extra: {'id': id, 'sendTime': time},
      );
    }
    expect(app.messages['200_100']!.map((m) => m.content), [
      '123',
      '你好',
      '😀',
      '😊😊',
    ]);
    await tester.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          theme: appTheme(),
          home: ChatPage(conversation: app.conversations.single),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tops = [
      for (final text in ['123', '你好', '😀', '😊😊'])
        tester.getTopLeft(find.text(text)).dy,
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.logout();
    await tester.pump();
  });

  test(
    'history merges retain same-second ID order without duplicates',
    () async {
      api.history = [
        message('9007199254740993', '后发', '2026-10-26 17:30:02'),
        message('9007199254740992', '先发', '2026-10-26T17:30:02'),
      ];
      await app.loadLatest('200_100');
      expect(app.messages['200_100']!.map((m) => m.content), ['先发', '后发']);
      api.older = [message('9007199254740991', '更早', '2026-10-26T17:29:00')];
      await app.loadOlder('200_100');
      // 重复拉取将同一条消息由 ISO 格式换为历史格式，不能改变逻辑顺序。
      api.history = [
        message('9007199254740992', '先发', '2026-10-26 17:30:02'),
        message('9007199254740993', '后发', '2026-10-26 17:30:02'),
      ];
      await app.loadLatest('200_100');
      expect(app.messages['200_100']!.map((m) => m.content), [
        '更早',
        '先发',
        '后发',
      ]);
    },
  );

  test('restoring old cache repairs mixed-format message order', () async {
    await storage.saveCache(app.cacheKey, {
      'messages': {
        '200_100': [
          message('1001', '123', '2026-10-26 17:30:01'),
          message('1003', '😀', '2026-10-26 17:31:00'),
          message('1002', '你好', '2026-10-26T17:30:02'),
        ],
      },
    });
    await app.acceptUser({'id': '100', 'username': '测试用户'});
    expect(app.messages['200_100']!.map((m) => m.content), ['123', '你好', '😀']);
  });

  test(
    'conversation ordering compares actual time and preserves pinning',
    () async {
      app.conversations.addAll([
        Conversation({'id': '300_100', 'latestMsgTime': '2026-10-26 17:31:00'}),
        Conversation({
          'id': '400_100',
          'latestMsgTime': '2026-10-25 10:00:00',
          'isTop': 1,
        }),
      ]);
      socket.frames.add(
        ImFrame(2, 0, message('1002', '你好', '2026-10-26T17:30:02')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(app.conversations.map((c) => c.id), [
        '400_100',
        '300_100',
        '200_100',
      ]);
    },
  );

  test('message ID determines order even when sendTime disagrees', () async {
    api.history = [
      message('7520640156306571265', '新 ID，旧时间', '2026-10-26 10:00:00'),
      message('7520640156306571264', '旧 ID，新时间', '2026-10-27T10:00:00'),
    ];
    await app.loadLatest('200_100');
    expect(app.messages['200_100']!.map((m) => m.content), [
      '旧 ID，新时间',
      '新 ID，旧时间',
    ]);
  });

  test(
    'ACK replaces temporary ID, reorders and merges a history duplicate',
    () async {
      api.history = [
        message('7520640156306571264', '已有消息', '2026-10-27 10:00:00'),
      ];
      await app.loadLatest('200_100');
      final outgoing = await app.send(
        app.conversations.single,
        '待确认消息',
        extra: {'id': '1001', 'sendTime': '2026-10-27 09:00:00'},
      );
      // REST 已返回正式 ID，但发送方的 ACK 尚未处理。
      api.history = [
        message('7520640156306571265', '待确认消息', '2026-10-27 09:00:00'),
      ];
      await app.loadLatest('200_100');
      socket.frames.add(
        ImFrame(16, 0, {
          'tempId': outgoing.id,
          'messageId': '7520640156306571265',
          'status': 0,
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(app.messages['200_100']!.map((m) => m.id), [
        '7520640156306571264',
        '7520640156306571265',
      ]);
      expect(app.messages['200_100']!.last.status, 1);
    },
  );
}
