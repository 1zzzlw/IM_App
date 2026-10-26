import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'im_protocol.dart';
import 'im_socket.dart';
import 'models.dart';
import 'session_storage.dart';

/// 应用状态只负责会话生命周期、消息同步和缓存；页面通过监听状态刷新。
class AppState extends ChangeNotifier {
  AppState(this.storage, {ApiClient? client, ImSocket? connection})
    : api =
          client ??
          ApiClient(storage.preferences.getString('im.http') ?? defaultHttp),
      socket = connection ?? ImSocket() {
    api.onTokens = _persistSession;
    api.onExpired = () => logout(reason: '登录已过期，请重新登录');
    socket.beforeReconnect = api.refresh;
    _frames = socket.frames.stream.listen(
      _onFrame,
      onError: (Object e) {
        notice = e.toString();
        notifyListeners();
      },
    );
    _states = socket.states.stream.listen((value) {
      notifyListeners();
      if (value == ConnectionState.online && user != null) {
        unawaited(
          sync().catchError((Object e) {
            notice = e.toString();
            notifyListeners();
          }),
        );
      }
    });
  }
  // 10.0.2.2 仅供 Android 模拟器访问宿主机，桌面及 Web 应连接本机回环地址。
  // 真机和远程服务继续通过连接设置或 dart-define 指定，不覆盖用户保存的地址。
  static String get _defaultHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : '127.0.0.1';
  static String get defaultHttp {
    const configured = String.fromEnvironment('API_BASE_URL');
    return configured.isNotEmpty ? configured : 'http://$_defaultHost:81';
  }

  static String get defaultWs {
    const configured = String.fromEnvironment('WS_BASE_URL');
    return configured.isNotEmpty ? configured : 'ws://$_defaultHost/ws';
  }

  final SessionStorage storage;
  final ApiClient api;
  final ImSocket socket;
  late final StreamSubscription<ImFrame> _frames;
  late final StreamSubscription<ConnectionState> _states;
  ImUser? user;
  List<Conversation> conversations = [];
  List<Contact> contacts = [];
  final Map<String, List<ChatMessage>> messages = {};
  final Map<String, List<Json>> members = {};
  final Set<String> onlineUsers = {};
  final Map<String, Timer> _pending = {};
  String? activeConversation;
  String? notice;
  bool initialized = false;
  bool syncing = false;
  Future<void>? _syncing;
  Timer? _cacheTimer;
  int _sessionGeneration = 0;
  final Random _random = Random.secure();
  String get wsUrl => storage.preferences.getString('im.ws') ?? defaultWs;
  String get httpUrl => api.dio.options.baseUrl;
  String get cacheKey => '${Uri.encodeComponent(httpUrl)}.${user?.id ?? ''}';
  int get unread =>
      conversations.where((c) => !c.muted).fold(0, (sum, c) => sum + c.unread);

  Future<void> initialize() async {
    try {
      final session = await storage.readSession();
      if (session['server'] == httpUrl && session['user'] is Map) {
        user = ImUser(asJson(session['user']));
        api.userId = user!.id;
        api.accessToken = str(session['accessToken']);
        api.refreshToken = str(session['refreshToken']);
        _restoreCache();
        // 网络失败时保留本地会话，鉴权失败才返回登录页。
        try {
          await api.refresh();
        } catch (e) {
          notice = e.toString();
        }
        if (user != null) {
          unawaited(socket.connect(wsUrl, () async => api.accessToken));
        }
      }
    } catch (e) {
      notice = '读取登录信息失败：$e';
    }
    initialized = true;
    notifyListeners();
  }

