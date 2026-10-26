import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/models.dart';
import 'package:im_app/features/ai/ai_page.dart';
import 'package:im_app/features/moments/moments_page.dart';
import 'package:im_app/ui/components.dart';
import 'package:im_app/ui/theme.dart';

import 'support.dart';

class MomentsApi extends FixtureApi {
  final requests = <(String, Json)>[];
  @override
  Future<dynamic> get(String path, {Json? query}) async {
    requests.add((path, query ?? {}));
    Json moment(String id, String content) => {
      'id': id,
      'userId': '200',
      'username': '好友',
      'content': '<p>$content</p>',
    };
    if (path == '/moments/list/new') return [moment('1', '最新内容')];
    if (path == '/moments/list/hot') {
      return {
        'total': 21,
        'data': [
          moment(
            query?['page'] == 1 ? '2' : '3',
            query?['page'] == 1 ? '热门第一页' : '热门第二页',
          ),
        ],
      };
    }
    if (path == '/ai-message/config/getConfig') {
      return [
        {
          'id': '42',
          'configName': '我的模型',
          'providerName': 'test',
          'modelName': 'test',
        },
      ];
    }
    return super.get(path, query: query);
  }
}

void main() {
  Future<AppState> create(MomentsApi api) async {
    SharedPreferences.setMockInitialValues({});
    return AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: api,
      connection: FakeSocket(),
    )..user = ImUser({'id': '100', 'username': '我'});
  }

  Widget host(AppState app, Widget page) => AppScope(
    state: app,
    child: MaterialApp(
      theme: appTheme(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      locale: const Locale('zh', 'CN'),
      home: Scaffold(body: page),
    ),
  );

  testWidgets(
    'hot tab requests correct endpoint and renders PageResult.data through final page',
    (tester) async {
      final api = MomentsApi();
      final app = await create(api);
      await tester.pumpWidget(host(app, const MomentsPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('最新内容', findRichText: true), findsOneWidget);
      await tester.tap(find.text('热门'));
      await tester.pumpAndSettle();
      expect(api.requests.last.$1, '/moments/list/hot');
      expect(api.requests.last.$2, {'page': 1, 'pageSize': 20});
      expect(find.textContaining('热门第一页', findRichText: true), findsOneWidget);
      expect(find.textContaining('最新内容', findRichText: true), findsNothing);
      await tester.ensureVisible(find.text('看看更多'));
      await tester.tap(find.text('看看更多'));
      await tester.pumpAndSettle();
      expect(api.requests.last.$1, '/moments/list/hot');
      expect(api.requests.last.$2, {'page': 2, 'pageSize': 20});
      expect(find.textContaining('热门第一页', findRichText: true), findsOneWidget);
      expect(find.textContaining('热门第二页', findRichText: true), findsOneWidget);
      expect(find.text('看看更多'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      await tester.pump();
    },
  );

  testWidgets('AI model menu stays compact on desktop and supports selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await create(MomentsApi());
    await tester.pumpWidget(host(app, const AiPage()));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('ai-model-selector'));
    expect(tester.getSize(selector).width, lessThanOrEqualTo(320));
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PopupMenuItem<String>).first).width,
      lessThanOrEqualTo(320),
    );
    await tester.tap(find.text('我的模型'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: selector, matching: find.text('我的模型')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await tester.pump();
  });
}
