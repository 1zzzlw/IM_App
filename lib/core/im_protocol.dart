import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

class ImFrame {
  ImFrame(this.type, this.sequence, this.data);
  final int type;
  final int sequence;
  final Json data;
}

/// 与 Netty / Electron 一致的 16 字节大端帧头。
class ImProtocol {
  static Uint8List encode(int type, int sequence, Json data) {
    final body = utf8.encode(jsonEncode(data));
    final bytes = Uint8List(16 + body.length);
    bytes.setAll(0, [1, 2, 3, 4, 1, 0, type]);
    final header = ByteData.sublistView(bytes);
    header.setUint32(7, sequence, Endian.big);
    bytes[11] = 255;
    header.setUint32(12, body.length, Endian.big);
    bytes.setAll(16, body);
    return bytes;
  }

  static ImFrame decode(List<int> input) {
    final bytes = Uint8List.fromList(input);
    if (bytes.length < 16 ||
        bytes[0] != 1 ||
        bytes[1] != 2 ||
        bytes[2] != 3 ||
        bytes[3] != 4) {
      throw const FormatException('无效的 IM 帧头');
    }
    if (bytes[4] != 1 || bytes[5] != 0) {
      throw const FormatException('不支持的协议版本或序列化算法');
    }
    final header = ByteData.sublistView(bytes);
    final length = header.getUint32(12, Endian.big);
    if (length != bytes.length - 16) throw const FormatException('IM 消息长度不匹配');
    final decoded = jsonDecode(utf8.decode(bytes.sublist(16)));
    if (decoded is! Map) throw const FormatException('IM 消息正文必须为对象');
    return ImFrame(bytes[6], header.getUint32(7, Endian.big), asJson(decoded));
  }
}
