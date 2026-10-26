import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../ai/ai_page.dart';
import '../moments/moments_page.dart';
import '../wallet/wallet_page.dart';
import 'favorites_page.dart';
import 'server_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final user = app.user;
    if (user == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 5, 24, 125),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              UserAvatar(name: user.name, url: user.avatar, size: 70),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      '账号 ${user.account}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      str(user.data['phone']),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              _item(
                context,
                Icons.account_balance_wallet_outlined,
                '我的钱包',
                const WalletPage(),
                color: const Color(0xFFE3AB62),
              ),
              _item(
                context,
                Icons.bookmark_border_rounded,
                '收藏与笔记',
                const FavoritesPage(),
                color: AppColors.primary,
              ),
              _item(
                context,
                Icons.photo_library_outlined,
                '我的动态',
                const MyMomentsPage(),
                color: AppColors.mint,
              ),
              _item(
                context,
                Icons.auto_awesome_outlined,
                'AI 助手',
                const AiPage(),
                color: const Color(0xFFA38BD8),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              _item(context, Icons.tune_rounded, '连接设置', const ServerPage()),
              ListTile(
                leading: const Icon(
                  Icons.cleaning_services_outlined,
                  color: AppColors.muted,
                ),
                title: const Text('清理本地消息缓存'),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () async {
                  if (!await confirm(context, '清理本地缓存', '清理后仍可从服务器重新加载聊天记录。')) {
                    return;
                  }
                  if (context.mounted) {
                    await runAction(
                      context,
                      app.clearLocalCache,
                      success: '本地缓存已清理',
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.muted,
                ),
                title: const Text('关于轻聊'),
                trailing: const Text(
                  '1.0.0',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: '轻聊',
                  applicationVersion: '1.0.0',
                  applicationIcon: Image.asset(
                    'assets/branding/app_icon.png',
                    width: 40,
                    height: 40,
                  ),
                  children: [
                    const Text('连接生活中的美好。\n基于现有 IM 服务的 Flutter 移动客户端。'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () async {
            if (!await confirm(context, '退出登录', '确定退出当前账号吗？')) return;
            await app.logout();
          },
          child: const Text('退出登录', style: TextStyle(color: Color(0xFFD86C7E))),
        ),
      ],
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    Widget page, {
    Color color = AppColors.muted,
  }) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: () => pushPage(context, page),
  );
}
