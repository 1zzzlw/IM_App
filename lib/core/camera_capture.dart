import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class CameraDraft {
  CameraDraft(this.file, this.accountId, this.server, this.conversationId);
  final XFile file;
  final String accountId;
  final String server;
  final String conversationId;
}

class CameraCapture {
  CameraCapture(this.preferences, {ImagePicker? picker})
    : picker = picker ?? ImagePicker();
  final SharedPreferences preferences;
  final ImagePicker picker;
  static const _pending = 'im.camera.pending';
  bool _busy = false;

  Future<CameraDraft?> take(
    String accountId,
    String server,
    String conversationId,
  ) async {
    if (_busy) return null;
    _busy = true;
    await preferences.setString(
      _pending,
      jsonEncode({
        'accountId': accountId,
        'server': server,
        'conversationId': conversationId,
      }),
    );
    try {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null) {
        await clear();
        return null;
      }
      await preferences.setString(
        _pending,
        jsonEncode({
          'accountId': accountId,
          'server': server,
          'conversationId': conversationId,
          'path': file.path,
        }),
      );
      return CameraDraft(file, accountId, server, conversationId);
    } catch (_) {
      await clear();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<CameraDraft?> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final result = await picker.retrieveLostData();
    final saved = preferences.getString(_pending);
    if (saved == null) return null;
    try {
      final data = asJson(jsonDecode(saved));
      if (result.exception != null) throw result.exception!;
      final file =
          result.files?.firstOrNull ??
          (str(data['path']).isEmpty ? null : XFile(str(data['path'])));
      if (file == null) {
        await clear();
        return null;
      }
      await file.length();
      return CameraDraft(
        file,
        str(data['accountId']),
        str(data['server']),
        str(data['conversationId']),
      );
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  Future<void> clear() async {
    await preferences.remove(_pending);
  }
}
