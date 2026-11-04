import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'ai_page.dart' show ModelConfigsPage;
import 'agent_call_page.dart';

String agentRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class AgentPersonPage extends StatefulWidget {
  const AgentPersonPage({super.key});
  @override
  State<AgentPersonPage> createState() => _AgentPersonPageState();
}

class _AgentPersonPageState extends State<AgentPersonPage>
    with WidgetsBindingObserver {
  final input = TextEditingController();
  final List<Json> messages = [];
  final List<Json> attachments = [];
  List<Json> configs = [];
  Json person = {};
  Json? model;
  bool loading = true, sending = false, uploading = false;
  String? error;
  Timer? timer;
  CancelToken? cancel;
  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  bool recording = false, foreground = true;
  Timer? recordLimit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      load();
      timer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!sending &&
            !loading &&
            foreground &&
            (ModalRoute.of(context)?.isCurrent ?? true)) {
          load(silent: true);
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    recordLimit?.cancel();
    _recorder?.dispose();
    timer?.cancel();
    cancel?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
  }

  Future<void> load({bool silent = false}) async {
    final app = AppScope.of(context);
    try {
      final result = await Future.wait([
        app.api.get('/ai-message/person', query: {'userId': app.user!.id}),
        app.api.get('/ai-message/loadMessage', query: {'userId': app.user!.id}),
        app.api.get(
          '/ai-message/config/getConfig',
          query: {'userId': app.user!.id},
        ),
      ]);
      if (!mounted || sending) return;
      setState(() {
        person = asJson(result[0]);
        messages
          ..clear()
          ..addAll(asList(result[1]));
        configs = asList(result[2]);
        model = configs.where((c) => flag(c['isActive'])).firstOrNull;
        if (!silent) error = null;
      });
      if (foreground && (ModalRoute.of(context)?.isCurrent ?? true)) {
        await app.api.post(
          '/ai-message/person/presence',
          data: {
            'userId': app.user!.id,
            'chatActive': true,
            'typing': input.text.isNotEmpty,
          },
        );
        if (messages.isNotEmpty && messages.last['seq'] != null) {
          await app.api.post(
            '/ai-message/person/read',
            data: {'userId': app.user!.id, 'upToSeq': messages.last['seq']},
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> attachImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    await uploadMedia(file!.bytes!, file.name);
  }

  Future<void> uploadMedia(Uint8List bytes, String name) async {
    final app = AppScope.of(context);
    if (bytes.length > 20 * 1024 * 1024) {
      toast(context, '媒体不能超过 20 MB');
      return;
    }
    setState(() => uploading = true);
    try {
      final asset = asJson(
        await app.api.post(
          '/ai-message/media',
          data: FormData.fromMap({
            'userId': app.user!.id,
            'file': MultipartFile.fromBytes(bytes, filename: name),
          }),
        ),
      );
      if (mounted) setState(() => attachments.add(asset));
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> toggleVoice() async {
    try {
      if (recording) {
        recordLimit?.cancel();
        final path = await recorder.stop();
        if (mounted) setState(() => recording = false);
        if (path != null && mounted) {
          final file = File(path);
          await uploadMedia(await file.readAsBytes(), 'voice.wav');
          await file.delete();
        }
      } else {
        if (!await recorder.hasPermission()) {
          if (mounted) toast(context, '请允许使用麦克风');
          return;
        }
        final directory = await getTemporaryDirectory();
        await recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            echoCancel: true,
            noiseSuppress: true,
          ),
          path: '${directory.path}/agent_voice_${agentRequestId()}.wav',
        );
        if (mounted) setState(() => recording = true);
        recordLimit = Timer(const Duration(seconds: 60), () {
          if (recording && mounted) toggleVoice();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => recording = false);
        toast(context, e.toString());
      }
    }
  }

  Future<void> send() async {
    if (sending ||
        uploading ||
        recording ||
        flag(person['requiresCreation']) ||
        (input.text.trim().isEmpty && attachments.isEmpty)) {
      return;
    }
    final app = AppScope.of(context);
    final content = input.text.trim().isEmpty
        ? (attachments.any((a) => a['kind'] == 'audio') ? '[语音]' : '[图片]')
        : input.text.trim();
    final id = agentRequestId(), media = List<Json>.from(attachments);
    final user = <String, dynamic>{
      'id': id,
      'role': 'user',
      'content': content,
      'parts': {
        'parts': media
            .map((m) => {'type': m['kind'], 'assetId': m['id']})
            .toList(),
      },
    };
    input.clear();
    attachments.clear();
    setState(() {
      sending = true;
      error = null;
      messages.add(user);
    });
    cancel = CancelToken();
    var accepted = false, done = false;
    try {
      await for (final event in app.api.stream('/ai-message/sendMessage', {
        'id': id,
        'userId': app.user!.id,
        'content': content,
        'assetIds': media.map((m) => m['id']).toList(),
        'config': model == null
            ? {'providerName': 'default'}
            : {'configId': model!['id']},
      }, cancel!)) {
        if (!mounted) return;
        if (![
          'run.started',
          'message.completed',
          'run.failed',
          'run.interrupted',
          'done',
        ].contains(event.event)) {
          continue;
        }
        final data = asJson(jsonDecode(event.data));
        switch (event.event) {
          case 'run.started':
            accepted = true;
          case 'message.completed':
            final existing = messages
                .where((m) => m['id'] == data['messageId'])
                .firstOrNull;
            if (existing == null) {
              messages.add({
                'id': data['messageId'],
                'role': 'assistant',
                'content': data['content'],
                'parts': data['parts'],
              });
            }
          case 'run.failed':
            throw StateError(str(data['message']));
          case 'run.interrupted':
            break;
          case 'done':
            done = true;
        }
        setState(() {});
      }
      if (!done) throw StateError('连接已中断，已发送的内容仍保留');
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          if (!accepted && input.text.isEmpty) input.text = content;
        });
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
        await load(silent: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: str(person['name']).isEmpty ? '你的 AI 伙伴' : str(person['name']),
    actions: [
      IconButton(
        tooltip: '语音通话',
        icon: const Icon(Icons.call_outlined),
        onPressed: flag(person['exists']) && !flag(person['requiresCreation'])
            ? () => pushPage(context, AgentCallPage(name: str(person['name'])))
            : null,
      ),
      IconButton(
        tooltip: '朋友圈',
        icon: const Icon(Icons.photo_library_outlined),
        onPressed: () => pushPage(context, const AgentMomentsPage()),
      ),
      IconButton(
        tooltip: '模型与生活设置',
        icon: const Icon(Icons.tune_rounded),
        onPressed: () async {
          await pushPage(context, const ModelConfigsPage());
          await load();
        },
      ),
    ],
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: PopupMenuButton<String>(
                key: const ValueKey('ai-model-selector'),
                tooltip: '选择聊天模型',
                enabled: !sending,
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
                onSelected: (id) async {
                  final app = AppScope.of(context);
                  try {
                    await app.api.put(
                      '/ai-message/config/switchModel',
                      data: {
                        'userId': app.user!.id,
                        'configId': id == 'default' ? null : id,
                      },
                    );
                    if (mounted) {
                      setState(
                        () => model = configs
                            .where((c) => str(c['id']) == id)
                            .firstOrNull,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) toast(context, e.toString());
                  }
                },
                itemBuilder: (_) => [
                  for (final option in <Json>[
                    {'id': 'default', 'configName': '系统默认模型'},
                    ...configs,
                  ])
                    PopupMenuItem<String>(
                      value: str(option['id']),
                      child: Text(
                        str(option['configName']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite_outline_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          model == null ? '系统默认模型' : str(model!['configName']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : !flag(person['exists']) || flag(person['requiresCreation'])
              ? AgentCreation(onCreated: load, configId: model?['id'])
              : messages.isEmpty
              ? const EmptyState(
                  title: '从一句你好开始',
                  description: '聊聊今天，慢慢了解彼此。',
                  icon: Icons.favorite_outline_rounded,
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final item = messages[messages.length - index - 1];
                    final mine = item['role'] == 'user';
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GlassCard(
                          padding: const EdgeInsets.all(16),
                          color: mine
                              ? AppColors.primary.withValues(alpha: .12)
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mine ? '你' : str(person['name']),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(str(item['content'])),
                              for (final part in asList(
                                asJson(item['parts'])['parts'],
                              ))
                                if (str(part['assetId']).isNotEmpty)
                                  AgentMobileMedia(
                                    id: str(part['assetId']),
                                    kind: str(part['type']),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (attachments.isNotEmpty)
          Wrap(
            children: [
              for (final a in attachments)
                InputChip(
                  label: Text(a['kind'] == 'audio' ? '语音' : '图片'),
                  onDeleted: () => setState(() => attachments.remove(a)),
                ),
            ],
          ),
        if (sending || uploading)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              uploading ? '正在看图片…' : '正在交流…',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        if (flag(person['exists']) && !flag(person['requiresCreation']))
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  onPressed: flag(person['exists']) && !uploading
                      ? attachImage
                      : null,
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton(
                  onPressed: uploading ? null : toggleVoice,
                  icon: Icon(
                    recording
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                  ),
                  tooltip: recording ? '结束录音' : '录制短语音',
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(hintText: '想说的话，慢慢说…'),
                  ),
                ),
                IconButton.filled(
                  onPressed: sending ? null : send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class AgentCreation extends StatefulWidget {
  const AgentCreation({super.key, required this.onCreated, this.configId});
  final Future<void> Function() onCreated;
  final String? configId;
  @override
  State<AgentCreation> createState() => _AgentCreationState();
}

class _AgentCreationState extends State<AgentCreation> {
  final wish = TextEditingController();
  List<Json> candidates = [];
  bool busy = false;
  @override
  void dispose() {
    wish.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text('你希望遇见怎样的人？', style: TextStyle(fontSize: 24)),
      const SizedBox(height: 16),
      TextField(
        controller: wish,
        maxLines: 4,
        maxLength: 3000,
        decoration: const InputDecoration(hintText: '简单说说想法，其余的留给相处。'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                final app = AppScope.of(context);
                setState(() => busy = true);
                try {
                  final result = asJson(
                    await app.api.post(
                      '/ai-message/person/candidates',
                      data: {
                        'userId': app.user!.id,
                        'wish': wish.text,
                        'config': {'configId': widget.configId},
                      },
                    ),
                  );
                  if (mounted) {
                    setState(() => candidates = asList(result['candidates']));
                  }
                } catch (e) {
                  if (context.mounted) toast(context, e.toString());
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(
          busy
              ? '正在遇见…'
              : candidates.isEmpty
              ? '看看会遇见谁'
              : '重新生成整组人物',
        ),
      ),
      for (final c in candidates)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(str(c['name']), style: const TextStyle(fontSize: 20)),
                Text(str(c['introduction'])),
                const SizedBox(height: 8),
                Text(
                  str(c['appearance']),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final app = AppScope.of(context);
                          setState(() => busy = true);
                          try {
                            await app.api.post(
                              '/ai-message/person/select',
                              data: {
                                'userId': app.user!.id,
                                'candidateId': c['id'],
                              },
                            );
                            await widget.onCreated();
                          } catch (e) {
                            if (context.mounted) toast(context, e.toString());
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: const Text('从一句你好开始'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class AgentMomentsPage extends StatelessWidget {
  const AgentMomentsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '伙伴的朋友圈',
      child: Loadable(
        load: () => app.api.get(
          '/ai-message/person/moments',
          query: {'userId': app.user!.id},
        ),
        builder: (context, data, reload) {
          final items = asList(data);
          if (items.isEmpty) {
            return const EmptyState(
              title: '还没有分享给你的生活片段',
              description: '生活在继续，分享的时机由它自己选择。',
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            str(item['name']),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          for (final part in asList(
                            asJson(item['parts'])['parts'],
                          ))
                            if (part['type'] == 'text')
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(str(part['text'])),
                              )
                            else
                              AgentMobileMedia(
                                id: str(part['assetId']),
                                kind: str(part['type']),
                              ),
                          for (final i in asList(item['interactions']))
                            Text(
                              '${i['name']}：${i['kind'] == 'like' ? '♥' : i['content']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => runAction(context, () async {
                                  await app.api.post(
                                    '/ai-message/person/moments/${item['id']}/interactions',
                                    data: {
                                      'userId': app.user!.id,
                                      'requestId': agentRequestId(),
                                      'kind': 'like',
                                      'active': !flag(item['liked']),
                                    },
                                  );
                                  await reload();
                                }),
                                child: Text(
                                  flag(item['liked']) ? '♥ 已点赞' : '♡ 点赞',
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final text = await editText(
                                    context,
                                    title: '评论',
                                  );
                                  if (text == null ||
                                      text.trim().isEmpty ||
                                      !context.mounted) {
                                    return;
                                  }
                                  await runAction(context, () async {
                                    await app.api.post(
                                      '/ai-message/person/moments/${item['id']}/interactions',
                                      data: {
                                        'userId': app.user!.id,
                                        'requestId': agentRequestId(),
                                        'kind': 'comment',
                                        'content': text,
                                      },
                                    );
                                    await reload();
                                  });
                                },
                                child: const Text('评论'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class AgentMobileMedia extends StatefulWidget {
  const AgentMobileMedia({super.key, required this.id, required this.kind});
  final String id, kind;
  @override
  State<AgentMobileMedia> createState() => _AgentMobileMediaState();
}

class _AgentMobileMediaState extends State<AgentMobileMedia> {
  Future<Uint8List>? bytes;
  AudioPlayer? _player;
  AudioPlayer get player => _player ??= AudioPlayer();
  File? cached;
  bool playing = false;
  @override
  void dispose() {
    (_player?.dispose() ?? Future<void>.value()).then((_) async {
      if (cached != null && await cached!.exists()) await cached!.delete();
    });
    super.dispose();
  }

  Future<void> play() async {
    if (playing) {
      await player.stop();
      if (mounted) setState(() => playing = false);
      return;
    }
    try {
      final blob = await bytes!;
      final root = await getTemporaryDirectory();
      final safe = widget.id.replaceAll(RegExp('[^a-zA-Z0-9-]'), '');
      final ext =
          blob.length > 12 && String.fromCharCodes(blob.take(4)) == 'RIFF'
          ? 'wav'
          : 'webm';
      cached = File('${root.path}/agent_audio_$safe.$ext');
      await cached!.writeAsBytes(blob);
      await player.setFilePath(cached!.path);
      if (mounted) setState(() => playing = true);
      await player.play();
      if (mounted) setState(() => playing = false);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    bytes ??= load();
  }

  Future<Uint8List> load() async {
    final app = AppScope.of(context);
    final response = await app.api.response(
      'GET',
      '/ai-message/media/${widget.id}',
      query: {'userId': app.user!.id},
      type: ResponseType.bytes,
    );
    app.api.unwrap(response);
    return Uint8List.fromList(List<int>.from(response.data));
  }

  @override
  Widget build(BuildContext context) => widget.kind == 'image'
      ? FutureBuilder<Uint8List>(
          future: bytes,
          builder: (context, snapshot) => snapshot.hasData
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Image.memory(
                    snapshot.data!,
                    width: 240,
                    fit: BoxFit.contain,
                  ),
                )
              : Text(snapshot.hasError ? '图片暂时无法加载' : '正在加载图片…'),
        )
      : TextButton.icon(
          onPressed: play,
          icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
          label: Text(playing ? '停止播放' : '播放语音'),
        );
}
