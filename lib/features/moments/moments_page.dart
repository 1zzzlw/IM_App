import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../chat/media_widgets.dart';
import '../wallet/wallet_page.dart' show validAmount;

class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key, this.mine = false});
  final bool mine;
  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  final List<Json> list = [];
  int mode = 0;
  int page = 1;
  static const pageSize = 20;
  bool loading = false;
  bool more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load(reset: true));
  }

  Future<void> load({bool reset = false}) async {
    if (loading) return;
    final app = AppScope.of(context);
    setState(() => loading = true);
    try {
      final next = reset ? 1 : page;
      final result = await app.api.get(
        widget.mine
            ? '/moments/my'
            : mode == 0
            ? '/moments/list/new'
            : '/moments/list/hot',
        query: widget.mine || mode == 1
            ? {'page': next, 'pageSize': pageSize}
            : {
                'lastId': reset || list.isEmpty
                    ? '9223372036854775807'
                    : str(list.last['id']),
              },
      );
      final items = asList(result);
      if (mounted) {
        setState(() {
          if (reset) list.clear();
          final existing = list.map((item) => str(item['id'])).toSet();
          list.addAll(
            items.where((item) => !existing.contains(str(item['id']))),
          );
          // 最新使用 ID 游标，热门/我的动态使用 PageResult.total 判断分页终点。
          final total = asJson(result)['total'];
          more = widget.mine || mode == 1
              ? total == null
                    ? items.length == pageSize
                    : next * pageSize < number(total)
              : items.isNotEmpty;
          page = next + 1;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => load(reset: true),
    child: ListView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, widget.mine ? 30 : 125),
      children: [
        if (!widget.mine) ...[
          GlassCard(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '生活，值得分享。',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '把小小的美好，留给在意的人',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '发布动态',
                  onPressed: () async {
                    await pushPage(context, const MomentEditorPage());
                    if (mounted) load(reset: true);
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                TextButton(
                  onPressed: loading
                      ? null
                      : () {
                          setState(() => mode = i);
                          load(reset: true);
                        },
                  child: Text(
                    ['最新', '热门'][i],
                    style: TextStyle(
                      color: mode == i ? AppColors.primary : AppColors.muted,
                      fontWeight: mode == i
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (error != null)
          ListTile(
            title: Text(error!, style: const TextStyle(fontSize: 12)),
            trailing: TextButton(
              onPressed: () => load(reset: true),
              child: const Text('重试'),
            ),
          ),
        if (list.isEmpty && !loading && error == null)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(
              title: '还没有动态',
              description: '分享第一份日常吧',
              icon: Icons.auto_awesome_outlined,
            ),
          ),
        for (final item in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 17),
            child: MomentCard(item: item, onChanged: () => load(reset: true)),
          ),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (more && list.isNotEmpty)
          TextButton(onPressed: load, child: const Text('看看更多')),
      ],
    ),
  );
}

class MyMomentsPage extends StatelessWidget {
  const MyMomentsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const PageScaffold(title: '我的动态', child: MomentsPage(mine: true));
}

class MomentCard extends StatefulWidget {
  const MomentCard({
    super.key,
    required this.item,
    required this.onChanged,
    this.detail = false,
  });
  final Json item;
  final Future<void> Function() onChanged;
  final bool detail;
  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  bool liking = false;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final item = widget.item;
    final mine = str(item['userId']) == app.user?.id;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: str(item['username']),
                url: str(item['avatar']),
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      str(item['username']),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      clockText(item['publishTime']),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (mine)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await pushPage(context, MomentEditorPage(item: item));
                      await widget.onChanged();
                    }
                    if (v == 'delete' &&
                        context.mounted &&
                        await confirm(context, '删除动态', '确定删除这条动态吗？')) {
                      if (!context.mounted) return;
                      await runAction(context, () async {
                        await app.api.delete('/moments/delete/${item['id']}');
                        await widget.onChanged();
                      });
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: widget.detail
                ? null
                : () async {
                    await pushPage(
                      context,
                      MomentDetailPage(id: str(item['id'])),
                    );
                    await widget.onChanged();
                  },
            child: HtmlWidget(
              str(item['content']),
              textStyle: const TextStyle(fontSize: 14, height: 1.6),
              onTapUrl: (url) async {
                await openLink(context, url);
                return true;
              },
              onTapImage: (image) => pushPage(
                context,
                ImagePreviewPage(url: image.sources.first.url),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: flag(item['liked']) ? '取消点赞' : '点赞',
                onPressed: liking
                    ? null
                    : () async {
                        setState(() => liking = true);
                        await runAction(context, () async {
                          await app.api.post('/moments/like/${item['id']}');
                          if (mounted) {
                            setState(() {
                              final was = flag(item['liked']);
                              item['liked'] = !was;
                              item['likeCount'] =
                                  number(item['likeCount']) + (was ? -1 : 1);
                            });
                          }
                        });
                        if (mounted) setState(() => liking = false);
                      },
                icon: Icon(
                  flag(item['liked'])
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 21,
                  color: flag(item['liked'])
                      ? const Color(0xFFD9869B)
                      : AppColors.muted,
                ),
              ),
              Text(
                '${number(item['likeCount'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '查看评论',
                onPressed: widget.detail
                    ? null
                    : () => pushPage(
                        context,
                        MomentDetailPage(id: str(item['id'])),
                      ),
                icon: const Icon(
                  Icons.mode_comment_outlined,
                  size: 20,
                  color: AppColors.muted,
                ),
              ),
              Text(
                '${number(item['commentCount'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final input = await editText(
                    context,
                    title: '送一份鼓励',
                    hint: '打赏金额',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  );
                  if (input == null || !context.mounted) return;
                  await runAction(context, () async {
                    final amount = validAmount(input);
                    if (!await confirm(
                      context,
                      '确认打赏',
                      '向 ${item['username']} 打赏 ¥ $amount',
                    )) {
                      return;
                    }
                    await app.api.post(
                      '/moments/reward',
                      query: {'momentId': item['id'], 'amount': amount},
                    );
                  }, success: '心意已送达');
                },
                child: const Text('送心意', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MomentDetailPage extends StatefulWidget {
  const MomentDetailPage({super.key, required this.id});
  final String id;
  @override
  State<MomentDetailPage> createState() => _MomentDetailPageState();
}

class _MomentDetailPageState extends State<MomentDetailPage> {
  final comment = TextEditingController();
  Json? replyTo;
  bool busy = false;
  int page = 1;
  final List<Json> comments = [];
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '动态详情',
      child: Loadable(
        load: () async {
          final result = await Future.wait([
            app.api.get('/moments/detail/${widget.id}'),
            app.api.get(
              '/moments/comments/query',
              query: {'momentId': widget.id, 'page': 1, 'pageSize': 20},
            ),
          ]);
          comments
            ..clear()
            ..addAll(asList(result[1]));
          page = 2;
          return result[0];
        },
        builder: (context, data, reload) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  MomentCard(
                    item: asJson(data),
                    detail: true,
                    onChanged: reload,
                  ),
                  const SectionLabel('评论'),
                  if (comments.isEmpty)
                    const Text(
                      '留下你的第一句回应吧',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  for (final item in comments)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      leading: UserAvatar(
                        name: str(item['username']),
                        url: str(item['avatar']),
                        size: 34,
                      ),
                      title: Text(
                        str(item['username']),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            str(item['content']),
                            style: const TextStyle(color: AppColors.ink),
                          ),
                          TextButton(
                            onPressed: () => showReplies(context, item, reload),
                            child: const Text(
                              '查看回复',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => setState(() => replyTo = item),
                      trailing: IconButton(
                        tooltip: '点赞评论',
                        icon: Icon(
                          flag(item['liked'])
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 17,
                        ),
                        onPressed: () => runAction(context, () async {
                          await app.api.post(
                            '/moments/comment/like/${item['id']}',
                          );
                          await reload();
                        }),
                      ),
                    ),
                  if (comments.isNotEmpty)
                    TextButton(
                      onPressed: () => runAction(context, () async {
                        final result = asList(
                          await app.api.get(
                            '/moments/comments/query',
                            query: {
                              'momentId': widget.id,
                              'page': page,
                              'pageSize': 20,
                            },
                          ),
                        );
                        if (mounted) {
                          setState(() {
                            comments.addAll(result);
                            page++;
                          });
                        }
                      }),
                      child: const Text('加载更多评论'),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (replyTo != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '回复 ${replyTo!['username']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '取消回复',
                          onPressed: () => setState(() => replyTo = null),
                          icon: const Icon(Icons.close_rounded, size: 16),
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: comment,
                          maxLines: 3,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: '说说你的想法…',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: '发送评论',
                        onPressed: busy
                            ? null
                            : () async {
                                if (comment.text.trim().isEmpty) return;
                                setState(() => busy = true);
                                await runAction(context, () async {
                                  await app.api.post(
                                    replyTo == null
                                        ? '/moments/comment/publish'
                                        : '/moments/comment/reply/publish',
                                    data: {
                                      'momentId': widget.id,
                                      'userId': app.user!.id,
                                      'username': app.user!.name,
                                      'avatar': app.user!.avatar,
                                      'content': comment.text.trim(),
                                      'publishTime': serverTime(),
                                      if (replyTo != null) ...{
                                        'parentId': replyTo!['id'],
                                        'replyToUserId': replyTo!['userId'],
                                        'replyToUsername': replyTo!['username'],
                                      },
                                    },
                                  );
                                  comment.clear();
                                  if (mounted) setState(() => replyTo = null);
                                  await reload();
                                });
                                if (mounted) setState(() => busy = false);
                              },
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showReplies(
    BuildContext context,
    Json parent,
    Future<void> Function() reload,
  ) async {
    final app = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Loadable(
          load: () => app.api.get(
            '/moments/comment/reply/${parent['id']}',
            query: {'page': 1, 'pageSize': 100},
          ),
          builder: (context, data, refresh) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '回复 ${parent['username']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              for (final item in asList(data))
                ListTile(
                  title: Text(
                    '${item['username']} → ${item['replyToUsername'] ?? parent['username']}',
                  ),
                  subtitle: Text(str(item['content'])),
                  trailing: IconButton(
                    icon: const Icon(Icons.reply_rounded),
                    tooltip: '回复',
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => replyTo = {...item, 'id': parent['id']});
                    },
                  ),
                ),
              if (asList(data).isEmpty) const EmptyState(title: '还没有回复'),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => replyTo = parent);
                },
                child: const Text('回复这条评论'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MomentEditorPage extends StatefulWidget {
  const MomentEditorPage({super.key, this.item});
  final Json? item;
  @override
  State<MomentEditorPage> createState() => _MomentEditorPageState();
}

class _MomentEditorPageState extends State<MomentEditorPage> {
  late final TextEditingController body;
  final List<PlatformFile> images = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    body = TextEditingController(text: str(widget.item?['content']));
  }

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> publish() async {
    if (busy || body.text.trim().isEmpty && images.isEmpty) return;
    setState(() => busy = true);
    final app = AppScope.of(context);
    try {
      var content = body.text.contains(RegExp(r'<\w+'))
          ? body.text
          : '<p>${const HtmlEscape().convert(body.text).replaceAll('\n', '<br>')}</p>';
      if (images.isNotEmpty) {
        final form = FormData();
        for (final image in images) {
          form.files.add(
            MapEntry(
              'images',
              MultipartFile.fromBytes(image.bytes!, filename: image.name),
            ),
          );
        }
        final urls = await app.api.post('/moments/uploadImage', data: form);
        if (urls is List) {
          content += urls
              .map(
                (url) => '<img src="${const HtmlEscape().convert(str(url))}">',
              )
              .join();
        }
      }
      final data = {
        'content': content,
        'userId': app.user!.id,
        'username': app.user!.name,
        'avatar': app.user!.avatar,
        'publishTime': widget.item?['publishTime'] ?? serverTime(),
        if (widget.item != null) 'id': widget.item!['id'],
      };
      if (widget.item == null) {
        await app.api.post('/moments/publish', data: data);
      } else {
        await app.api.put('/moments/update', data: data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: widget.item == null ? '分享此刻' : '编辑动态',
    actions: [
      TextButton(
        onPressed: busy ? null : publish,
        child: Text(busy ? '发布中…' : '发布'),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: body,
          minLines: 9,
          maxLines: null,
          decoration: InputDecoration(
            hintText: widget.item == null
                ? '今天，有什么值得记住的小事？'
                : '编辑内容（既有富文本保留为 HTML）',
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final image in images)
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(image.bytes!, fit: BoxFit.cover),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        tooltip: '移除图片',
                        onPressed: () => setState(() => images.remove(image)),
                        icon: const Icon(
                          Icons.cancel,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (images.length < 9)
              InkWell(
                onTap: busy
                    ? null
                    : () => runAction(context, () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                          allowMultiple: true,
                        );
                        if (result == null) return;
                        if (result.files.any((f) => f.size > 5 * 1024 * 1024)) {
                          throw Exception('每张图片请控制在 5 MB 以内');
                        }
                        if (mounted) {
                          setState(
                            () => images.addAll(
                              result.files.take(9 - images.length),
                            ),
                          );
                        }
                      }),
                child: const GlassCard(
                  padding: EdgeInsets.zero,
                  radius: 14,
                  child: SizedBox(
                    width: 90,
                    height: 90,
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppColors.primary,
                      size: 30,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
