import 'dart:math';

/// 对齐 Electron 的 @theinternetfolks/snowflake：epoch=0，毫秒左移 22 位。
/// ID 始终使用 BigInt 计算并输出字符串，避免 JS 精度损失和 Java Long 溢出。
class MessageIdGenerator {
  MessageIdGenerator({int? shardId, int Function()? clock})
    : _shardId = shardId ?? Random.secure().nextInt(1024),
      _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (_shardId < 0 || _shardId >= 1024) {
      throw ArgumentError.value(_shardId, 'shardId', '必须在 0 到 1023 之间');
    }
  }

  static final _maxLong = (BigInt.one << 63) - BigInt.one;
  final int _shardId;
  final int Function() _clock;
  int _lastMillis = -1;
  int _sequence = 0;

  String next() {
    var millis = max(_clock(), _lastMillis);
    _sequence = millis == _lastMillis ? _sequence + 1 : 0;
    // 同毫秒用 12 位序列递增；序列耗尽或时钟回拨时维持逻辑时钟递增。
    if (_sequence >= 4096) {
      millis++;
      _sequence = 0;
    }
    final id =
        (BigInt.from(millis) << 22) |
        (BigInt.from(_shardId) << 12) |
        BigInt.from(_sequence);
    if (millis < 0 || id > _maxLong) {
      throw StateError('消息 ID 超出 Java Long 范围，请检查设备时间');
    }
    _lastMillis = millis;
    return id.toString();
  }
}
