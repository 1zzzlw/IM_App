import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/app.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/models.dart';
import 'package:im_app/features/chat/chat_page.dart';
import 'package:im_app/features/ai/ai_page.dart';
import 'package:im_app/ui/components.dart';
import 'package:im_app/ui/theme.dart';

import 'support.dart';

/// 可选的本机视觉验收：只使用合成数据，截图写入 build/visual，不连接真实账号。
void main() {
  testWidgets('export mobile UI for visual review', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final shadowsDisabled = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = shadowsDisabled);
    final fontFile = File('C:/Windows/Fonts/msyh.ttc');
    if (fontFile.existsSync()) {
      final loader = FontLoader('sans-serif')
        ..addFont(
          Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
        );
      await tester.runAsync(loader.load);
      final roboto = FontLoader('Roboto')
        ..addFont(
          Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
        );
      await tester.runAsync(roboto.load);
      final fallback = FontLoader('Ahem')
        ..addFont(
          Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
        );
      await tester.runAsync(fallback.load);
    }
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await tester.runAsync(loader.load);
    }
    SharedPreferences.setMockInitialValues({});
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: FixtureApi(),
      connection: FakeSocket(),
    )..initialized = true;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ImApp(state: app),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) => tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/visual').create(recursive: true);
      await File('build/visual/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await capture('login');
    app.user = ImUser({'id': '100', 'username': '小澈', 'account': 'test'});
    await app.sync();
    await app.socket.connect('', () async => '');
    app.conversations.addAll([
      Conversation({
        'id': 'g_test',
        'name': '周末出逃计划',
        'type': 1,
        'latestMsg': '一起收集生活里的小美好',
        'unreadCount': 5,
        'latestMsgTime': '2026-10-26 09:30:00',
      }),
      Conversation({
        'id': '300_100',
        'targetId': '300',
        'name': '林间',
        'latestMsg': '今天也要开心呀',
        'latestMsgTime': '2026-10-26 08:50:00',
      }),
    ]);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ImApp(state: app),
      ),
    );
    await tester.pumpAndSettle();
    await capture('messages');
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await capture('home-menu');
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await capture('profile');
    app.messages['200_100'] = [
      ChatMessage({
        'id': '1',
        'conversationId': '200_100',
        'senderId': '200',
        'msgType': 1,
        'content': '周末一起去看海吧',
        'sendStatus': 1,
      }),
      ChatMessage({
        'id': '2',
        'conversationId': '200_100',
        'senderId': '100',
        'msgType': 1,
        'content': '好呀！带上相机，记录每一个好天气。',
        'sendStatus': 1,
      }),
      ChatMessage({
        'id': '3',
        'conversationId': '200_100',
        'senderId': '200',
        'msgType': 1,
        'content': '那就这么说定了',
        'sendStatus': 1,
      }),
    ];
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AppScope(
          state: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            locale: const Locale('zh', 'CN'),
            home: ChatPage(conversation: app.conversations.first),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('chat');
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AppScope(
          state: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            locale: const Locale('zh', 'CN'),
            home: const AiPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
    await tester.pumpAndSettle();
    await capture('ai-model-menu-desktop');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    await tester.pump();
  }, skip: Platform.environment['CAPTURE_UI'] != '1');
}
