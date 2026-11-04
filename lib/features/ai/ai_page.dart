import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'agent_person_page.dart';
import 'agent_preferences_page.dart';

class AiPage extends AgentPersonPage {
  const AiPage({super.key});
}

class ModelConfigsPage extends StatelessWidget {
  const ModelConfigsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '模型设置',
      child: Loadable(
        load: () => app.api.get(
          '/ai-message/config/getConfig',
          query: {'userId': app.user!.id},
        ),
        builder: (context, data, reload) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextButton.icon(
              onPressed: () => pushPage(context, const AgentPreferencesPage()),
              icon: const Icon(Icons.favorite_outline_rounded),
              label: const Text('生活、通知与多模态能力'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                await pushPage(context, const ModelEditorPage());
                await reload();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加模型配置'),
            ),
            const SizedBox(height: 20),
            for (final config in asList(data))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(str(config['configName'])),
                    subtitle: Text(
                      '${config['providerName']} · ${config['modelName']}',
                    ),
                    leading: Icon(
                      flag(config['isActive'])
                          ? Icons.check_circle_rounded
                          : Icons.auto_awesome_outlined,
                      color: AppColors.primary,
                    ),
                    onTap: flag(config['isPublic'])
                        ? null
                        : () async {
                            await pushPage(
                              context,
                              ModelEditorPage(config: config),
                            );
                            await reload();
                          },
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => runAction(context, () async {
                        if (value == 'active') {
                          await app.api.put(
                            '/ai-message/config/switchModel',
                            data: {
                              'configId': config['id'],
                              'userId': app.user!.id,
                            },
                          );
                        } else {
                          if (!await confirm(
                            context,
                            '删除模型配置',
                            '确定删除 ${config['configName']} 吗？',
                          )) {
                            return;
                          }
                          await app.api.delete(
                            '/ai-message/config/deleteModel/${config['id']}',
                            query: {'userId': app.user!.id},
                          );
                        }
                        await reload();
                      }),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'active',
                          child: Text('设为默认'),
                        ),
                        if (!flag(config['isPublic']))
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ModelEditorPage extends StatefulWidget {
  const ModelEditorPage({super.key, this.config});
  final Json? config;
  @override
  State<ModelEditorPage> createState() => _ModelEditorPageState();
}

class _ModelEditorPageState extends State<ModelEditorPage> {
  late final Map<String, TextEditingController> fields;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    fields = {
      for (final key in [
        'configName',
        'providerName',
        'modelName',
        'baseUrl',
        'apiKey',
      ])
        key: TextEditingController(
          text: key == 'apiKey' ? '' : str(widget.config?[key]),
        ),
    };
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: widget.config == null ? '添加模型' : '编辑模型',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final entry in {
          'configName': '配置名称',
          'providerName': '提供商（如 openai）',
          'modelName': '模型名称',
          'baseUrl': 'API 地址',
          'apiKey': widget.config == null ? 'API Key' : '新 API Key（留空保留原值）',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: fields[entry.key],
              obscureText: entry.key == 'apiKey',
              decoration: InputDecoration(labelText: entry.value),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (fields['configName']!.text.trim().isEmpty ||
                      fields['providerName']!.text.trim().isEmpty ||
                      fields['modelName']!.text.trim().isEmpty) {
                    toast(context, '请填写配置名称、提供商和模型名称');
                    return;
                  }
                  final app = AppScope.of(context);
                  setState(() => busy = true);
                  try {
                    final data = <String, dynamic>{
                      'userId': app.user!.id,
                      if (widget.config != null)
                        'configId': widget.config!['id'],
                      for (final entry in fields.entries)
                        if (entry.key != 'apiKey')
                          entry.key: entry.value.text.trim(),
                      'modelTemperature':
                          widget.config?['modelTemperature'] ?? 1,
                    };
                    String? configId = widget.config?['id'];
                    if (widget.config == null) {
                      final created = asJson(
                        await app.api.post(
                          '/ai-message/config/add_model',
                          data: data,
                        ),
                      );
                      configId = str(created['configId']);
                    } else {
                      await app.api.put(
                        '/ai-message/config/updateModel',
                        data: data,
                      );
                    }
                    if (fields['apiKey']!.text.trim().isNotEmpty) {
                      await app.api.put(
                        '/ai-message/person/credential',
                        data: {
                          'userId': app.user!.id,
                          'configId': configId,
                          'apiKey': fields['apiKey']!.text.trim(),
                        },
                      );
                    }
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) toast(context, e.toString());
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? '保存中…' : '保存配置'),
        ),
      ],
    ),
  );
}
