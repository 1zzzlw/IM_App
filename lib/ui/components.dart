import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../core/app_state.dart';
import 'theme.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// 背景固定渐变避免动画不断触发模糊计算，卡片单独裁剪以控制 GPU 开销。
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFECF2FF), Color(0xFFF5F4FC), Color(0xFFF3F8FB)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -180,
          right: -120,
          child: _glow(const Color(0xFFCDD8FF), 430),
        ),
        Positioned(
          top: 260,
          left: -180,
          child: _glow(const Color(0xFFE3DDF8), 380),
        ),
        Positioned(
          bottom: -120,
          right: -140,
          child: _glow(const Color(0xFFD5EEED), 400),
        ),
        Positioned.fill(child: child),
      ],
    ),
  );
  Widget _glow(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: .7), color.withValues(alpha: 0)],
      ),
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.blur = 16,
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white.withValues(alpha: .56),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: .85)),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  );
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.url = '',
    this.size = 50,
    this.online,
    this.group = false,
  });
  final String name;
  final String url;
  final double size;
  final bool? online;
  final bool group;
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF8A9CEB),
      const Color(0xFF9E9AE0),
      const Color(0xFF78BEB4),
      const Color(0xFFE0A78F),
    ];
    final color = colors[name.runes.fold(0, (a, b) => a + b) % colors.length];
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: .68), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: group
          ? Icon(
              Icons.people_alt_rounded,
              color: Colors.white,
              size: size * .47,
            )
          : Text(
              name.isEmpty ? '聊' : String.fromCharCode(name.runes.first),
              style: TextStyle(
                fontSize: size * .38,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * .34),
              child: url.isEmpty
                  ? fallback
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stack) => fallback,
                    ),
            ),
          ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: online! ? AppColors.mint : const Color(0xFFC2C7D4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description = '',
    this.icon = Icons.forum_outlined,
    this.action,
  });
  final String title;
  final String description;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(
              icon,
              size: 38,
              color: AppColors.primary.withValues(alpha: .65),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 20), child: action!),
        ],
      ),
    ),
  );
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottom,
    this.floatingActionButton,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  final Widget? floatingActionButton;
  @override
  Widget build(BuildContext context) => GlassBackground(
    child: Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: child,
      bottomNavigationBar: bottom,
      floatingActionButton: floatingActionButton,
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 20, 6, 12),
    child: Row(
      children: [
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<T?> runAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) toast(context, success);
    return result;
  } catch (e) {
    if (context.mounted) toast(context, e.toString());
    return null;
  }
}

Future<void> pushPage(BuildContext context, Widget page) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> editText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  bool multiline = false,
  bool obscure = false,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: obscure,
        keyboardType: keyboardType,
        minLines: multiline ? 4 : 1,
        maxLines: multiline ? 8 : 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // 对话框退场动画结束后由框架释放输入框，避免提前 dispose 仍在使用的 controller。
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  return result;
}

class Loadable extends StatefulWidget {
  const Loadable({super.key, required this.load, required this.builder});
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext, dynamic, Future<void> Function()) builder;
  @override
  State<Loadable> createState() => _LoadableState();
}

class _LoadableState extends State<Loadable> {
  dynamic data;
  Object? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final value = await widget.load();
      if (mounted) {
        setState(() {
          data = value;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error != null) {
      return EmptyState(
        title: '暂时没有加载成功',
        description: error.toString(),
        icon: Icons.cloud_off_rounded,
        action: FilledButton.tonal(
          onPressed: () {
            setState(() => loading = true);
            reload();
          },
          child: const Text('重新加载'),
        ),
      );
    }
    return widget.builder(context, data, reload);
  }
}
