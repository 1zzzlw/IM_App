import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/app.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/models.dart';
import 'package:im_app/features/chat/chat_page.dart';
import 'package:im_app/ui/components.dart';
import 'package:im_app/ui/theme.dart';

import 'support.dart';

void main() {
  Future<AppState> state({bool loggedIn = false}) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: FixtureApi(),
      connection: FakeSocket(),
    );
    app.initialized = true;
    if (loggedIn) {
      app.user = ImUser({'id': '100', 'username': '小澈', 'account': 'test'});
      await app.sync();
    }
    return app;
  }

  testWidgets('login validates empty input and opens connection settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await state();
    await tester.pumpWidget(ImApp(state: app));
    await tester.pumpAndSettle();
    expect(find.text('很高兴，\n又见到你。'), findsOneWidget);
    await tester.ensureVisible(find.text('登 录'));
    await tester.tap(find.text('登 录'));
    await tester.pumpAndSettle();
    expect(find.text('请输入账号'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    await tester.tap(find.byTooltip('服务器设置'));
    await tester.pumpAndSettle();
    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('HTTP 接口'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await tester.pump();
  });

  testWidgets('home navigation and narrow screen layout show no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await state(loggedIn: true);
    await tester.pumpWidget(ImApp(state: app));
    await tester.pumpAndSettle();
    expect(find.text('测试好友'), findsOneWidget);
    await tester.tap(find.text('联系人').last);
    await tester.pumpAndSettle();
    expect(find.text('新的朋友'), findsOneWidget);
    await tester.tap(find.text('动态').last);
    await tester.pumpAndSettle();
    expect(find.text('生活，值得分享。'), findsOneWidget);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('我的钱包'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await tester.pump();
  });

  testWidgets('chat composer and emoji panel support small phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await state(loggedIn: true);
    await tester.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          theme: appTheme(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          locale: const Locale('zh', 'CN'),
          home: ChatPage(conversation: app.conversations.first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('说点什么…'), findsOneWidget);
    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😊'));
    await tester.pump();
    expect(find.text('😊'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await tester.pump();
  });
}
