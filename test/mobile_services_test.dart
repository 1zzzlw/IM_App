import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/im_protocol.dart';
import 'package:im_app/core/mobile_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android 登录启动后台接收、前后台提醒分流、退出停止服务', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({'im.messageSound': false});
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MobileServices.channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return {'granted': true};
          if (call.method == 'requestPermission') return true;
          return null;
        });
    final socket = FakeSocket();
    final app = AppState(
      MemoryStorage(await SharedPreferences.getInstance()),
      client: FixtureApi(),
      connection: socket,
    );
    final mobile = MobileServices(app);
    var banners = 0;
    mobile.onBanner = (_) => banners++;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    try {
      await mobile.initialize();
      await app.acceptUser({'id': '100', 'username': '测试用户'});
      await settle();
      expect(calls.where((c) => c.method == 'background').last.arguments, {
        'enabled': true,
      });
      void receive(String id) => socket.frames.add(
        ImFrame(2, 0, {
          'id': id,
          'conversationId': '200_100',
          'senderId': '200',
          'msgType': 1,
          'content': '提醒',
        }),
      );
      receive('1001');
      await settle();
      expect(banners, 1);
      expect(calls.where((c) => c.method == 'notify'), isEmpty);
      app.inForeground = false;
      receive('1002');
      await settle();
      final notification = calls.singleWhere((c) => c.method == 'notify');
      expect(notification.arguments['accountId'], '100');
      expect(notification.arguments['conversationId'], '200_100');
      expect(notification.arguments['sound'], false);
      await app.logout();
      await settle();
      expect(calls.where((c) => c.method == 'background').last.arguments, {
        'enabled': false,
      });
      expect(
        calls.where((c) => c.method == 'cancelNotifications'),
        hasLength(1),
      );
    } finally {
      mobile.dispose();
      app.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MobileServices.channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
