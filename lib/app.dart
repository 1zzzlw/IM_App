import 'package:material_ui/material_ui.dart';

import 'core/app_state.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'ui/components.dart';
import 'ui/theme.dart';

class ImApp extends StatefulWidget {
  const ImApp({super.key, required this.state});
  final AppState state;
  @override
  State<ImApp> createState() => _ImAppState();
}

class _ImAppState extends State<ImApp> with WidgetsBindingObserver {
  final messenger = GlobalKey<ScaffoldMessengerState>();
  final navigator = GlobalKey<NavigatorState>();
  String? previousUser;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    previousUser = widget.state.user?.id;
    widget.state.addListener(_changed);
  }

  void _changed() {
    final current = widget.state.user?.id;
    if (previousUser != null && current == null) {
      navigator.currentState?.popUntil((route) => route.isFirst);
    }
    previousUser = current;
    final notice = widget.state.notice;
    if (notice != null && notice.isNotEmpty) {
      widget.state.notice = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.currentState?.showSnackBar(SnackBar(content: Text(notice)));
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.state.user != null) {
      widget.state.sync().catchError((Object e) {
        widget.state.notice = e.toString();
        _changed();
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    state: widget.state,
    child: MaterialApp(
      title: '轻聊',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      navigatorKey: navigator,
      scaffoldMessengerKey: messenger,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          if (!widget.state.initialized) {
            return const GlassBackground(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: widget.state.user == null
                ? const LoginPage(key: ValueKey('login'))
                : const HomePage(key: ValueKey('home')),
          );
        },
      ),
    ),
  );
}
