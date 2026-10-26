import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'im_protocol.dart';
import 'models.dart';

enum ConnectionState { offline, connecting, online, reconnecting }

/// 单连接、单心跳、单重连定时器；generation 防止旧连接回调污染新会话。
class ImSocket {
  final frames = StreamController<ImFrame>.broadcast();
  final states = StreamController<ConnectionState>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _retry;
  int _generation = 0;
  int _attempt = 0;
  bool _stopped = true;
  ConnectionState state = ConnectionState.offline;
  late String url;
  late Future<String> Function() token;
  Future<void> Function()? beforeReconnect;

  void _set(ConnectionState value) {
    state = value;
    states.add(value);
  }

  Future<void> connect(
    String address,
    Future<String> Function() readToken,
  ) async {
    disconnect();
    url = address;
    token = readToken;
    _stopped = false;
    _attempt = 0;
    await _open();
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _set(
      _attempt == 0 ? ConnectionState.connecting : ConnectionState.reconnecting,
    );
    try {
      if (_attempt > 0) await beforeReconnect?.call();
      final credential = await token();
      if (_stopped || generation != _generation || credential.isEmpty) return;
      final uri = Uri.parse(url);
      final channel = WebSocketChannel.connect(
        uri.replace(
          queryParameters: {...uri.queryParameters, 'token': credential},
        ),
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (raw) {
          if (generation != _generation) return;
          try {
            if (raw is List<int>) {
              frames.add(ImProtocol.decode(raw));
            }
          } on FormatException catch (e) {
            frames.addError(e);
          }
        },
        onError: (Object _) => _lost(generation),
        onDone: () => _lost(generation),
      );
      await channel.ready.timeout(const Duration(seconds: 15));
      if (generation != _generation || _stopped) return;
      _attempt = 0;
      _set(ConnectionState.online);
      _heartbeat = Timer.periodic(
        const Duration(seconds: 30),
        (_) => send(0, {'action': 'heartbeat'}),
      );
    } catch (_) {
      _lost(generation);
    }
  }

  void _lost(int generation) {
    if (generation != _generation || _stopped) return;
    ++_generation;
    _heartbeat?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _set(ConnectionState.reconnecting);
    _retry?.cancel();
    final seconds = [2, 4, 8, 15, 30][_attempt.clamp(0, 4)];
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void send(int type, Json body) {
    if (state != ConnectionState.online || _channel == null) {
      throw StateError('连接尚未就绪，请稍后重试');
    }
    _channel!.sink.add(ImProtocol.encode(type, 0, body));
  }

  void disconnect() {
    _stopped = true;
    ++_generation;
    _heartbeat?.cancel();
    _retry?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _set(ConnectionState.offline);
  }

  Future<void> dispose() async {
    disconnect();
    await frames.close();
    await states.close();
  }
}
