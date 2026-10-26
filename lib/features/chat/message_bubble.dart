import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'media_widgets.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.name,
    required this.avatar,
    required this.onLongPress,
    required this.onRetry,
    required this.onRedPacket,
    required this.onFile,
    this.showName = false,
  });
  final ChatMessage message;
  final bool mine;
  final String name;
  final String avatar;
  final bool showName;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final VoidCallback onRedPacket;
  final VoidCallback onFile;
  @override
  Widget build(BuildContext context) {
    if (message.revoked || message.type == 99) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 35),
        child: Text(
          message.displayText,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      );
    }
    final foreground = mine ? Colors.white : AppColors.ink;
    Widget content;
    switch (message.type) {
      case 2:
        content = InkWell(
          onTap: message.url.isEmpty
              ? null
              : () => pushPage(context, ImagePreviewPage(url: message.url)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: message.url.isEmpty
                ? const Text('图片尚未上传完成')
                : Image.network(
                    message.url,
                    width: 210,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const SizedBox(
                      width: 180,
                      height: 100,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
          ),
        );
        break;
      case 3:
        content = InkWell(
          onTap: message.url.isEmpty
              ? null
              : () => pushPage(context, VideoPreviewPage(url: message.url)),
          child: SizedBox(
            width: 190,
            height: 100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 38,
                  color: foreground,
                ),
                const SizedBox(height: 8),
                Text(
                  message.fileName.isEmpty ? '视频消息' : message.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground),
                ),
              ],
            ),
          ),
        );
        break;
      case 4:
        content = AudioMessage(url: message.url);
        break;
      case 5:
        content = InkWell(
          onTap: onFile,
          child: SizedBox(
            width: 205,
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 36,
                  color: foreground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${(number(message.data['fileSize']) / 1024).toStringAsFixed(1)} KB · 点击保存',
                        style: TextStyle(
                          color: foreground.withValues(alpha: .65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        break;
      case 6:
        content = InkWell(
          onTap: onRedPacket,
          child: SizedBox(
            width: 205,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.redeem_rounded, color: Colors.white, size: 31),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '一份心意，送给你',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Container(height: 1, color: Colors.white24),
                const SizedBox(height: 8),
                const Text(
                  '轻聊红包',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        );
        break;
      default:
        content = Text(
          message.content,
          style: TextStyle(color: foreground, fontSize: 15, height: 1.55),
        );
    }
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .68,
        ),
        padding: EdgeInsets.all(message.type == 2 ? 5 : 15),
        decoration: BoxDecoration(
          color: message.type == 6
              ? const Color(0xFFE8A168)
              : mine
              ? AppColors.primary
              : Colors.white.withValues(alpha: .82),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 6),
            bottomRight: Radius.circular(mine ? 6 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: (mine ? AppColors.primary : AppColors.muted).withValues(
                alpha: .06,
              ),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (str(message.data['quoteMsgId']).isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  str(message.data['quoteContent']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: foreground.withValues(alpha: .75),
                  ),
                ),
              ),
            content,
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 7, 18, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            UserAvatar(name: name, url: avatar, size: 35),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showName && !mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5, left: 3),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                bubble,
                if (mine)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: message.status == 2
                        ? InkWell(
                            onTap: onRetry,
                            child: const Text(
                              '发送失败 · 点击重试',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFD86C7E),
                              ),
                            ),
                          )
                        : Text(
                            message.status == 0
                                ? '发送中…'
                                : clockText(message.time),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                  ),
              ],
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 10),
            UserAvatar(name: name, url: avatar, size: 35),
          ],
        ],
      ),
    );
  }
}
