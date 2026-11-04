import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../ui/components.dart';

class AgentPreferencesPage extends StatefulWidget {
  const AgentPreferencesPage({super.key});
  @override
  State<AgentPreferencesPage> createState() => _AgentPreferencesPageState();
}

class _AgentPreferencesPageState extends State<AgentPreferencesPage> {
  final window = TextEditingController(text: '60');
  bool loading = true,
      busy = false,
      online = true,
      read = true,
      typing = true,
      muted = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    window.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final app = AppScope.of(context);
    try {
      final result = await app.api.get(
        '/ai-message/person/settings',
        query: {'userId': app.user!.id},
      );
      if (!mounted) return;
      final settings = asJson(result);
      setState(() {
        window.text = str(settings['lifeWindowMinutes'] ?? 60);
        final visibility = asJson(settings['presenceVisibility']);
        online = visibility['online'] != false;
        read = visibility['read'] != false;
        typing = visibility['typing'] != false;
        muted = flag(asJson(settings['notifications'])['muted']);
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    final minutes = int.tryParse(window.text);
    if (minutes == null || minutes < 5 || minutes > 1440) {
      toast(context, '时间窗口为 5～1440 分钟');
      return;
    }
    final app = AppScope.of(context);
    setState(() => busy = true);
    try {
      await app.api.put(
        '/ai-message/person/settings',
        data: {
          'userId': app.user!.id,
          'lifeWindowMinutes': minutes,
          'onlineVisible': online,
          'readVisible': read,
          'typingVisible': typing,
          'muted': muted,
        },
      );
      if (mounted) toast(context, '已保存');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: '生活与通知',
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (error != null) Text(error!),
              const Text('生活推进', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 12),
              const Text('每个窗口可以继续原来的活动，不必产生新剧情。'),
              const SizedBox(height: 16),
              TextField(
                controller: window,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '时间窗口（分钟）'),
              ),
              SwitchListTile(
                title: const Text('公开在线状态'),
                value: online,
                onChanged: (v) => setState(() => online = v),
              ),
              SwitchListTile(
                title: const Text('公开已读状态'),
                value: read,
                onChanged: (v) => setState(() => read = v),
              ),
              SwitchListTile(
                title: const Text('公开输入状态'),
                value: typing,
                onChanged: (v) => setState(() => typing = v),
              ),
              SwitchListTile(
                title: const Text('消息免打扰'),
                value: muted,
                onChanged: (v) => setState(() => muted = v),
              ),
              FilledButton(
                onPressed: busy ? null : save,
                child: const Text('保存偏好'),
              ),
              const SizedBox(height: 32),
              const Text('模型使用', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 12),
              const Text('聊天窗口只切换对话的语言模型。记忆、回忆、生活以及图片和语音能力由服务端统一提供，不随聊天模型切换。'),
            ],
          ),
  );
}
