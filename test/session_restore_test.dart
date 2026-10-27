import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/app.dart';
import 'package:im_app/core/api_client.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/models.dart';
import 'package:im_app/features/auth/login_page.dart';
import 'package:im_app/features/home/home_page.dart';

import 'support.dart';

class RestoreSocket extends FakeSocket {
  int connections = 0;

  @override
  Future<void> connect(
    String address,
    Future<String> Function() readToken,
  ) async {
    connections++;
    await super.connect(address, readToken);
  }
}

class RestoreApi extends FixtureApi {
  bool offline = false;

  @override
  Future<dynamic> get(String path, {Json? query}) async {
    if (offline) throw ApiException('连接失败，请检查网络和服务器地址');
    return super.get(path, query: query);
  }
}

void main() {
  late AppState app;
  late RestoreApi api;
  late RestoreSocket socket;
  late MemoryStorage storage;
  late String cacheKey;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = RestoreApi();
    socket = RestoreSocket();
    storage = MemoryStorage(await SharedPreferences.getInstance())
      ..session = {
        'server': api.dio.options.baseUrl,
        'user': {'id': '100', 'username': '测试用户'},
        'accessToken': 'saved-access',
        'refreshToken': 'saved-refresh',
      };
    app = AppState(storage, client: api, connection: socket);
    cacheKey = '${Uri.encodeComponent(app.httpUrl)}.100';
    await storage.saveCache(cacheKey, {
      'conversations': [
        {'id': '200_100', 'name': '测试好友'},
      ],
      'messages': {
        '200_100': [
          {'id': '1001', 'conversationId': '200_100', 'content': '本地记录'},
        ],
      },
    });
  });
  tearDown(() => app.dispose());

  test(
    'cold start without network clears session but preserves chat cache',
    () async {
      api.dio.httpClientAdapter = FakeAdapter(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      await app.initialize();
      expect(app.initialized, isTrue);
      expect(app.user, isNull);
      expect(storage.session, isEmpty);
      expect(api.accessToken, isEmpty);
      expect(api.refreshToken, isEmpty);
      expect(socket.connections, 0);
      expect(
        asJson(storage.readCache(cacheKey)['messages']),
        contains('200_100'),
      );
    },
  );

  testWidgets(
    'stalled startup is cancelled within five seconds and shows login',
    (tester) async {
      final response = Completer<ResponseBody>();
      final adapter = FakeAdapter((options) => response.future);
      api.dio.httpClientAdapter = adapter;
      final startup = app.initialize();
      try {
        await tester.pumpWidget(ImApp(state: app));
        await tester.pump(Duration.zero);
        expect(adapter.requests.single.path, '/user/refreshToken/100');
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 400));
        expect(app.initialized, isTrue);
        await startup;
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(HomePage), findsNothing);
        expect(adapter.requests.single.cancelToken?.isCancelled, isTrue);
        expect(storage.session, isEmpty);
        // 即使旧请求后来返回 Token，也不能恢复已取消的登录状态。
        response.complete(
          jsonResponse(
            {'code': 1},
            headers: {
              'authorization': ['Bearer late-access'],
            },
          ),
        );
        await tester.pump();
        expect(app.user, isNull);
        expect(api.accessToken, isEmpty);
        expect(storage.session, isEmpty);
        expect(socket.connections, 0);
      } finally {
        if (!response.isCompleted) response.complete(success(null));
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  test(
    'online cold start restores cached account and persists refreshed tokens',
    () async {
      api.dio.httpClientAdapter = FakeAdapter(
        (options) => jsonResponse(
          {'code': 1},
          headers: {
            'authorization': ['Bearer renewed-access'],
            'refreshtoken': ['renewed-refresh'],
          },
        ),
      );
      await app.initialize();
      expect(app.initialized, isTrue);
      expect(app.user?.id, '100');
      expect(app.messages['200_100']!.single.content, '本地记录');
      expect(storage.session['accessToken'], 'renewed-access');
      expect(storage.session['refreshToken'], 'renewed-refresh');
      expect(socket.connections, 1);
    },
  );

  test(
    'no saved login opens login without any startup network request',
    () async {
      storage.session = {};
      final adapter = FakeAdapter((options) => success(null));
      api.dio.httpClientAdapter = adapter;
      await app.initialize();
      expect(app.initialized, isTrue);
      expect(app.user, isNull);
      expect(adapter.requests, isEmpty);
      expect(socket.connections, 0);
    },
  );

  test('expired saved login still returns to login', () async {
    api.dio.httpClientAdapter = FakeAdapter(
      (options) => jsonResponse({}, status: 401),
    );
    await app.initialize();
    expect(app.initialized, isTrue);
    expect(app.user, isNull);
    expect(storage.session, isEmpty);
    expect(app.notice, '登录已过期，请重新登录');
    expect(socket.connections, 0);
  });

  test(
    'network loss after login keeps session during requests and reconnects',
    () async {
      await app.acceptUser({'id': '100', 'username': '测试用户'});
      final savedSession = Map.of(storage.session);
      api.dio.httpClientAdapter = FakeAdapter(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      socket.disconnect();
      await expectLater(api.post('/wallet/info'), throwsA(isA<ApiException>()));
      await expectLater(
        socket.beforeReconnect!(),
        throwsA(isA<DioException>()),
      );
      expect(app.user?.id, '100');
      expect(api.accessToken, isNotEmpty);
      expect(storage.session, savedSession);
    },
  );

  testWidgets('resuming the running app offline keeps the home screen', (
    tester,
  ) async {
    await app.acceptUser({'id': '100', 'username': '测试用户'});
    app.initialized = true;
    await tester.pumpWidget(ImApp(state: app));
    await tester.pumpAndSettle();
    final savedSession = Map.of(storage.session);
    api.offline = true;
    socket.disconnect();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(app.user?.id, '100');
    expect(storage.session, savedSession);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.logout();
    await tester.pump();
  });
}
