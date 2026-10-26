import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../chat/chat_page.dart';
import '../auth/login_page.dart' show avatarMime;

/// 后端建群和处理邀请都要求 multipart 头像；未选图片时生成小尺寸默认头像。
Future<Uint8List> groupAvatarBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 96, 96),
    Paint()..color = AppColors.primary,
  );
  canvas.drawCircle(const Offset(36, 33), 12, Paint()..color = Colors.white);
  canvas.drawCircle(
    const Offset(62, 36),
    10,
    Paint()..color = Colors.white.withValues(alpha: .65),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(17, 50, 41, 30),
      const Radius.circular(16),
    ),
    Paint()..color = Colors.white,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(52, 53, 27, 26),
      const Radius.circular(12),
    ),
    Paint()..color = Colors.white.withValues(alpha: .65),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 96);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<void> dealGroupInvitation(AppState app, Json item, bool accept) async {
  Uint8List bytes;
  final url = str(item['userAvatar']);
  if (url.isNotEmpty) {
    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    bytes = Uint8List.fromList(response.data!);
  } else {
    bytes = await groupAvatarBytes();
  }
  await app.api.post(
    '/apply/groupApply/deal',
    data: FormData.fromMap({
      'conversationId': item['conversationId'],
      'userId': item['userId'],
      'memberId': app.user!.id,
      'status': accept ? 2 : 3,
      'userAvatar': url,
      'groupAvatarBlob': MultipartFile.fromBytes(
        bytes,
        filename: 'group.png',
        contentType: DioMediaType.parse('image/png'),
      ),
    }),
  );
  if (accept && app.socket.state.name == 'online') {
    await app.loadMembers(str(item['conversationId']));
    app.socket.send(17, {
      'conversationId': item['conversationId'],
      'userId': app.user!.id,
      'username': app.user!.name,
      'avatar': app.user!.avatar,
      'role': 0,
      'receiverIds': (app.members[str(item['conversationId'])] ?? [])
          .map((m) => str(m['userId']))
          .where((id) => id != app.user!.id)
          .toList(),
    });
  }
}

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});
  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final name = TextEditingController();
  final selected = <String>{};
  PlatformFile? avatar;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (busy) return;
    if (name.text.trim().isEmpty || selected.isEmpty) {
      toast(context, '填写群名称，并至少邀请一位好友');
      return;
    }
    final app = AppScope.of(context);
    setState(() => busy = true);
    try {
      final bytes = avatar?.bytes ?? await groupAvatarBytes();
      final form = FormData.fromMap({
        'groupName': name.text.trim(),
        'userId': app.user!.id,
        'groupAvatar': MultipartFile.fromBytes(
          bytes,
          filename: avatar?.name ?? 'group.png',
          contentType: DioMediaType.parse(
            avatar == null ? 'image/png' : avatarMime(avatar!.name),
          ),
        ),
      });
      for (final id in selected) {
        form.fields.add(MapEntry('invitedIds', id));
      }
      final group = asJson(
        await app.api.post('/conversation/createGroup', data: form),
      );
      if (app.socket.state.name == 'online') {
        app.socket.send(7, {
          'conversationId': group['id'],
          'userAvatar': group['avatar'],
          'groupName': group['name'],
          'invitedIds': jsonEncode(selected.toList()),
        });
      }
      await app.sync();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(conversation: Conversation(group)),
        ),
      );
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '发起群聊',
      bottom: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: FilledButton(
          onPressed: busy ? null : create,
          child: Text(busy ? '正在创建…' : '创建群聊 · 已选 ${selected.length} 人'),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          GlassCard(
            child: Row(
              children: [
                InkWell(
                  onTap: () => runAction(context, () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                      withData: true,
                    );
                    if (result != null && mounted) {
                      if (result.files.single.size > 5 * 1024 * 1024) {
                        throw Exception('头像请控制在 5 MB 以内');
                      }
                      setState(() => avatar = result.files.single);
                    }
                  }),
                  child: avatar?.bytes == null
                      ? const UserAvatar(name: '群', group: true, size: 56)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.memory(
                            avatar!.bytes!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: name,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      hintText: '给群聊取个名字',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('邀请好友'),
          if (app.contacts.isEmpty)
            const EmptyState(
              title: '先添加几位好友吧',
              icon: Icons.people_outline_rounded,
            ),
          for (final friend in app.contacts.where((c) => c.status < 2))
            CheckboxListTile(
              value: selected.contains(friend.id),
              onChanged: (v) => setState(() {
                v! ? selected.add(friend.id) : selected.remove(friend.id);
              }),
              title: Text(friend.name),
              secondary: UserAvatar(
                name: friend.name,
                url: friend.avatar,
                size: 42,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
        ],
      ),
    );
  }
}

class GroupDetailPage extends StatelessWidget {
  const GroupDetailPage({super.key, required this.conversation});
  final Conversation conversation;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '群聊资料',
      child: Loadable(
        load: () async {
          await app.loadMembers(conversation.id);
          return app.api.get('/conversation/groupDetail/${conversation.id}');
        },
        builder: (context, result, reload) {
          final group = asJson(result);
          final members = app.members[conversation.id] ?? [];
          final mine = members.where((m) => str(m['userId']) == app.user?.id);
          final role = mine.isEmpty ? 0 : number(mine.first['role']);
          final owner = str(group['ownerId']) == app.user?.id;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: UserAvatar(
                  name: conversation.name,
                  url: conversation.avatar,
                  size: 82,
                  group: true,
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  str(group['groupName']),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: SelectableText(
                  conversation.id,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 22),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('群名称'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      subtitle: Text(str(group['groupName'])),
                      onTap: role < 1
                          ? null
                          : () async {
                              final value = await editText(
                                context,
                                title: '修改群名称',
                                initial: str(group['groupName']),
                              );
                              if (value == null ||
                                  value.isEmpty ||
                                  !context.mounted) {
                                return;
                              }
                              await runAction(context, () async {
                                await app.api.post(
                                  '/conversation/updateGroupInfo',
                                  query: {
                                    'conversationId': conversation.id,
                                    'groupName': value,
                                  },
                                );
                                conversation.data['name'] = value;
                                await app.sync();
                                await reload();
                              });
                            },
                    ),
                    ListTile(
                      title: const Text('群介绍'),
                      subtitle: Text(
                        str(group['groupDesc']).isEmpty
                            ? '记录属于你们的小世界'
                            : str(group['groupDesc']),
                      ),
                      trailing: role > 0
                          ? const Icon(Icons.edit_outlined, size: 18)
                          : null,
                      onTap: role < 1
                          ? null
                          : () async {
                              final value = await editText(
                                context,
                                title: '群介绍',
                                initial: str(group['groupDesc']),
                                multiline: true,
                              );
                              if (value == null || !context.mounted) return;
                              await runAction(context, () async {
                                await app.api.post(
                                  '/conversation/updateGroupInfo',
                                  query: {
                                    'conversationId': conversation.id,
                                    'groupDesc': value,
                                  },
                                );
                                await reload();
                              });
                            },
                    ),
                    SwitchListTile(
                      title: const Text('置顶聊天'),
                      value: conversation.pinned,
                      onChanged: (v) => runAction(
                        context,
                        () => app.setConversationFlag(conversation, 'isTop', v),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('消息免打扰'),
                      value: conversation.muted,
                      onChanged: (v) => runAction(
                        context,
                        () =>
                            app.setConversationFlag(conversation, 'isMute', v),
                      ),
                    ),
                  ],
                ),
              ),
              SectionLabel(
                '群成员 · ${members.length}',
                trailing: TextButton.icon(
                  onPressed: () async {
                    final ids = await chooseContacts(
                      context,
                      exclude: members.map((m) => str(m['userId'])).toSet(),
                    );
                    if (ids == null || ids.isEmpty || !context.mounted) return;
                    await runAction(context, () async {
                      await app.api.post(
                        '/conversation/batchInvite',
                        query: {'conversationId': conversation.id},
                        data: ids,
                      );
                      await reload();
                    });
                  },
                  icon: const Icon(Icons.person_add_alt_rounded, size: 17),
                  label: const Text('邀请'),
                ),
              ),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  children: [
                    for (final member in members)
                      ListTile(
                        leading: UserAvatar(
                          name: str(member['username']),
                          url: str(member['avatar']),
                          size: 40,
                        ),
                        title: Text(str(member['username'])),
                        subtitle: Text(
                          number(member['role']) == 2
                              ? '群主'
                              : number(member['role']) == 1
                              ? '管理员'
                              : '群成员',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                        trailing: flag(member['isMute'])
                            ? const Icon(Icons.mic_off_outlined, size: 16)
                            : null,
                        onTap:
                            role < 1 ||
                                str(member['userId']) == app.user?.id ||
                                number(member['role']) == 2
                            ? null
                            : () =>
                                  manageMember(context, member, owner, reload),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () async {
                  if (!await confirm(
                    context,
                    owner ? '解散群聊' : '退出群聊',
                    owner ? '解散后所有成员都将离开群聊。' : '确定离开这个群聊吗？',
                  )) {
                    return;
                  }
                  if (!context.mounted) return;
                  await runAction(context, () async {
                    await app.api.delete(
                      owner
                          ? '/conversation/dissolveGroup'
                          : '/conversation/exitGroup',
                      query: {'conversationId': conversation.id},
                    );
                    await app.sync();
                    if (context.mounted) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  });
                },
                child: Text(
                  owner ? '解散群聊' : '退出群聊',
                  style: const TextStyle(color: Color(0xFFD86C7E)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> manageMember(
    BuildContext context,
    Json member,
    bool owner,
    Future<void> Function() reload,
  ) async {
    final app = AppScope.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (owner)
              ListTile(
                title: Text(number(member['role']) == 1 ? '取消管理员' : '设为管理员'),
                onTap: () => Navigator.pop(context, 'admin'),
              ),
            ListTile(
              title: Text(flag(member['isMute']) ? '解除禁言' : '禁言成员'),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
            if (owner)
              ListTile(
                title: const Text('转让群主'),
                onTap: () => Navigator.pop(context, 'owner'),
              ),
            ListTile(
              title: const Text('移出群聊'),
              onTap: () => Navigator.pop(context, 'kick'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if ((action == 'owner' || action == 'kick') &&
        !await confirm(
          context,
          action == 'owner' ? '转让群主' : '移出群聊',
          '确定对 ${member['username']} 执行此操作吗？',
        )) {
      return;
    }
    if (!context.mounted) return;
    await runAction(context, () async {
      final query = <String, dynamic>{
        'conversationId': conversation.id,
        'targetUserId': member['userId'],
      };
      switch (action) {
        case 'admin':
          await app.api.post(
            '/conversation/setAdmin',
            query: {...query, 'role': number(member['role']) == 1 ? 0 : 1},
          );
          break;
        case 'mute':
          await app.api.post(
            '/conversation/muteMember',
            query: {...query, 'isMute': flag(member['isMute']) ? 0 : 1},
          );
          break;
        case 'owner':
          await app.api.post(
            '/conversation/transferOwner',
            query: {
              'conversationId': conversation.id,
              'newOwnerId': member['userId'],
            },
          );
          break;
        case 'kick':
          await app.api.delete('/conversation/kickMember', query: query);
          break;
      }
      await reload();
    });
  }
}

Future<List<String>?> chooseContacts(
  BuildContext context, {
  Set<String> exclude = const {},
}) async {
  final contacts = AppScope.of(context).contacts
      .where((c) => !exclude.contains(c.id) && c.status < 2)
      .toList();
  final selected = <String>{};
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              const Text(
                '选择好友',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Expanded(
                child: contacts.isEmpty
                    ? const EmptyState(title: '没有可邀请的好友')
                    : ListView(
                        children: [
                          for (final c in contacts)
                            CheckboxListTile(
                              value: selected.contains(c.id),
                              onChanged: (v) => update(() {
                                v! ? selected.add(c.id) : selected.remove(c.id);
                              }),
                              title: Text(c.name),
                              secondary: UserAvatar(
                                name: c.name,
                                url: c.avatar,
                                size: 40,
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, selected.toList()),
                    child: Text('邀请 ${selected.length} 位好友'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
