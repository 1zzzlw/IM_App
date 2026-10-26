import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 凭据只写入系统安全存储；界面设置与按账号隔离的有限消息缓存单独保存。
class SessionStorage {
  SessionStorage(this.preferences, {FlutterSecureStorage? secure})
    : secure = secure ?? const FlutterSecureStorage();
  final SharedPreferences preferences;
  final FlutterSecureStorage secure;

  Future<Json> readSession() async {
    final raw = await secure.read(key: 'im.session');
    if (raw == null) return {};
    try {
      return asJson(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSession(Json value) =>
      secure.write(key: 'im.session', value: jsonEncode(value));
  Future<void> clearSession() => secure.delete(key: 'im.session');
  Json readCache(String account) {
    try {
      return asJson(
        jsonDecode(preferences.getString('im.cache.$account') ?? '{}'),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCache(String account, Json value) async {
    await preferences.setString('im.cache.$account', jsonEncode(value));
  }

  Future<void> clearCache(String account) async {
    await preferences.remove('im.cache.$account');
  }
}
