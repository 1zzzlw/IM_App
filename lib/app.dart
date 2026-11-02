import 'package:material_ui/material_ui.dart';

import 'dart:async';

import 'core/app_state.dart';
import 'core/mobile_services.dart';
import 'core/message_alert.dart';
import 'features/chat/chat_page.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';
import 'ui/components.dart';
import 'ui/theme.dart';

class ImApp extends StatefulWidget {
  const ImApp({super.key, required this.state, this.mobile});
  final AppState state;
  final MobileServices? mobile;
  @override
  State<ImApp> createState() => _ImAppState();
}

class _ImAppState extends State<ImApp> with WidgetsBindingObserver {
  final messenger = GlobalKey<ScaffoldMessengerState>();
  final navigator = GlobalKey<NavigatorState>();
  String? previousUser;
  OverlayEntry? _bannerEntry;
  Timer? _bannerTimer;
  (String, String)? _pendingOpen;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    previousUser = widget.state.user?.id;
    widget.state.addListener(_changed);
    widget.mobile?.onBanner = _showBanner;
    widget.mobile?.onOpen = (account, conversation) {
      _pendingOpen = (account, conversation);
      _changed();
    };
  }

  void _dismissBanner() {
    _bannerTimer?.cancel();
    _bannerEntry?.remove();
    _bannerEntry?.dispose();
    _bannerEntry = null;
  }

  void _showBanner(MessageAlert alert) {
    if (!mounted || widget.state.user?.id != alert.accountId) return;
    final overlay = navigator.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showBanner(alert));
      return;
    }
    _dismissBanner();
    _bannerEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 14,
        right: 14,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: GlassCard(
              padding: const EdgeInsets.all(12),
              child: InkWell(
                onTap: () {
                  _dismissBanner();
                  _pendingOpen = (alert.accountId, alert.conversationId);
                  _changed();
                },
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            alert.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            alert.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭提醒',
                      onPressed: _dismissBanner,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_bannerEntry!);
    _bannerTimer = Timer(const Duration(seconds: 4), _dismissBanner);
  }

  void _changed() {
    final current = widget.state.user?.id;
    if (previousUser != null && current == null) {
      navigator.currentState?.popUntil((route) => route.isFirst);
    }
    previousUser = current;
    if (current == null) _dismissBanner();
    if (current != null &&
        _pendingOpen != null &&
        _pendingOpen!.$1 != current) {
      _pendingOpen = null;
    }
    final recovered = widget.mobile?.recoveredPhoto;
    final pending =
        _pendingOpen ??
        (recovered == null || recovered.server != widget.state.httpUrl
            ? null
            : (recovered.accountId, recovered.conversationId));
    final photo =
        recovered != null &&
            pending?.$1 == recovered.accountId &&
            pending?.$2 == recovered.conversationId &&
            recovered.server == widget.state.httpUrl
        ? recovered
        : null;
    if (!_opening &&
        pending != null &&
        current == pending.$1 &&
        (photo == null || photo.server == widget.state.httpUrl)) {
      final conversation = widget.state.conversations
          .where((c) => c.id == pending.$2)
          .firstOrNull;
      if (conversation != null) {
        _opening = true;
        _pendingOpen = null;
        if (photo != null) widget.mobile?.recoveredPhoto = null;
        final previousConversation = widget.state.activeConversation;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            final closed = navigator.currentState?.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ChatPage(conversation: conversation, initialPhoto: photo),
              ),
            );
            _opening = false;
            await closed;
          }
          if (widget.state.user?.id == pending.$1) {
            widget.state.activeConversation = previousConversation;
          }
          _opening = false;
        });
      }
    }
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
    widget.state.inForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      widget.mobile?.refreshPermission();
    } else {
      widget.mobile?.synchronize();
    }
    if (state == AppLifecycleState.resumed && widget.state.user != null) {
      widget.state.sync().catchError((Object e) {
        widget.state.notice = e.toString();
        _changed();
      });
    }
  }

  @override
  void dispose() {
    _dismissBanner();
    widget.mobile?.dispose();
    widget.state.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    state: widget.state,
    mobile: widget.mobile,
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
