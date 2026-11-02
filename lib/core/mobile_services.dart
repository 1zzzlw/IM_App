import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'app_state.dart';
import 'camera_capture.dart';
import 'message_alert.dart';
import 'models.dart';

/// 原生通知和前台服务复用当前 Flutter 引擎及聊天连接。
class MobileServices extends ChangeNotifier {
  MobileServices(this.app) : camera = CameraCapture(app.storage.preferences);
  final AppState app;
  final CameraCapture camera;
  static const channel = MethodChannel('im_app/mobile');
  final AudioPlayer _sound = AudioPlayer();
  final _seen = <String>{};
  StreamSubscription<MessageAlert>? _alerts;
  void Function(MessageAlert)? onBanner;
  void Function(String accountId, String conversationId)? onOpen;
  CameraDraft? recoveredPhoto;
  bool permissionGranted = false;
  bool _asked = false;
  bool _syncing = false;
  bool _resync = false;
  bool _closed = false;
  bool _loggingOut = false;
  String _keepAlive = '';
  DateTime _lastSound = DateTime.fromMillisecondsSinceEpoch(0);
  bool get supported => android;
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get enabled =>
      app.storage.preferences.getBool('im.notifications') ?? true;
  bool get soundEnabled =>
      app.storage.preferences.getBool('im.messageSound') ?? true;
  bool get backgroundEnabled =>
      app.storage.preferences.getBool('im.background') ?? true;

  Future<void> initialize() async {
    if (!supported) return;
    channel.setMethodCallHandler((call) async {
      final data = asJson(call.arguments);
      if (call.method == 'notificationOpened') {
        onOpen?.call(str(data['accountId']), str(data['conversationId']));
      }
    });
    final status = asJson(await channel.invokeMethod('initialize'));
    permissionGranted = status['granted'] == true;
    final launch = asJson(status['launch']);
    if (launch.isNotEmpty) {
      onOpen?.call(str(launch['accountId']), str(launch['conversationId']));
    }
    _alerts = app.messageAlerts.stream.listen(
      (alert) => unawaited(_present(alert)),
    );
    app.addListener(_changed);
    app.beforeLogout = _logout;
    try {
      recoveredPhoto = await camera.recover();
    } catch (e) {
      app.notice = '拍摄照片恢复失败：$e';
    }
    await synchronize();
  }

  void _changed() {
    unawaited(synchronize());
  }

  Future<void> synchronize() async {
    if (!supported || _closed) return;
    if (_loggingOut) {
      if (app.user != null) return;
      _loggingOut = false;
    }
    if (_syncing) {
      _resync = true;
      return;
    }
    _syncing = true;
    try {
      if (app.user != null && app.inForeground && enabled && !_asked) {
        _asked = true;
        permissionGranted =
            await channel.invokeMethod<bool>('requestPermission') ?? false;
      }
      final keep = '${app.user?.id}:${backgroundEnabled && app.user != null}';
      if (android &&
          keep != _keepAlive &&
          (app.inForeground || app.user == null || !backgroundEnabled)) {
        await channel.invokeMethod('background', {
          'enabled': backgroundEnabled && app.user != null,
        });
        _keepAlive = keep;
      }
    } catch (e) {
      debugPrint('更新消息通知状态失败：$e');
    } finally {
      _syncing = false;
      if (!_closed) notifyListeners();
      if (_resync && !_closed) {
        _resync = false;
        unawaited(synchronize());
      }
    }
  }

  Future<void> setOption(String key, bool value) async {
    await app.storage.preferences.setBool(key, value);
    if (key == 'im.notifications' && value) _asked = false;
    await synchronize();
  }

  Future<void> _present(MessageAlert alert) async {
    if (_closed || !enabled || alert.accountId != app.user?.id) return;
    if (app.inForeground && app.activeConversation == alert.conversationId) {
      return;
    }
    if (app.conversations.any((c) => c.id == alert.conversationId && c.muted)) {
      return;
    }
    final key = '${alert.accountId}:${alert.messageId}';
    if (!_seen.add(key)) return;
    if (_seen.length > 256) _seen.remove(_seen.first);
    try {
      if (app.inForeground) {
        onBanner?.call(alert);
        if (soundEnabled &&
            DateTime.now().difference(_lastSound).inMilliseconds >= 700) {
          _lastSound = DateTime.now();
          await _sound.setAsset('assets/audio/message.mp3');
          await _sound.play();
        }
      } else {
        await channel.invokeMethod('notify', {
          ...alert.toJson(),
          'sound': soundEnabled,
        });
      }
    } catch (e) {
      debugPrint('消息提醒失败：$e');
    }
  }

  Future<void> refreshPermission() async {
    if (!supported) return;
    final status = asJson(await channel.invokeMethod('initialize'));
    permissionGranted = status['granted'] == true;
    await synchronize();
  }

  Future<void> _logout() async {
    if (!supported) return;
    _loggingOut = true;
    recoveredPhoto = null;
    await channel.invokeMethod('cancelNotifications');
    if (android) await channel.invokeMethod('background', {'enabled': false});
    _keepAlive = '';
    _seen.clear();
    await camera.clear();
  }

  @override
  void dispose() {
    _closed = true;
    app.removeListener(_changed);
    app.beforeLogout = null;
    _alerts?.cancel();
    channel.setMethodCallHandler(null);
    _sound.dispose();
    super.dispose();
  }
}
