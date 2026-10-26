import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../chat/chat_page.dart';
import 'group_pages.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  String query = '';
  bool groups = false;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final friends =
        app.contacts
            .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final chats = app.conversations
        .where(
          (c) =>
              c.isGroup && c.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: app.sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 125),
        children: [
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hintText: '搜索好友和群聊',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 22),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                ListTile(
                  leading: _icon(
                    Icons.person_add_alt_1_rounded,
                    AppColors.primary,
                  ),
                  title: const Text('新的朋友'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => pushPage(context, const ApplicationsPage()),
                ),
                const Divider(indent: 70, endIndent: 18),
                ListTile(
                  leading: _icon(
                    Icons.mark_chat_unread_outlined,
                    AppColors.mint,
                  ),
                  title: const Text('群聊邀请'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      pushPage(context, const ApplicationsPage(groups: true)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => groups = false),
                child: Text(
                  '好友  ${app.contacts.length}',
                  style: TextStyle(
                    color: groups ? AppColors.muted : AppColors.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => groups = true),
                child: Text(
                  '群聊  ${app.conversations.where((c) => c.isGroup).length}',
                  style: TextStyle(
                    color: groups ? AppColors.primary : AppColors.muted,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: groups ? '发起群聊' : '添加好友',
                onPressed: () => pushPage(
                  context,
                  groups ? const CreateGroupPage() : const FindFriendPage(),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (!groups && friends.isEmpty || groups && chats.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 35),
              child: EmptyState(
                title: '这里等着新的相遇',
                description: '添加好友，分享你的日常',
                icon: Icons.people_outline_rounded,
              ),
            ),
          if (!groups)
            for (final friend in friends)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 7,
                ),
                leading: UserAvatar(
                  name: friend.name,
                  url: friend.avatar,
                  size: 46,
                  online: app.onlineUsers.contains(friend.id),
                ),
                title: Text(friend.name),
                subtitle: Text(
                  friend.status >= 2
                      ? '已加入黑名单'
                      : app.onlineUsers.contains(friend.id)
                      ? '在线'
                      : '离线',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                onTap: () => pushPage(context, ContactPage(contact: friend)),
              ),
          if (groups)
            for (final chat in chats)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 7,
                ),
                leading: UserAvatar(
                  name: chat.name,
                  url: chat.avatar,
                  size: 46,
                  group: true,
                ),
                title: Text(chat.name),
                subtitle: Text(
                  chat.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => pushPage(context, ChatPage(conversation: chat)),
              ),
        ],
      ),
    );
  }

  Widget _icon(IconData icon, Color color) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: color, size: 23),
  );
}