  Future<void> configure(String http, String ws) async {
    final parsedHttp = Uri.tryParse(http.trim());
    final parsedWs = Uri.tryParse(ws.trim());
    if (parsedHttp == null ||
        !['http', 'https'].contains(parsedHttp.scheme) ||
        parsedHttp.host.isEmpty ||
        parsedWs == null ||
        !['ws', 'wss'].contains(parsedWs.scheme) ||
        parsedWs.host.isEmpty) {
      throw ApiException('请输入完整的 HTTP 和 WebSocket 地址');
    }
    if (user != null) await logout();
    api.dio.options.baseUrl = http.trim().replaceFirst(RegExp(r'/$'), '');
    await storage.preferences.setString('im.http', api.dio.options.baseUrl);
    await storage.preferences.setString('im.ws', ws.trim());
    notifyListeners();
  }

  Future<void> login(String account, String password, String captcha) async {
    final result = await api.response(
      'POST',
      '/user/login',
      authenticated: false,
      data: {
        'account': account.trim(),
        'password': password,
        'verifyCode': captcha.trim(),
      },
    );
    final profile = asJson(api.unwrap(result));
    if (str(profile['id']).isEmpty || api.accessToken.isEmpty) {
      throw ApiException('登录响应缺少用户信息或 Token');
    }
    await acceptUser(profile);
  }

  Future<void> acceptUser(Json profile) async {
    ++_sessionGeneration;
    user = ImUser(profile);
    api.userId = user!.id;
    _restoreCache();
    await _persistSession();
    notifyListeners();
    unawaited(socket.connect(wsUrl, () async => api.accessToken));
    try {
      await sync();
    } catch (e) {
      notice = e.toString();
      notifyListeners();
    }
  }

  Future<void> _persistSession() async {
    if (user == null) return;
    await storage.saveSession({
      'server': httpUrl,
      'user': user!.data,
      'accessToken': api.accessToken,
      'refreshToken': api.refreshToken,
    });
  }

  Future<void> logout({String? reason}) async {
    ++_sessionGeneration;
    socket.disconnect();
    _cacheTimer?.cancel();
    await _saveCache();
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    _syncing = null;
    syncing = false;
    user = null;
    api.userId = '';
    api.accessToken = '';
    api.refreshToken = '';
    conversations = [];
    contacts = [];
    messages.clear();
    members.clear();
    onlineUsers.clear();
    activeConversation = null;
    notice = reason;
    await storage.clearSession();
    notifyListeners();
  }

  void _restoreCache() {
    final cached = storage.readCache(cacheKey);
    conversations = asList(cached['conversations'])
        .map(Conversation.new)
        .toList();
    contacts = asList(cached['contacts']).map(Contact.new).toList();
    messages.clear();
    asJson(cached['messages']).forEach((key, value) {
      messages[key] = asList(value).map((data) {
        if (number(data['sendStatus']) == 0) data['sendStatus'] = 2;
        return ChatMessage(data);
      }).toList();
    });
  }

