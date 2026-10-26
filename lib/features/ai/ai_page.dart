import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../chat/media_widgets.dart';

class AiPage extends StatefulWidget {
  const AiPage({super.key});
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final List<Json> messages = [];
  List<Json> conversations = [];
  List<Json> configs = [];
  String? conversationId;
  Json? model;
  bool loading = true;
  bool streaming = false;
  String? error;
  CancelToken? cancel;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    cancel?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final app = AppScope.of(context);
    try {
      final result = await Future.wait([
        app.api.get(
          '/ai-message/conversation/list',
          query: {'userId': app.user!.id},
        ),
        app.api.get(
          '/ai-message/config/getConfig',
          query: {'userId': app.user!.id},
        ),
      ]);
      if (mounted) {
        setState(() {
          conversations = asList(result[0]);
          configs = asList(result[1]);
          model = configs.where((c) => flag(c['isActive'])).firstOrNull;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openConversation(String id) async {
    if (streaming) return;
    setState(() => loading = true);
    try {
      final app = AppScope.of(context);
      final result = await app.api.get(
        '/ai-message/loadMessage',
        query: {'userId': app.user!.id, 'conversationId': id, 'limit': 500},
      );
      if (mounted) {
        setState(() {
          messages
            ..clear()
            ..addAll(asList(result));
          conversationId = id;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    if (streaming || input.text.trim().isEmpty) return;
    final app = AppScope.of(context);
    final id = conversationId ?? 'mobile_${app.nextId()}';
    final content = input.text.trim();
    input.clear();
    final assistant = <String, dynamic>{
      'role': 'assistant',
      'content': '',
      'reasoningContent': '',
    };
    setState(() {
      conversationId = id;
      streaming = true;
      error = null;
      messages.add({'role': 'user', 'content': content});
      messages.add(assistant);
    });
    cancel = CancelToken();
    var done = false;
    try {
      await for (final event in app.api.stream('/ai-message/sendMessage', {
        'id': app.nextId(),
        'conversationId': id,
        'userId': app.user!.id,
        'role': 'user',
        'messageType': 1,
        'content': content,
        'config': model == null
            ? {'providerName': 'default'}
            : {
                'providerName': model!['providerName'],
                'modelName': model!['modelName'],
                'configId': model!['id'],
                'modelTemperature': model!['modelTemperature'] ?? 1,
              },
      }, cancel!)) {
        if (!mounted) return;
        final data = asJson(jsonDecode(event.data));
        switch (event.event) {
          case 'run.started':
            if (str(data['conversationId']).isNotEmpty) {
              conversationId = str(data['conversationId']);
            }
            break;
          case 'message.delta':
            assistant['content'] =
                str(assistant['content']) + str(data['delta']);
            break;
          case 'message.reasoning.delta':
            assistant['reasoningContent'] =
                str(assistant['reasoningContent']) + str(data['delta']);
            break;
          case 'message.completed':
            assistant['content'] = data['content'] ?? assistant['content'];
            break;
          case 'run.failed':
            throw ApiException(
              str(data['message']).isEmpty ? 'AI 服务处理失败' : str(data['message']),
            );
          case 'tool.request':
            // 移动端不声明电脑工作区；若服务仍请求本地工具，返回明确失败以结束挂起。
            await app.api.post(
              '/ai-message/workspace/tool/result',
              data: {
                'toolCallId': data['toolCallId'],
                'workspaceName': data['workspaceName'],
                'userId': app.user!.id,
                'success': false,
                'error': '移动客户端不支持电脑本地工作区工具',
              },
            );
            break;
          case 'done':
            done = true;
            break;
        }
        setState(() {});
      }
      if (!done) throw ApiException('AI 连接提前结束，已保留收到的内容，可重新发送');
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = (e is DioException && CancelToken.isCancel(e))
              ? '已停止生成'
              : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => streaming = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'AI 助手',
    actions: [
      IconButton(
        tooltip: '历史会话',
        onPressed: streaming ? null : history,
        icon: const Icon(Icons.history_rounded),
      ),
      IconButton(
        tooltip: '模型设置',
        onPressed: streaming
            ? null
            : () async {
                await pushPage(context, const ModelConfigsPage());
                await load();
              },
        icon: const Icon(Icons.tune_rounded),
      ),
      IconButton(
        tooltip: '新对话',
        onPressed: streaming
            ? null
            : () => setState(() {
                messages.clear();
                conversationId = null;
                error = null;
              }),
        icon: const Icon(Icons.add_rounded),
      ),
    ],
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: PopupMenuButton<String>(
                key: const ValueKey('ai-model-selector'),
                tooltip: '选择模型',
                enabled: !streaming,
                initialValue: model == null ? 'default' : str(model!['id']),
                constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
                offset: const Offset(0, 8),
                onSelected: (id) => setState(
                  () => model = configs
                      .where((c) => str(c['id']) == id)
                      .firstOrNull,
                ),
                itemBuilder: (_) => [
                  for (final option in <Json>[
                    {'id': 'default', 'configName': '系统默认模型'},
                    ...configs,
                  ])
                    PopupMenuItem<String>(
                      value: str(option['id']),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              str(option['configName']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (str(option['id']) ==
                              (model == null
                                  ? 'default'
                                  : str(model!['id']))) ...[
                            const SizedBox(width: 14),
                            const Icon(
                              Icons.check_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
                child: GlassCard(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppColors.primary,
                        size: 17,
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          model == null ? '系统默认模型' : str(model!['configName']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.muted,
                        size: 19,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD86C7E),
                    ),
                  ),
                ),
                if (!streaming)
                  TextButton(onPressed: load, child: const Text('刷新')),
              ],
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : messages.isEmpty
              ? const EmptyState(
                  title: '你好，今天想聊点什么？',
                  description: '写作、灵感、问题，都可以交给我。',
                  icon: Icons.auto_awesome_rounded,
                )
              : ListView.builder(
                  controller: scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final item = messages[messages.length - index - 1];
                    final mine = item['role'] == 'user';
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: GlassCard(
                          padding: const EdgeInsets.all(18),
                          color: mine
                              ? AppColors.primary.withValues(alpha: .12)
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mine ? '你' : 'AI 助手',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (str(item['reasoningContent']).isNotEmpty)
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text(
                                    '思考过程',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  children: [
                                    Text(
                                      str(item['reasoningContent']),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 8),
                              MarkdownBody(
                                data: str(item['content']).isEmpty && streaming
                                    ? '正在思考…'
                                    : str(item['content']),
                                selectable: true,
                                onTapLink: (text, href, title) {
                                  if (href != null) openLink(context, href);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: '向 AI 发消息…'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                tooltip: streaming ? '停止生成' : '发送',
                onPressed: streaming ? () => cancel?.cancel() : send,
                icon: Icon(
                  streaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> history() async {
    final app = AppScope.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: conversations.isEmpty
                ? const EmptyState(title: '暂时没有历史会话')
                : ListView(
                    children: [
                      for (final item in conversations)
                        ListTile(
                          title: Text(
                            str(item['title']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(clockText(item['updatedAt'])),
                          onTap: () => Navigator.pop(context, str(item['id'])),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'rename') {
                                final name = await editText(
                                  context,
                                  title: '重命名会话',
                                  initial: str(item['title']),
                                );
                                if (name == null ||
                                    name.isEmpty ||
                                    !context.mounted) {
                                  return;
                                }
                                await runAction(context, () async {
                                  await app.api.put(
                                    '/ai-message/conversation/rename',
                                    data: {
                                      'conversationId': item['id'],
                                      'userId': app.user!.id,
                                      'title': name,
                                    },
                                  );
                                  item['title'] = name;
                                  if (context.mounted) update(() {});
                                });
                              } else {
                                if (!await confirm(
                                  context,
                                  '删除 AI 会话',
                                  '确定删除这个会话和其中的消息吗？',
                                )) {
                                  return;
                                }
                                if (!context.mounted) return;
                                await runAction(context, () async {
                                  await app.api.delete(
                                    '/ai-message/conversation/${item['id']}',
                                    query: {'userId': app.user!.id},
                                  );
                                  conversations.remove(item);
                                  if (context.mounted) update(() {});
                                  if (mounted &&
                                      conversationId == str(item['id'])) {
                                    setState(() {
                                      conversationId = null;
                                      messages.clear();
                                    });
                                  }
                                });
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('重命名'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) await openConversation(selected);
  }
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
                    onTap: () async {
                      await pushPage(context, ModelEditorPage(config: config));
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
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'active', child: Text('设为默认')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
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
                        if (entry.key != 'apiKey' ||
                            entry.value.text.trim().isNotEmpty)
                          entry.key: entry.value.text.trim(),
                      'modelTemperature':
                          widget.config?['modelTemperature'] ?? 1,
                    };
                    if (widget.config == null) {
                      await app.api.post(
                        '/ai-message/config/add_model',
                        data: data,
                      );
                    } else {
                      await app.api.put(
                        '/ai-message/config/updateModel',
                        data: data,
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
