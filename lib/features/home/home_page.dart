import 'package:material_ui/material_ui.dart';

import '../../core/im_socket.dart' as im;
import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../chat/chat_page.dart';
import '../contacts/contacts_page.dart';
import '../contacts/group_pages.dart';
import '../moments/moments_page.dart';
import '../profile/profile_page.dart';
import '../ai/ai_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final user = app.user;
    if (user == null) return const SizedBox.shrink();
    final titles = ['消息', '联系人', '动态', '我的'];
    final online = app.socket.state == im.ConnectionState.online;
    return GlassBackground(
      child: Scaffold(
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 17, 18, 18),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => setState(() => tab = 3),
                          borderRadius: BorderRadius.circular(18),
                          child: UserAvatar(
                            name: user.name,
                            url: user.avatar,
                            size: 44,
                            online: online,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titles[tab],
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                online ? '连接每一份在意' : '正在连接，稍等一下…',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (tab == 0)
                          IconButton(
                            tooltip: 'AI 助手',
                            onPressed: () => pushPage(context, const AiPage()),
                            icon: const Icon(
                              Icons.auto_awesome_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: '更多操作',
                          offset: const Offset(0, 8),
                          constraints: const BoxConstraints(
                            minWidth: 188,
                            maxWidth: 230,
                          ),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          onSelected: (value) {
                            if (value == 'add') {
                              pushPage(context, const FindFriendPage());
                            }
                            if (value == 'group') {
                              pushPage(context, const CreateGroupPage());
                            }
                            if (value == 'refresh') {
                              runAction(context, app.sync);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'add',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_add_alt_rounded,
                                    size: 19,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 12),
                                  Text('添加好友'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'group',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.group_add_outlined,
                                    size: 19,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 12),
                                  Text('发起群聊'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'refresh',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.sync_rounded,
                                    size: 19,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 12),
                                  Text('同步数据'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: switch (tab) {
                        0 => const ConversationList(key: ValueKey('messages')),
                        1 => const ContactsPage(key: ValueKey('contacts')),
                        2 => const MomentsPage(key: ValueKey('moments')),
                        _ => const ProfilePage(key: ValueKey('profile')),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: GlassCard(
                radius: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                blur: 22,
                child: Row(
                  children: List.generate(4, (index) {
                    final selected = index == tab;
                    final icons = [
                      Icons.chat_bubble_outline_rounded,
                      Icons.people_outline_rounded,
                      Icons.explore_outlined,
                      Icons.person_outline_rounded,
                    ];
                    final filled = [
                      Icons.chat_bubble_rounded,
                      Icons.people_rounded,
                      Icons.explore_rounded,
                      Icons.person_rounded,
                    ];
                    return Expanded(
                      child: Semantics(
                        selected: selected,
                        button: true,
                        label: titles[index],
                        child: InkWell(
                          onTap: () => setState(() => tab = index),
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary.withValues(alpha: .1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Badge(
                                  isLabelVisible: index == 0 && app.unread > 0,
                                  label: Text(
                                    app.unread > 99 ? '99+' : '${app.unread}',
                                  ),
                                  child: Icon(
                                    selected ? filled[index] : icons[index],
                                    size: 24,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  titles[index],
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.muted,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConversationList extends StatefulWidget {
  const ConversationList({super.key});
  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  String query = '';
  int filter = 0;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.conversations
        .where(
          (c) =>
              c.name.toLowerCase().contains(query.toLowerCase()) &&
              (filter == 0 ||
                  filter == 1 && c.unread > 0 ||
                  filter == 2 && c.isGroup),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: '搜索联系人或会话',
              prefixIcon: Icon(Icons.search_rounded, size: 22),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Text(['全部', '未读', '群聊'][i]),
                    selected: filter == i,
                    showCheckmark: false,
                    side: BorderSide.none,
                    selectedColor: Colors.white.withValues(alpha: .85),
                    backgroundColor: Colors.transparent,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: filter == i
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: filter == i ? AppColors.primary : AppColors.muted,
                    ),
                    onSelected: (_) => setState(() => filter = i),
                  ),
                ),
              const Spacer(),
              if (app.syncing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: app.sync,
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * .47,
                        child: EmptyState(
                          title: query.isNotEmpty
                              ? '没有找到相关会话'
                              : filter == 1
                              ? '消息都已读完啦'
                              : '从一句你好开始',
                          description: '下拉同步消息，或添加好友开启聊天',
                          action: TextButton(
                            onPressed: () =>
                                pushPage(context, const FindFriendPage()),
                            child: const Text('添加好友'),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 120),
                    itemCount: list.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final c = list[index];
                      return Material(
                        color: c.pinned
                            ? Colors.white.withValues(alpha: .5)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () =>
                              pushPage(context, ChatPage(conversation: c)),
                          onLongPress: () => _menu(c),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Badge(
                                  isLabelVisible: c.unread > 0,
                                  label: Text(
                                    c.unread > 99 ? '99+' : '${c.unread}',
                                  ),
                                  child: UserAvatar(
                                    name: c.name,
                                    url: c.avatar,
                                    size: 56,
                                    group: c.isGroup,
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              c.name.isEmpty ? '未命名会话' : c.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (c.pinned)
                                            const Padding(
                                              padding: EdgeInsets.only(left: 6),
                                              child: Icon(
                                                Icons.push_pin_rounded,
                                                size: 12,
                                                color: AppColors.muted,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        c.preview.isEmpty
                                            ? '开启一段新的对话吧'
                                            : c.preview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      clockText(c.time),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontSize: 11),
                                    ),
                                    const SizedBox(height: 11),
                                    if (c.muted)
                                      const Icon(
                                        Icons.notifications_off_outlined,
                                        size: 14,
                                        color: AppColors.muted,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _menu(Conversation c) async {
    final app = AppScope.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(c.pinned ? '取消置顶' : '置顶会话'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none_rounded),
              title: Text(c.muted ? '开启提醒' : '消息免打扰'),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('移除会话'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (selected == 'pin') {
      await runAction(
        context,
        () => app.setConversationFlag(c, 'isTop', !c.pinned),
      );
    }
    if (!mounted) return;
    if (selected == 'mute') {
      await runAction(
        context,
        () => app.setConversationFlag(c, 'isMute', !c.muted),
      );
    }
    if (selected == 'delete') {
      if (!mounted) return;
      await runAction(context, () => app.deleteConversation(c));
    }
  }
}
