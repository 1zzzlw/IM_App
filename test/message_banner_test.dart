import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_agent/app.dart';
import 'package:lumina_agent/core/app_state.dart';
import 'package:lumina_agent/core/message_alert.dart';
import 'package:lumina_agent/core/mobile_services.dart';
import 'package:lumina_agent/core/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  testWidgets('顶部消息卡片拥有 Overlay，关闭提示和点击跳转不会报错', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'im.messageSound': false});
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: FixtureApi(),
      connection: FakeSocket(),
    );
    app.user = ImUser({'id': '100', 'username': '测试用户'});
    app.initialized = true;
    await app.sync();
    final mobile = MobileServices(app);
    await tester.pumpWidget(ImApp(state: app, mobile: mobile));
    await tester.pumpAndSettle();
    const alert = MessageAlert(
      accountId: '100',
      conversationId: '200_100',
      messageId: '999',
      title: '测试好友',
      body: '新的消息卡片',
    );
    mobile.onBanner!(alert);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('新的消息卡片'), findsOneWidget);
    await tester.longPress(find.byTooltip('关闭提醒'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭提醒'));
    await tester.pumpAndSettle();
    expect(find.text('新的消息卡片'), findsNothing);
    mobile.onBanner!(alert);
    await tester.pump();
    await tester.tap(find.text('新的消息卡片'));
    await tester.pumpAndSettle();
    expect(find.text('说点什么…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await tester.pump();
  });
}
