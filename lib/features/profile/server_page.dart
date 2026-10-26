import 'package:material_ui/material_ui.dart';

import '../../core/app_state.dart';
import '../../ui/components.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final http = TextEditingController();
  final ws = TextEditingController();
  bool loaded = false;
  bool busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      final app = AppScope.of(context);
      http.text = app.httpUrl;
      ws.text = app.wsUrl;
      loaded = true;
    }
  }

  @override
  void dispose() {
    http.dispose();
    ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: '连接设置',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SectionLabel('服务器地址'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              http.text = AppState.defaultHttp;
              ws.text = AppState.defaultWs;
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('使用当前平台默认地址'),
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: http,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'HTTP 接口',
                  hintText: 'http://192.168.1.10:81',
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: ws,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'WebSocket',
                  hintText: 'ws://192.168.1.10/ws',
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Android 模拟器访问电脑使用 10.0.2.2；真机请填写电脑的局域网 IP，并连接同一个网络。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (AppScope.of(context).user != null &&
                      !await confirm(context, '更换服务器', '更换后需要重新登录。')) {
                    return;
                  }
                  if (!context.mounted) return;
                  setState(() => busy = true);
                  try {
                    await AppScope.of(context).configure(http.text, ws.text);
                    if (context.mounted) {
                      toast(context, '连接地址已保存');
                      Navigator.maybePop(context);
                    }
                  } catch (e) {
                    if (context.mounted) toast(context, e.toString());
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? '保存中…' : '保存连接设置'),
        ),
      ],
    ),
  );
}
