import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:im_app/core/api_client.dart';
import 'package:im_app/core/im_protocol.dart';
import 'package:im_app/features/wallet/wallet_page.dart' show validAmount;

void main() {
  test(
    'Netty frame preserves big-endian sequence, Chinese, emoji and Long IDs',
    () {
      const id = '1792113130553123456';
      final bytes = ImProtocol.encode(3, 0x12345678, {
        'id': id,
        'content': '你好 🌊',
      });
      expect(bytes.sublist(0, 12), [
        1,
        2,
        3,
        4,
        1,
        0,
        3,
        0x12,
        0x34,
        0x56,
        0x78,
        255,
      ]);
      expect(ByteData.sublistView(bytes).getUint32(12), bytes.length - 16);
      final frame = ImProtocol.decode(bytes);
      expect(frame.sequence, 0x12345678);
      expect(frame.type, 3);
      expect(frame.data, {'id': id, 'content': '你好 🌊'});
    },
  );
  test('rejects malformed, truncated and unsupported protocol frames', () {
    expect(() => ImProtocol.decode([1, 2, 3]), throwsFormatException);
    final bytes = ImProtocol.encode(2, 0, {});
    bytes[5] = 1;
    expect(() => ImProtocol.decode(bytes), throwsFormatException);
    bytes[5] = 0;
    bytes[15] = 50;
    expect(() => ImProtocol.decode(bytes), throwsFormatException);
  });
  test(
    'SSE handles UTF-8 split across bytes, CRLF and multiple data lines',
    () async {
      final source = utf8.encode(
        'event: message.delta\r\ndata: {"delta":"你好🌊"}\r\n\r\nevent: extra\ndata: first\ndata: second\n\nevent: done\ndata: {}\n\n',
      );
      final events = await parseSse(
        Stream.fromIterable(source.map((byte) => [byte])),
      ).toList();
      expect(events.map((e) => e.event), ['message.delta', 'extra', 'done']);
      expect(events[0].data, '{"delta":"你好🌊"}');
      expect(events[1].data, 'first\nsecond');
    },
  );
  test('does not emit incomplete SSE event', () async {
    final events = await parseSse(
      Stream.value(utf8.encode('event: done\ndata: {}')),
    ).toList();
    expect(events, isEmpty);
  });
  test('money uses exact cents and rejects invalid financial parameters', () {
    expect(validAmount('000.1'), '0.10');
    expect(validAmount('12.99'), '12.99');
    for (final value in [
      '0',
      '-1',
      'NaN',
      'Infinity',
      '0.001',
      '1e2',
      '',
      '1.2.3',
    ]) {
      expect(() => validAmount(value), throwsException, reason: value);
    }
  });
}
