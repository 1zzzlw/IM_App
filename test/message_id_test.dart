import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:im_app/core/app_state.dart';
import 'package:im_app/core/im_protocol.dart';
import 'package:im_app/core/message_id.dart';

import 'support.dart';

void main() {
  test('matches vectors from the installed Electron Snowflake generator', () {
    final generator = MessageIdGenerator(
      shardId: 37,
      clock: () => 1793060340000,
    );
    // @theinternetfolks/snowflake 1.3.0 实际入口 dist/index.js 的输出。
    expect(generator.next(), '7520640156303511552');
    expect(generator.next(), '7520640156303511553');
  });

  test('same-millisecond bursts remain unique and strictly increasing', () {
    const millis = 1793060340000;
    final generator = MessageIdGenerator(shardId: 37, clock: () => millis);
    final ids = List.generate(5000, (_) => BigInt.parse(generator.next()));
    expect(ids.toSet().length, 5000);
    for (var i = 1; i < ids.length; i++) {
      expect(ids[i], greaterThan(ids[i - 1]));
    }
    expect((ids.last >> 22).toInt(), millis + 1);
  });

  test('clock rollback does not generate an older ID', () {
    var millis = 1793060340000;
    final generator = MessageIdGenerator(shardId: 37, clock: () => millis);
    final first = BigInt.parse(generator.next());
    millis -= 1000;
    final second = BigInt.parse(generator.next());
    expect(second, greaterThan(first));
    millis += 1001;
    expect(BigInt.parse(generator.next()), greaterThan(second));
  });

  test('Java Long maximum is exact and overflow is rejected', () {
    final generator = MessageIdGenerator(
      shardId: 1023,
      clock: () => 2199023255551,
    );
    for (var i = 0; i < 4095; i++) {
      generator.next();
    }
    expect(generator.next(), '9223372036854775807');
    expect(generator.next, throwsStateError);
  });

  test('WS JSON preserves message and reference IDs as decimal strings', () {
    final body = {
      'id': '7520640156303511553',
      'quoteMsgId': '7520640156303511552',
      'redPacketId': '9223372036854775807',
    };
    final bytes = ImProtocol.encode(3, 1, body);
    expect(utf8.decode(bytes.sublist(16)), jsonEncode(body));
    expect(ImProtocol.decode(bytes).data, body);
  });

  test(
    'App IDs use the same Unix millisecond Snowflake range as Electron',
    () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState(
        MemoryStorage(await SharedPreferences.getInstance()),
        connection: FakeSocket(),
      );
      addTearDown(app.dispose);
      final before = DateTime.now().millisecondsSinceEpoch;
      final id = BigInt.parse(app.nextId());
      final after = DateTime.now().millisecondsSinceEpoch;
      expect((id >> 22).toInt(), inInclusiveRange(before, after));
      expect(id, lessThanOrEqualTo(BigInt.parse('9223372036854775807')));
    },
  );
}
