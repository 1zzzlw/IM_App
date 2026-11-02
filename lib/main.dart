import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/session_storage.dart';
import 'core/mobile_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF3F6FC),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  final preferences = await SharedPreferences.getInstance();
  final state = AppState(SessionStorage(preferences));
  final mobile = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? MobileServices(state)
      : null;
  runApp(ImApp(state: state, mobile: mobile));
  try {
    await mobile?.initialize();
  } catch (error) {
    debugPrint('通知服务初始化失败：$error');
  }
  await state.initialize();
}
