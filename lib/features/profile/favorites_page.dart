import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../chat/media_widgets.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '收藏与笔记',
      child: Loadable(
        load: () => app.api.get('/favorites/list'),
        builder: (context, data, reload) {
          final list = asList(data);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await pushPage(context, const NoteEditorPage());
                    await reload();
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('记一篇笔记'),
                ),
                const SizedBox(height: 22),
                if (list.isEmpty)
                  const EmptyState(
                    title: '把喜欢的内容留在这里',
                    description: '长按聊天消息收藏，或创建自己的笔记',
                    icon: Icons.bookmarks_outlined,
                  ),
                for (final item in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: GlassCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(18),
                        leading: Icon(
                          number(item['type']) == 0
                              ? Icons.description_outlined
                              : Icons.bookmark_border_rounded,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          str(item['title']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          str(item['sourceUsername']).isEmpty
                              ? '我的笔记'
                              : '来自 ${item['sourceUsername']}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (_) async {
                            if (!await confirm(context, '移除收藏', '确定移除这条内容吗？')) {
                              return;
                            }
                            if (!context.mounted) return;
                            await runAction(context, () async {
                              await app.api.delete(
                                '/favorites/delete/${item['id']}',
                              );
                              await reload();
                            });
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('移除')),
                          ],
                        ),
                        onTap: () async {
                          await pushPage(
                            context,
                            FavoriteDetailPage(item: item),
                          );
                          await reload();
                        },
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

class FavoriteDetailPage extends StatelessWidget {
  const FavoriteDetailPage({super.key, required this.item});
  final Json item;
  @override
  Widget build(BuildContext context) {
    final type = number(item['type']);
    final content = str(item['content']);
    return PageScaffold(
      title: str(item['title']),
      actions: [
        if (type == 0)
          IconButton(
            tooltip: '编辑笔记',
            onPressed: () => pushPage(context, NoteEditorPage(item: item)),
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (type == 2)
            InkWell(
              onTap: () => pushPage(context, ImagePreviewPage(url: content)),
              child: Image.network(
                content,
                errorBuilder: (_, e, s) => const Text('图片加载失败'),
              ),
            )
          else if (type == 3)
            FilledButton(
              onPressed: () =>
                  pushPage(context, VideoPreviewPage(url: content)),
              child: const Text('播放视频'),
            )
          else if (type == 4)
            AudioMessage(url: content)
          else if (type == 5)
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('打开收藏的文件'),
              onTap: () => openLink(context, content),
            )
          else
            HtmlWidget(
              content,
              onTapUrl: (url) async {
                await openLink(context, url);
                return true;
              },
              onTapImage: (image) => pushPage(
                context,
                ImagePreviewPage(url: image.sources.first.url),
              ),
            ),
        ],
      ),
    );
  }
}

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.item});
  final Json? item;
  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController title;
  late final TextEditingController body;
  bool busy = false;
  final List<String> images = [];
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: str(widget.item?['title']));
    // 既有富文本以 HTML 保留；普通输入会被转义，避免丢失编辑前的图片与格式。
    body = TextEditingController(text: str(widget.item?['content']));
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy ||
        title.text.trim().isEmpty ||
        body.text.trim().isEmpty && images.isEmpty) {
      return;
    }
    setState(() => busy = true);
    try {
      final content = body.text.contains(RegExp(r'<\w+'))
          ? body.text
          : '<p>${const HtmlEscape().convert(body.text).replaceAll('\n', '<br>')}</p>';
      await AppScope.of(context).api.post(
        widget.item == null ? '/favorites/saveNote' : '/favorites/updateNote',
        data: {
          if (widget.item != null) 'id': widget.item!['id'],
          'title': title.text.trim(),
          'type': 0,
          'content':
              content +
              images
                  .map(
                    (url) => '<img src="${const HtmlEscape().convert(url)}">',
                  )
                  .join(),
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: widget.item == null ? '新建笔记' : '编辑笔记',
    actions: [
      TextButton(
        onPressed: busy ? null : save,
        child: Text(busy ? '保存中…' : '保存'),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: title,
          maxLength: 100,
          decoration: const InputDecoration(hintText: '给笔记起个标题'),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: body,
          minLines: 12,
          maxLines: null,
          decoration: InputDecoration(
            hintText: widget.item == null
                ? '记下此刻的灵感…'
                : '编辑笔记内容（既有富文本保留为 HTML）',
          ),
        ),
        const SizedBox(height: 12),
        for (final url in images)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Image.network(url, height: 120),
          ),
        TextButton.icon(
          onPressed: busy
              ? null
              : () => runAction(context, () async {
                  final app = AppScope.of(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    withData: true,
                  );
                  if (result == null) return;
                  final file = result.files.single;
                  final urls = await app.api.post(
                    '/favorites/uploadImage',
                    data: FormData.fromMap({
                      'images': MultipartFile.fromBytes(
                        file.bytes!,
                        filename: file.name,
                      ),
                    }),
                  );
                  if (mounted && urls is List) {
                    setState(() => images.addAll(urls.map(str)));
                  }
                }),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('插入图片'),
        ),
      ],
    ),
  );
}
