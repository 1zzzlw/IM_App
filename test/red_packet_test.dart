import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/models.dart';
import 'package:im_app/features/wallet/red_packet_page.dart';
import 'package:im_app/ui/components.dart';
import 'package:im_app/ui/theme.dart';

import 'support.dart';

class PaymentApi extends FixtureApi {
  final payments = <Json>[];
  @override
  Future<dynamic> post(String path, {dynamic data, Json? query}) async {
    if (path == '/redPacket/send') {
      payments.add(asJson(data));
      return {'id': 'packet'};
    }
    return null;
  }
}

void main() {
  testWidgets(
    'red packet requires confirmation and reuses payment message ID',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = PaymentApi();
      final socket = FakeSocket();
      final app = AppState(
        MemoryStorage(await SharedPreferences.getInstance()),
        client: api,
        connection: socket,
      );
      await app.acceptUser({'id': '100', 'username': '测试用户'});
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            theme: appTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => pushPage(
                    context,
                    SendRedPacketPage(conversation: app.conversations.single),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '2.30');
      await tester.ensureVisible(find.text('发红包'));
      await tester.tap(find.text('发红包'));
      await tester.pumpAndSettle();
      expect(find.text('确认发红包'), findsOneWidget);
      expect(api.payments, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.payments, isEmpty);
      await tester.tap(find.text('发红包'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(api.payments.single['totalAmount'], '2.30');
      expect(socket.sent.single.$2['id'], api.payments.single['messageId']);
      expect(socket.sent.single.$2['redPacketId'], 'packet');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await app.logout();
      app.dispose();
      await tester.pump();
    },
  );
}
