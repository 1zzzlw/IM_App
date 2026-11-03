import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumina_agent/core/camera_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestPicker extends ImagePicker {
  XFile? photo;
  PlatformException? failure;
  Completer<XFile?>? pending;
  LostDataResponse lost = LostDataResponse.empty();
  int calls = 0;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(source, ImageSource.camera);
    expect(imageQuality, 85);
    expect(requestFullMetadata, false);
    calls++;
    if (failure != null) throw failure!;
    return pending == null ? photo : pending!.future;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async => lost;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('拍照保留账号、服务器和会话信息，确认发送前不执行上传', () async {
    final preferences = await SharedPreferences.getInstance();
    final picker = TestPicker()
      ..photo = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'photo.jpg',
      );
    final camera = CameraCapture(preferences, picker: picker);
    final photo = await camera.take('100', 'http://server', '200_100');
    expect(photo!.accountId, '100');
    expect(photo.server, 'http://server');
    expect(photo.conversationId, '200_100');
    expect(await photo.file.readAsBytes(), [1, 2, 3]);
    await camera.clear();
    expect(preferences.getString('im.camera.pending'), isNull);
  });

  test('取消拍照和权限拒绝都清理待恢复记录', () async {
    final preferences = await SharedPreferences.getInstance();
    final picker = TestPicker();
    final camera = CameraCapture(preferences, picker: picker);
    expect(await camera.take('100', 'server', 'chat'), isNull);
    expect(preferences.getString('im.camera.pending'), isNull);
    picker.failure = PlatformException(code: 'camera_access_denied');
    await expectLater(
      camera.take('100', 'server', 'chat'),
      throwsA(isA<PlatformException>()),
    );
    expect(preferences.getString('im.camera.pending'), isNull);
  });

  test('快速点击只启动一次系统相机', () async {
    final picker = TestPicker()..pending = Completer<XFile?>();
    final camera = CameraCapture(
      await SharedPreferences.getInstance(),
      picker: picker,
    );
    final first = camera.take('100', 'server', 'chat');
    expect(await camera.take('100', 'server', 'chat'), isNull);
    picker.pending!.complete(null);
    await first;
    expect(picker.calls, 1);
  });

  test('相机期间进程回收后恢复照片及原会话，保留账号隔离信息', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'im.camera.pending',
      jsonEncode({
        'accountId': '100',
        'server': 'http://server',
        'conversationId': '200_100',
      }),
    );
    final picker = TestPicker()
      ..lost = LostDataResponse(
        files: [
          XFile.fromData(Uint8List.fromList([1]), name: 'recovered.jpg'),
        ],
      );
    final draft = await CameraCapture(preferences, picker: picker).recover();
    expect(draft!.accountId, '100');
    expect(draft.server, 'http://server');
    expect(draft.conversationId, '200_100');
  });
}
