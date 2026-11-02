import 'package:material_ui/material_ui.dart';

import '../../core/mobile_services.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key, required this.mobile});
  final MobileServices mobile;

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: '消息与后台接收',
    child: ListenableBuilder(
      listenable: mobile,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('新消息提醒'),
                  subtitle: const Text('显示聊天弹窗和系统消息通知'),
                  value: mobile.enabled,
                  onChanged: (value) =>
                      mobile.setOption('im.notifications', value),
                ),
                SwitchListTile(
                  title: const Text('消息提示音'),
                  subtitle: const Text('收到新消息时播放声音'),
                  value: mobile.soundEnabled,
                  onChanged: mobile.enabled
                      ? (value) => mobile.setOption('im.messageSound', value)
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_none_rounded),
                  title: Text(
                    mobile.permissionGranted ? '系统通知已允许' : '系统通知尚未允许',
                  ),
                  trailing: TextButton(
                    onPressed: () =>
                        MobileServices.channel.invokeMethod('openSettings'),
                    child: const Text('系统设置'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('后台连接保活'),
                  subtitle: const Text('保持聊天连接，通知栏会显示运行状态'),
                  value: mobile.backgroundEnabled,
                  onChanged: (value) =>
                      mobile.setOption('im.background', value),
                ),
                ListTile(
                  title: const Text('后台与省电设置'),
                  subtitle: const Text('若锁屏后收不到消息，可允许轻聊在后台运行'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      MobileServices.channel.invokeMethod('batterySettings'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '正在查看的会话和免打扰会话不会重复提醒。',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
