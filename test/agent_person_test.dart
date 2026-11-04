import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lumina_agent/core/app_state.dart';
import 'package:lumina_agent/core/models.dart';
import 'package:lumina_agent/core/api_client.dart';
import 'package:lumina_agent/features/ai/ai_page.dart';
import 'package:lumina_agent/features/ai/agent_person_page.dart';
import 'package:lumina_agent/ui/components.dart';
import 'package:lumina_agent/ui/theme.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

class PersonApi extends FixtureApi {
  final paths = <String>[];
  Json? sent;
  final history = <Json>[
    {'id': 'old', 'role': 'assistant', 'content': '今天想聊些什么？', 'seq': '1'},
  ];
  @override
  Future<dynamic> get(String path, {Json? query}) async {
    paths.add(path);
    return switch (path) {
      '/ai-message/person' => {'exists': true, 'name': '林夏'},
      '/ai-message/loadMessage' => history,
      '/ai-message/config/getConfig' => [],
      '/ai-message/person/moments' => [
        {
          'id': 'moment',
          'name': '林夏',
          'parts': {
            'parts': [
              {'type': 'text', 'text': '今天画了海边的云'},
            ],
          },
          'interactions': [],
        },
      ],
      _ => [],
    };
  }

  @override
  Future<dynamic> post(String path, {dynamic data, Json? query}) async {
    paths.add(path);
    return {'success': true};
  }

  @override
  Stream<SseEvent> stream(String path, Json body, CancelToken token) async* {
    sent = body;
    history.add({
      'id': body['id'],
      'role': 'user',
      'content': body['content'],
      'seq': '2',
    });
    for (final event in [
      ('run.started', {'conversationId': 'world'}),
      ('message.reasoning.delta', {'delta': 'INTERNAL_SECRET'}),
      ('message.completed', {'messageId': 'one', 'content': '我在呢。'}),
      ('message.completed', {'messageId': 'two', 'content': '慢慢说。'}),
      ('done', {'success': true}),
    ]) {
      if (event.$1 == 'message.completed') {
        history.add({
          'id': event.$2['messageId'],
          'role': 'assistant',
          'content': event.$2['content'],
          'seq': '${history.length + 1}',
        });
      }
      yield SseEvent(event.$1, jsonEncode(event.$2));
    }
  }
}

void main() {
  test('request IDs are UUID v4', () {
    final id = agentRequestId();
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(agentRequestId(), isNot(id));
  });
  testWidgets(
    'one shared person window excludes internal events and old workspace APIs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final api = PersonApi();
      final app =
          AppState(
              MemoryStorage(await SharedPreferences.getInstance()),
              client: api,
              connection: FakeSocket(),
            )
            ..initialized = true
            ..user = ImUser({'id': '100', 'username': '用户'});
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: appTheme(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            locale: const Locale('zh', 'CN'),
            home: const AiPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('林夏'), findsWidgets);
      expect(find.text('今天想聊些什么？'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '你好');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(api.sent?['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(find.textContaining('INTERNAL_SECRET'), findsNothing);
      expect(find.text('我在呢。'), findsOneWidget);
      expect(find.text('慢慢说。'), findsOneWidget);
      expect(
        api.paths.any(
          (p) => p.contains('conversation/') || p.contains('workspace'),
        ),
        isFalse,
      );
      await tester.tap(find.byTooltip('朋友圈'));
      await tester.pumpAndSettle();
      expect(find.text('今天画了海边的云'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      await tester.pump();
    },
  );
}