  void _changed() {
    notifyListeners();
    _cacheTimer?.cancel();
    _cacheTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_saveCache()),
    );
  }

  Future<void> _saveCache() async {
    if (user == null) return;
    await storage.saveCache(cacheKey, {
      'conversations': conversations.map((c) => c.data).toList(),
      'contacts': contacts.map((c) => c.data).toList(),
      'messages': messages.map(
        (key, list) => MapEntry(
          key,
          list.skip(max(0, list.length - 150)).map((m) => m.data).toList(),
        ),
      ),
    });
  }

  Future<void> sync() {
    if (_syncing != null) return _syncing!;
    late final Future<void> task;
    task = _sync().whenComplete(() {
      if (_syncing == task) _syncing = null;
    });
    _syncing = task;
    return task;
  }

  Future<void> _sync() async {
    if (user == null) return;
    final generation = _sessionGeneration;
    syncing = true;
    notifyListeners();
    try {
      final result = await Future.wait([
        api.get('/conversation/init/list', query: {'isInit': true}),
        api.get('/friend/init/list', query: {'isInit': true}),
      ]);
      if (generation != _sessionGeneration) return;
      conversations = asList(result[0]).map(Conversation.new).toList();
      for (final conversation in conversations) {
        if (conversation.id == activeConversation) {
          conversation.data['unreadCount'] = 0;
        }
      }
      contacts = asList(result[1]).map(Contact.new).toList();
      _sortConversations();
      if (conversations.isNotEmpty) {
        // 每批 20 个会话，避免 GET 路径过长；合并到缓存而不是覆盖实时消息。
        final ids = conversations.map((c) => c.id).toList();
        for (var start = 0; start < ids.length; start += 20) {
          final batch = ids
              .sublist(start, min(start + 20, ids.length))
              .join(',');
          final data = await api.get(
            '/message/init/list/$batch',
            query: {'isInit': true},
          );
          if (generation != _sessionGeneration) return;
          for (final item in asList(data)) {
            _merge(ChatMessage(item));
          }
        }
      }
      _changed();
    } finally {
      if (generation == _sessionGeneration) {
        syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> openConversation(Conversation conversation) async {
    activeConversation = conversation.id;
    conversation.data['unreadCount'] = 0;
    _changed();
    await Future.wait([
      api.put('/conversation/isReaded/${conversation.id}'),
      loadLatest(conversation.id),
      if (conversation.isGroup) loadMembers(conversation.id),
    ]);
  }

  Future<void> loadLatest(String id) async {
    final generation = _sessionGeneration;
    final data = await api.get(
      '/message/init/list/$id',
      query: {'isInit': true},
    );
    if (generation != _sessionGeneration) return;
    for (final item in asList(data)) {
      _merge(ChatMessage(item));
    }
    _changed();
  }

  Future<int> loadOlder(String id) async {
    final list = messages[id] ?? [];
    final oldest =
        list
            .where((m) => m.status == 1)
            .map((m) => BigInt.tryParse(m.id))
            .whereType<BigInt>()
            .toList()
          ..sort();
    if (oldest.isEmpty) {
      await loadLatest(id);
      return 0;
    }
    final generation = _sessionGeneration;
    final data = asList(
      await api.get(
        '/message/pull/list',
        query: {'conversationId': id, 'maxMessageId': oldest.first.toString()},
      ),
    );
    if (generation != _sessionGeneration) return 0;
    for (final item in data) {
      _merge(ChatMessage(item));
    }
    _changed();
    return data.length;
  }

  Future<void> loadMembers(String id) async {
    final generation = _sessionGeneration;
    final result = asList(await api.get('/conversation/groupMemberList/$id'));
    if (generation != _sessionGeneration) return;
    members[id] = result;
    notifyListeners();
  }

  Future<Conversation> conversationFor(Contact contact) async {
    for (final c in conversations) {
      if (!c.isGroup && c.targetId == contact.id) return c;
    }
    // 与 ApplyServiceImpl 一致：较大用户 ID 在前，不添加额外前缀。
    final ids = [user!.id, contact.id]
      ..sort((a, b) => BigInt.parse(b).compareTo(BigInt.parse(a)));
    final id = ids.join('_');
    // 好友申请通过时后端已建立双方会话；列表只返回 status=1 的会话。
    // 隐藏或新建会话由首条消息恢复显示，不能再次 INSERT 造成重复主键。
    final conversation = Conversation({
      'id': id,
      'targetId': contact.id,
      'name': contact.name,
      'avatar': contact.avatar,
      'type': 0,
    });
    conversations.add(conversation);
    _changed();
    return conversation;
  }

  String nextId() =>
      (BigInt.from(DateTime.now().millisecondsSinceEpoch) *
                  BigInt.from(1000000) +
              BigInt.from(_random.nextInt(1000000)))
          .toString();
  Json messageBody(
    Conversation conversation,
    String content,
    int type, {
    ChatMessage? quote,
  }) => {
    'id': nextId(),
    'senderId': user!.id,
    'conversationId': conversation.id,
    'receiverId': conversation.isGroup
        ? conversation.id
        : conversation.targetId,
    'msgType': type,
    'content': content,
    'sendStatus': 0,
    'sendTime': serverTime(),
    if (quote != null) 'quoteMsgId': quote.id,
    if (quote != null) 'quoteContent': quote.displayText,
    if (quote != null) 'quoteMsgType': quote.type,
  };
  Future<ChatMessage> send(
    Conversation conversation,
    String content, {
    int type = 1,
    Json? extra,
    ChatMessage? quote,
  }) async {
    final sendingUser = user?.id;
    if (socket.state != ConnectionState.online) {
      throw ApiException('正在连接服务器，请稍后发送');
    }
    if (!conversation.isGroup) {
      final found = contacts.where((c) => c.id == conversation.targetId);
      if (found.isNotEmpty && found.first.status >= 2) {
        throw ApiException('当前好友关系不允许发送消息');
      }
    }
    if (conversation.isGroup && !members.containsKey(conversation.id)) {
      await loadMembers(conversation.id);
    }
    if (sendingUser == null || sendingUser != user?.id) {
      throw ApiException('登录状态已变化');
    }
    final myMembership = (members[conversation.id] ?? [])
        .where((m) => str(m['userId']) == sendingUser)
        .firstOrNull;
    if (conversation.isGroup && flag(myMembership?['isMute'])) {
      throw ApiException('你已被禁言，暂时无法发送消息');
    }
    final body = messageBody(conversation, content, type, quote: quote)
      ..addAll(extra ?? {});
    if (conversation.isGroup) {
      body['receiverIds'] = (members[conversation.id] ?? [])
          .map((m) => str(m['userId']))
          .where((id) => id != user!.id)
          .toList();
    }
    final message = ChatMessage(body);
    _merge(message);
    _updatePreview(message);
    _changed();
    _transmit(conversation, message);
    return message;
  }

  void _transmit(Conversation conversation, ChatMessage message) {
    try {
      socket.send(conversation.isGroup ? 3 : 1, message.data);
    } catch (_) {
      message.data['sendStatus'] = 2;
      _changed();
      return;
    }
    _pending[message.id]?.cancel();
    _pending[message.id] = Timer(const Duration(seconds: 20), () {
      _pending.remove(message.id);
      message.data['sendStatus'] = 2;
      _changed();
    });
  }

  void retry(Conversation conversation, ChatMessage message) {
    if (socket.state != ConnectionState.online) throw ApiException('连接尚未恢复');
    message.data['sendStatus'] = 0;
    _transmit(conversation, message);
    _changed();
  }

  void _merge(ChatMessage message) {
    if (message.id.isEmpty || message.conversationId.isEmpty) return;
    final list = messages.putIfAbsent(message.conversationId, () => []);
    final index = list.indexWhere((m) => m.id == message.id);
    if (index >= 0) {
      final previous = list[index];
      previous.data.addAll(message.data);
    } else {
      list.add(message);
    }
    list.sort((a, b) {
      final time = a.time.compareTo(b.time);
      return time != 0
          ? time
          : (BigInt.tryParse(a.id) ?? BigInt.zero).compareTo(
              BigInt.tryParse(b.id) ?? BigInt.zero,
            );
    });
  }

  void _updatePreview(ChatMessage message, {bool incoming = false}) {
    for (final c in conversations.where(
      (c) => c.id == message.conversationId,
    )) {
      c.data['latestMsg'] = message.displayText;
      c.data['latestMsgTime'] = message.time;
      if (incoming &&
          activeConversation != c.id &&
          message.senderId != user?.id) {
        c.data['unreadCount'] = c.unread + 1;
      }
    }
    _sortConversations();
  }

  void _sortConversations() => conversations.sort((a, b) {
    final pinned = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
    return pinned != 0 ? pinned : b.time.compareTo(a.time);
  });

  void _onFrame(ImFrame frame) {
    if (user == null) return;
    final data = frame.data;
    switch (frame.type) {
      case 2:
      case 4:
      case 13:
        final message = ChatMessage(data);
        final exists = (messages[message.conversationId] ?? []).any(
          (m) => m.id == message.id,
        );
        data['sendStatus'] = 1;
        if (frame.type == 13) {
          data['msgType'] = 99;
          if (number(data['subType']) == 10) {
            try {
              final target = str(
                asJson(jsonDecode(str(data['content'])))['operationData'],
              );
              for (final m
                  in messages[message.conversationId] ?? <ChatMessage>[]) {
                if (m.id == target) m.data['isRevoked'] = 1;
              }
            } catch (_) {
              /* 不完整系统消息仍保留原文。 */
            }
          }
          unawaited(
            sync().catchError((Object e) {
              notice = e.toString();
              notifyListeners();
            }),
          );
        }
        _merge(message);
        if (!exists) _updatePreview(message, incoming: true);
        if (activeConversation == message.conversationId) {
          unawaited(
            api
                .put('/conversation/isReaded/${message.conversationId}')
                .catchError((Object _) => null),
          );
        }
        if (!conversations.any((c) => c.id == message.conversationId)) {
          unawaited(
            sync().catchError((Object e) {
              notice = e.toString();
              notifyListeners();
            }),
          );
        }
        break;
      case 16:
        final temporary = str(data['tempId']);
        _pending.remove(temporary)?.cancel();
        for (final list in messages.values) {
          final found = list.where((m) => m.id == temporary);
          if (found.isEmpty) continue;
          found.first.data['sendStatus'] = number(data['status']) == 0 ? 1 : 2;
          if (number(data['status']) == 0 &&
              str(data['messageId']).isNotEmpty) {
            found.first.data['id'] = str(data['messageId']);
          }
        }
        if (number(data['status']) != 0) notice = str(data['errorCase']);
        break;
      case 9:
        onlineUsers.add(str(data['userId']));
        break;
      case 10:
        onlineUsers
          ..clear()
          ..addAll((data['friendIdList'] as List? ?? []).map(str));
        break;
      case 11:
        onlineUsers.remove(str(data['userId']));
        break;
      case 6:
        notice = '收到新的好友申请';
        break;
      case 8:
        notice = '收到新的群聊邀请';
        break;
      case 15:
      case 18:
        unawaited(
          sync().catchError((Object e) {
            notice = e.toString();
            notifyListeners();
          }),
        );
        break;
    }
    _changed();
  }

  Future<void> recall(Conversation conversation, ChatMessage message) async {
    await api.delete(
      '/message/recallMessage',
      query: {'conversationId': conversation.id, 'messageId': message.id},
    );
    message.data['isRevoked'] = 1;
    _changed();
    final body = messageBody(
      conversation,
      jsonEncode({
        'tpl': '${user!.name} 撤回了一条消息',
        'opName': user!.name,
        'opId': user!.id,
        'operationData': message.id,
      }),
      99,
    );
    body['subType'] = 10;
    body['receiverIds'] = conversation.isGroup
        ? (members[conversation.id] ?? [])
              .map((m) => str(m['userId']))
              .where((id) => id != user!.id)
              .toList()
        : [conversation.targetId];
    socket.send(12, body);
  }

  Future<void> setConversationFlag(
    Conversation c,
    String key,
    bool value,
  ) async {
    await api.post(
      key == 'isTop'
          ? '/conversation/updateTopStatus'
          : '/conversation/updateMuteStatus',
      query: {'conversationId': c.id, key: value ? 1 : 0},
    );
    c.data[key] = value ? 1 : 0;
    _sortConversations();
    _changed();
  }

  Future<void> deleteConversation(Conversation c) async {
    await api.delete('/conversation/delete', query: {'conversationId': c.id});
    conversations.removeWhere((item) => item.id == c.id);
    _changed();
  }

  Future<void> clearHistory(Conversation c) async {
    await api.delete('/message/clearHistoryMessage/${c.id}');
    messages.remove(c.id);
    _changed();
  }

  Future<void> clearLocalCache() async {
    _cacheTimer?.cancel();
    messages.clear();
    await storage.clearCache(cacheKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _frames.cancel();
    _states.cancel();
    socket.dispose();
    api.dio.close(force: true);
    super.dispose();
  }
}
