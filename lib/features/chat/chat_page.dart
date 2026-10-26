import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/app_state.dart';
import '../../core/file_service.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../contacts/contacts_page.dart';
import '../contacts/group_pages.dart';
import '../wallet/red_packet_page.dart';
import 'message_bubble.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.conversation});
  final Conversation conversation;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final text = TextEditingController();
  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  final scroll = ScrollController();
  AppState? app;
  ChatMessage? quote;
  bool sending = false;
  bool loading = true;
  bool recording = false;
  bool recordBusy = false;
  bool olderBusy = false;
  bool emojiOpen = false;
  double? progress;
  CancelToken? upload;
  Timer? recordLimit;
  String? loadError;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (app != null) return;
    app = AppScope.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    try {
      await app!.openConversation(widget.conversation);
    } catch (e) {
      loadError = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    if (app?.activeConversation == widget.conversation.id) {
      app?.activeConversation = null;
    }
    upload?.cancel();
    recordLimit?.cancel();
    _recorder?.dispose();
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> sendText() async {
    if (sending || text.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await app!.send(widget.conversation, text.text.trim(), quote: quote);
      if (mounted) {
        text.clear();
        setState(() {
          quote = null;
          emojiOpen = false;
        });
        if (scroll.hasClients) {
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pick(FileType type) async {
    if (progress != null) return;
    await runAction(context, () async {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        withData: true,
      );
      if (result != null && mounted) await sendFile(result.files.single);
    });
  }

  Future<void> sendFile(PlatformFile file) async {
    if (!mounted) return;
    setState(() => progress = 0);
    upload = CancelToken();
    try {
      await FileService(app!).send(
        widget.conversation,
        file,
        quote: quote,
        cancelToken: upload,
        onProgress: (v) {
          if (mounted) setState(() => progress = v);
        },
      );
      if (mounted) setState(() => quote = null);
    } catch (e) {
      if (mounted && !(upload?.isCancelled ?? false)) {
        toast(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => progress = null);
    }
  }

  Future<void> toggleRecord() async {
    if (recordBusy || progress != null) return;
    setState(() => recordBusy = true);
    try {
      if (recording) {
        recordLimit?.cancel();
        final path = await recorder.stop();
        if (mounted) setState(() => recording = false);
        if (path != null && mounted) {
          final file = XFile(path);
          final bytes = await file.readAsBytes();
          await sendFile(
            PlatformFile(
              name: '语音_${DateTime.now().millisecondsSinceEpoch}.m4a',
              size: bytes.length,
              bytes: bytes,
            ),
          );
        }
      } else {
        if (!await recorder.hasPermission()) throw Exception('请在系统设置中允许使用麦克风');
        final path = kIsWeb
            ? 'voice.m4a'
            : '${(await getTemporaryDirectory()).path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        if (mounted) setState(() => recording = true);
        recordLimit = Timer(const Duration(seconds: 60), toggleRecord);
      }
    } catch (e) {
      if (mounted) toast(context, '录音失败：$e');
    } finally {
      if (mounted) setState(() => recordBusy = false);
    }
  }

  Future<void> menu(ChatMessage message) async {
    final mine = message.senderId == app!.user?.id;
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('引用'),
              onTap: () => Navigator.pop(context, 'quote'),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border_rounded),
              title: const Text('收藏'),
              onTap: () => Navigator.pop(context, 'favorite'),
            ),
            if (mine && message.type != 6 && message.status == 1)
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: const Text('撤回'),
                onTap: () => Navigator.pop(context, 'recall'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (value) {
      case 'copy':
        await Clipboard.setData(
          ClipboardData(
            text: message.type == 1 ? message.content : message.url,
          ),
        );
        break;
      case 'quote':
        setState(() => quote = message);
        break;
      case 'favorite':
        await runAction(
          context,
          () => app!.api.post(
            '/favorites/save',
            data: {
              'title': message.displayText,
              'content': message.type == 1 ? message.content : message.url,
              'sourceUsername': mine
                  ? app!.user!.name
                  : widget.conversation.name,
              'type': message.type,
            },
          ),
          success: '已加入收藏',
        );
        break;
      case 'recall':
        await runAction(
          context,
          () => app!.recall(widget.conversation, message),
        );
        break;
    }
  }

  Future<void> saveFile(ChatMessage message) async {
    await runAction(context, () async {
      if (message.url.isEmpty) throw Exception('文件还没有准备好');
      final response = await Dio().get<List<int>>(
        message.url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data!);
      final saved = await FilePicker.platform.saveFile(
        fileName: message.fileName,
        bytes: bytes,
        dialogTitle: '保存聊天文件',
      );
      if (saved != null && mounted) toast(context, '文件已保存');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c =
        state.conversations
            .where((c) => c.id == widget.conversation.id)
            .firstOrNull ??
        widget.conversation;
    final items = state.messages[c.id] ?? [];
    final members = state.members[c.id] ?? [];
    return GlassBackground(
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              UserAvatar(
                name: c.name,
                url: c.avatar,
                size: 35,
                group: c.isGroup,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      c.isGroup
                          ? '${members.length} 位成员'
                          : state.onlineUsers.contains(c.targetId)
                          ? '在线'
                          : '轻轻一句，让彼此靠近',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '聊天资料',
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () async {
                if (c.isGroup) {
                  await pushPage(context, GroupDetailPage(conversation: c));
                } else {
                  final contact = state.contacts
                      .where((f) => f.id == c.targetId)
                      .firstOrNull;
                  if (contact != null) {
                    await pushPage(context, ContactPage(contact: contact));
                  }
                }
                if (mounted) state.activeConversation = c.id;
              },
            ),
            PopupMenuButton<String>(
              tooltip: '聊天操作',
              onSelected: (value) async {
                if (value == 'search') {
                  await pushPage(context, ChatSearchPage(conversation: c));
                }
                if (!context.mounted) return;
                if (value == 'clear' &&
                    await confirm(context, '清空聊天记录', '确定清空这个会话的聊天记录吗？')) {
                  if (!context.mounted) return;
                  await runAction(context, () => state.clearHistory(c));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'search', child: Text('查找聊天记录')),
                PopupMenuItem(value: 'clear', child: Text('清空聊天记录')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (loadError != null)
              Material(
                color: Colors.white54,
                child: ListTile(
                  dense: true,
                  title: Text(loadError!, style: const TextStyle(fontSize: 12)),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() {
                        loadError = null;
                        loading = true;
                      });
                      load();
                    },
                    child: const Text('重试'),
                  ),
                ),
              ),
            Expanded(
              child: loading && items.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : items.isEmpty
                  ? const EmptyState(
                      title: '聊点什么吧',
                      description: '每一句话，都值得被认真听见。',
                    )
                  : ListView.builder(
                      controller: scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: items.length + 1,
                      itemBuilder: (context, index) {
                        if (index == items.length) {
                          return Center(
                            child: TextButton(
                              onPressed: olderBusy
                                  ? null
                                  : () async {
                                      setState(() => olderBusy = true);
                                      await runAction(context, () async {
                                        final count = await state.loadOlder(
                                          c.id,
                                        );
                                        if (count == 0 && context.mounted) {
                                          toast(context, '已加载到最早的消息');
                                        }
                                      });
                                      if (mounted) {
                                        setState(() => olderBusy = false);
                                      }
                                    },
                              child: Text(olderBusy ? '正在加载…' : '加载更早的消息'),
                            ),
                          );
                        }
                        final m = items[items.length - index - 1];
                        final mine = m.senderId == state.user?.id;
                        final member = members
                            .where((x) => str(x['userId']) == m.senderId)
                            .firstOrNull;
                        return MessageBubble(
                          key: ValueKey(m.id),
                          message: m,
                          mine: mine,
                          showName: c.isGroup,
                          name: mine
                              ? state.user?.name ?? ''
                              : str(member?['username'] ?? c.name),
                          avatar: mine
                              ? state.user?.avatar ?? ''
                              : str(member?['avatar'] ?? c.avatar),
                          onLongPress: () => menu(m),
                          onRetry: () =>
                              runAction(context, () async => state.retry(c, m)),
                          onRedPacket: () => pushPage(
                            context,
                            RedPacketDetailPage(id: str(m.data['redPacketId'])),
                          ),
                          onFile: () => saveFile(m),
                        );
                      },
                    ),
            ),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 5, 10, 5),
                child: Row(
                  children: [
                    Expanded(child: LinearProgressIndicator(value: progress)),
                    const SizedBox(width: 12),
                    Text(
                      '上传 ${(progress! * 100).round()}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                    IconButton(
                      tooltip: '取消上传',
                      onPressed: () => upload?.cancel(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            GlassCard(
              radius: 0,
              padding: EdgeInsets.zero,
              blur: 20,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (quote != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.reply_rounded,
                              size: 15,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                quote!.displayText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '取消引用',
                              onPressed: () => setState(() => quote = null),
                              icon: const Icon(Icons.close_rounded, size: 17),
                            ),
                          ],
                        ),
                      ),
                    if (recording)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.fiber_manual_record,
                              color: Colors.redAccent,
                              size: 12,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '正在录音，再点麦克风发送（最长 60 秒）',
                              style: TextStyle(fontSize: 12),
                            ),
                            TextButton(
                              onPressed: () async {
                                await recorder.cancel();
                                recordLimit?.cancel();
                                if (mounted) setState(() => recording = false);
                              },
                              child: const Text('取消'),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 14, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: recording ? '结束录音并发送' : '录制语音',
                            onPressed: recordBusy ? null : toggleRecord,
                            icon: Icon(
                              recording
                                  ? Icons.stop_circle_outlined
                                  : Icons.mic_none_rounded,
                              color: recording
                                  ? Colors.redAccent
                                  : AppColors.ink,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: text,
                              minLines: 1,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                hintText: '说点什么…',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 45,
                            height: 45,
                            child: IconButton.filled(
                              onPressed: sending ? null : sendText,
                              tooltip: '发送',
                              icon: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          tooltip: '表情',
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            setState(() => emojiOpen = !emojiOpen);
                          },
                          icon: const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            size: 23,
                          ),
                        ),
                        IconButton(
                          tooltip: '发送图片',
                          onPressed: progress == null
                              ? () => pick(FileType.image)
                              : null,
                          icon: const Icon(Icons.image_outlined, size: 23),
                        ),
                        IconButton(
                          tooltip: '发送视频',
                          onPressed: progress == null
                              ? () => pick(FileType.video)
                              : null,
                          icon: const Icon(Icons.videocam_outlined, size: 24),
                        ),
                        IconButton(
                          tooltip: '发送文件',
                          onPressed: progress == null
                              ? () => pick(FileType.any)
                              : null,
                          icon: const Icon(Icons.folder_open_rounded, size: 23),
                        ),
                        IconButton(
                          tooltip: '发红包',
                          onPressed: () => pushPage(
                            context,
                            SendRedPacketPage(conversation: c),
                          ),
                          icon: const Icon(Icons.redeem_outlined, size: 23),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: !emojiOpen
                          ? const SizedBox(width: double.infinity)
                          : SizedBox(
                              height: 170,
                              child: GridView.count(
                                crossAxisCount: 8,
                                padding: const EdgeInsets.all(12),
                                children: [
                                  for (final emoji in [
                                    '😀',
                                    '😊',
                                    '🥰',
                                    '😎',
                                    '🤔',
                                    '😭',
                                    '😂',
                                    '🥹',
                                    '👍',
                                    '👏',
                                    '🙌',
                                    '🤝',
                                    '❤️',
                                    '💕',
                                    '🎉',
                                    '✨',
                                    '🌸',
                                    '🌈',
                                    '☀️',
                                    '🌙',
                                    '🍀',
                                    '☕',
                                    '🎁',
                                    '🔥',
                                  ])
                                    InkWell(
                                      onTap: () {
                                        text.text += emoji;
                                        text.selection =
                                            TextSelection.collapsed(
                                              offset: text.text.length,
                                            );
                                      },
                                      child: Center(
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 25),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage({super.key, required this.conversation});
  final Conversation conversation;
  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = (app.messages[widget.conversation.id] ?? [])
        .where(
          (m) =>
              !m.revoked &&
              m.displayText.toLowerCase().contains(query.toLowerCase()),
        )
        .toList()
        .reversed;
    return PageScaffold(
      title: '查找聊天记录',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                hintText: '搜索已加载的聊天记录',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final message in list)
                  ListTile(
                    title: Text(message.displayText),
                    subtitle: Text(message.time),
                    onTap: () => Clipboard.setData(
                      ClipboardData(text: message.displayText),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: TextButton(
              onPressed: () => runAction(
                context,
                () => app.loadOlder(widget.conversation.id),
              ),
              child: const Text('加载更早的记录'),
            ),
          ),
        ],
      ),
    );
  }
}