class ContactPage extends StatelessWidget {
  const ContactPage({super.key, required this.contact});
  final Contact contact;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '好友资料',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          Center(
            child: UserAvatar(
              name: contact.name,
              url: contact.avatar,
              size: 94,
              online: app.onlineUsers.contains(contact.id),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(
              contact.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: SelectableText(
              '账号  ${contact.data['account'] ?? ''}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 30),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('备注'),
                  subtitle: Text(
                    str(contact.data['remark']).isEmpty
                        ? '设置一个专属称呼'
                        : str(contact.data['remark']),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 19),
                  onTap: () async {
                    final value = await editText(
                      context,
                      title: '修改备注',
                      initial: str(contact.data['remark']),
                    );
                    if (value == null || !context.mounted) return;
                    await runAction(context, () async {
                      await app.api.put(
                        '/friend/remark',
                        data: {},
                        query: {'friendId': contact.id, 'remark': value},
                      );
                      contact.data['remark'] = value;
                      await app.sync();
                    });
                  },
                ),
                ListTile(
                  title: const Text('手机号'),
                  trailing: Text(
                    str(contact.data['phone']),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                ListTile(
                  title: const Text('地区'),
                  trailing: Text(
                    str(contact.data['address']),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                SwitchListTile(
                  title: const Text('加入黑名单'),
                  value: contact.status == 2,
                  onChanged: (value) => runAction(context, () async {
                    await app.api.put(
                      '/friend/status',
                      data: {},
                      query: {
                        'friendId': contact.id,
                        'relationStatus': value ? 2 : 1,
                      },
                    );
                    contact.data['relationStatus'] = value ? 2 : 1;
                    await app.sync();
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('发消息'),
            onPressed: () => runAction(context, () async {
              final conversation = await app.conversationFor(contact);
              if (context.mounted) {
                await pushPage(context, ChatPage(conversation: conversation));
              }
            }),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              if (!await confirm(context, '删除好友', '确定删除 ${contact.name} 吗？')) {
                return;
              }
              if (!context.mounted) return;
              await runAction(context, () async {
                await app.api.delete(
                  '/friend/delete',
                  query: {'friendId': contact.id},
                );
                await app.sync();
                if (context.mounted) Navigator.pop(context);
              });
            },
            child: const Text(
              '删除好友',
              style: TextStyle(color: Color(0xFFD86C7E)),
            ),
          ),
        ],
      ),
    );
  }
}

class FindFriendPage extends StatefulWidget {
  const FindFriendPage({super.key});
  @override
  State<FindFriendPage> createState() => _FindFriendPageState();
}

class _FindFriendPageState extends State<FindFriendPage> {
  final search = TextEditingController();
  Json? found;
  bool busy = false;
  bool searched = false;
  bool sent = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> find() async {
    if (busy || search.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final data = await AppScope.of(context).api
          .get('/user/search', query: {'number': search.text.trim()});
      if (mounted) {
        setState(() {
          found = data == null ? null : asJson(data);
          searched = true;
          sent = false;
        });
      }
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
      title: '添加好友',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => find(),
            decoration: InputDecoration(
              hintText: '输入账号或手机号',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: '搜索',
                onPressed: busy ? null : find,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (busy)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (found != null)
            GlassCard(
              child: Column(
                children: [
                  UserAvatar(
                    name: str(found!['username']),
                    url: str(found!['avatar']),
                    size: 80,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    str(found!['username']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '账号  ${found!['account']}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  if (str(found!['id']) == app.user?.id)
                    const Text('这是你自己呀')
                  else if (flag(found!['isFriend']))
                    const Text(
                      '你们已经是好友了',
                      style: TextStyle(color: AppColors.mint),
                    )
                  else
                    FilledButton.icon(
                      onPressed: sent
                          ? null
                          : () async {
                              final message = await editText(
                                context,
                                title: '打个招呼',
                                initial: '你好，我是${app.user!.name}',
                              );
                              if (message == null || !context.mounted) return;
                              await runAction(context, () async {
                                final body = <String, dynamic>{
                                  'fromUserId': app.user!.id,
                                  'toUserId': found!['id'],
                                  'applyMsg': message,
                                };
                                final id = await app.api.post(
                                  '/apply/send',
                                  data: body,
                                );
                                if (app.socket.state.name == 'online') {
                                  app.socket.send(5, {...body, 'applyId': id});
                                }
                                if (mounted) setState(() => sent = true);
                              }, success: '好友申请已发送');
                            },
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: Text(sent ? '申请已发送' : '添加为好友'),
                    ),
                ],
              ),
            )
          else
            EmptyState(
              title: searched ? '没有找到这个用户' : '遇见你的下一位好友',
              description: '通过账号或手机号找到对方',
              icon: Icons.person_search_outlined,
            ),
        ],
      ),
    );
  }
}

class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key, this.groups = false});
  final bool groups;
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  final Set<String> busy = {};
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: widget.groups ? '群聊邀请' : '新的朋友',
      child: Loadable(
        load: () => app.api.get(
          widget.groups ? '/apply/groupApplyList' : '/apply/list',
        ),
        builder: (context, result, reload) {
          final list = asList(result);
          if (list.isEmpty) {
            return const EmptyState(
              title: '暂时没有新的申请',
              icon: Icons.mark_email_read_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: list.length,
              separatorBuilder: (_, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final item = list[index];
                final key = str(item['applyId'] ?? item['conversationId']);
                final processed = widget.groups
                    ? number(item['status']) != 1
                    : flag(item['isDealt']);
                return GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(
                            name: str(item['username'] ?? item['groupName']),
                            url: str(item['avatar'] ?? item['userAvatar']),
                            group: widget.groups,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  str(item['username'] ?? item['groupName']),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.groups
                                      ? '邀请你加入群聊'
                                      : str(item['applyMsg']),
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (processed)
                        Text(
                          widget.groups
                              ? number(item['status']) == 2
                                    ? '已加入'
                                    : '已拒绝'
                              : number(item['dealResult']) == 1
                              ? '已通过'
                              : '已拒绝',
                          style: const TextStyle(color: AppColors.muted),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: busy.contains(key)
                                  ? null
                                  : () => deal(item, false, reload),
                              child: const Text('拒绝'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: busy.contains(key)
                                  ? null
                                  : () => deal(item, true, reload),
                              child: Text(
                                busy.contains(key)
                                    ? '处理中…'
                                    : widget.groups
                                    ? '加入群聊'
                                    : '通过',
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> deal(
    Json item,
    bool accept,
    Future<void> Function() reload,
  ) async {
    final app = AppScope.of(context);
    final key = str(item['applyId'] ?? item['conversationId']);
    setState(() => busy.add(key));
    await runAction(context, () async {
      if (widget.groups) {
        await dealGroupInvitation(app, item, accept);
      } else {
        final result = asJson(
          await app.api.post(
            '/apply/deal',
            data: {
              'applyId': item['applyId'],
              'dealResult': accept ? 1 : 0,
              'fromUserId': item['fromUserId'],
            },
          ),
        );
        if (app.socket.state.name == 'online') {
          app.socket.send(14, {
            ...app.user!.data,
            'userId': item['fromUserId'],
            'friendId': app.user!.id,
            'dealResult': accept ? 1 : 0,
            'conversationId': result['conversationId'],
          });
        }
      }
      await app.sync();
      await reload();
    });
    if (mounted) setState(() => busy.remove(key));
  }
}
