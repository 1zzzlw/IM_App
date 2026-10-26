import 'dart:convert';

typedef Json = Map<String, dynamic>;

Json asJson(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> asList(dynamic value) {
  // Java PageResult 的列表字段为 data；API 层已解开最外层 Result.data。
  if (value is Map) {
    value =
        value['data'] ?? value['records'] ?? value['list'] ?? value['items'];
  }
  return value is List ? value.map(asJson).toList() : [];
}

String str(dynamic value) => value?.toString() ?? '';
int number(dynamic value) => int.tryParse(str(value)) ?? 0;
bool flag(dynamic value) => value == true || value == 1 || value == '1';
String serverTime([DateTime? time]) => (time ?? DateTime.now())
    .toIso8601String()
    .substring(0, 19)
    .replaceFirst('T', ' ');
String clockText(dynamic value) {
  final date = DateTime.tryParse(str(value));
  if (date == null) return '';
  final today = DateTime.now();
  if (date.year == today.year &&
      date.month == today.month &&
      date.day == today.day) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return '${date.month}/${date.day}';
}

class ImUser {
  ImUser(this.data);
  final Json data;
  String get id => str(data['id'] ?? data['userId']);
  String get name => str(data['username']);
  String get avatar => str(data['avatar']);
  String get account => str(data['account']);
}

class Conversation {
  Conversation(this.data);
  final Json data;
  String get id => str(data['id']);
  String get targetId => str(data['targetId']);
  String get name =>
      str(data['remark']).isNotEmpty ? str(data['remark']) : str(data['name']);
  String get avatar => str(data['avatar']);
  bool get isGroup => number(data['type']) == 1 || id.startsWith('g_');
  bool get pinned => flag(data['isTop']);
  bool get muted => flag(data['isMute']);
  int get unread => number(data['unreadCount']);
  String get preview => str(data['latestMsg']);
  String get time => str(data['latestMsgTime']);
}

class Contact {
  Contact(this.data);
  final Json data;
  String get id => str(data['friendId'] ?? data['id']);
  String get name => str(data['remark']).isNotEmpty
      ? str(data['remark'])
      : str(data['username']);
  String get avatar => str(data['avatar']);
  int get status => number(data['relationStatus']);
}

class ChatMessage {
  ChatMessage(this.data);
  final Json data;
  String get id => str(data['id']);
  String get conversationId => str(data['conversationId']);
  String get senderId => str(data['senderId']);
  int get type => number(data['msgType']);
  int get status => number(data['sendStatus']);
  String get content => str(data['content']);
  String get url => str(data['remoteUrl']);
  String get fileName => str(data['fileName']);
  String get time => str(data['sendTime'] ?? data['receiveTime']);
  bool get revoked => flag(data['isRevoked']);
  String get displayText {
    if (revoked) return '消息已撤回';
    if (type == 99) {
      try {
        final body = asJson(jsonDecode(content));
        return str(body['tpl']).replaceAll('{name}', str(body['opName']));
      } catch (_) {
        return content;
      }
    }
    return switch (type) {
      2 => '[图片]',
      3 => '[视频]',
      4 => '[语音]',
      5 => '[文件] $fileName',
      6 => '[红包]',
      _ => content,
    };
  }
}
