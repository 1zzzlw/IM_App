import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../profile/server_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final account = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  Uint8List? captcha;
  String? captchaError;
  bool captchaLoading = false;
  int captchaRequest = 0;
  bool busy = false;
  bool hidden = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshCaptcha());
  }

  Future<void> refreshCaptcha() async {
    final request = ++captchaRequest;
    setState(() {
      captchaLoading = true;
      captchaError = null;
    });
    try {
      final image = await AppScope.of(context).api.captcha();
      if (mounted && request == captchaRequest) {
        setState(() {
          captcha = image;
          captchaError = null;
        });
      }
    } catch (e) {
      if (mounted && request == captchaRequest) {
        setState(() {
          captcha = null;
          captchaError = e.toString();
        });
      }
    } finally {
      if (mounted && request == captchaRequest) {
        setState(() => captchaLoading = false);
      }
    }
  }

  Future<void> login() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await AppScope.of(context).login(account.text, password.text, code.text);
    } catch (e) {
      if (mounted) {
        toast(context, e.toString());
        refreshCaptcha();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    account.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassBackground(
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: '服务器设置',
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () async {
                            await pushPage(context, const ServerPage());
                            if (mounted) refreshCaptcha();
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      GlassCard(
                        radius: 30,
                        padding: const EdgeInsets.all(20),
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          width: 48,
                          height: 48,
                          semanticLabel: '轻聊',
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        '很高兴，\n又见到你。',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '让每一次相遇，都近一点。',
                        style: TextStyle(color: AppColors.muted, fontSize: 15),
                      ),
                      const SizedBox(height: 34),
                      Form(
                        key: form,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: account,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                hintText: '你的账号',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '请输入账号'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: password,
                              obscureText: hidden,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                hintText: '密码',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: hidden ? '显示密码' : '隐藏密码',
                                  onPressed: () =>
                                      setState(() => hidden = !hidden),
                                  icon: Icon(
                                    hidden
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (v) =>
                                  v == null || v.isEmpty ? '请输入密码' : null,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: code,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => login(),
                                    decoration: const InputDecoration(
                                      hintText: '图形验证码',
                                      prefixIcon: Icon(
                                        Icons.verified_user_outlined,
                                      ),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? '请输入验证码'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Semantics(
                                  button: true,
                                  label: '刷新图形验证码',
                                  child: InkWell(
                                    onTap: refreshCaptcha,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      width: 108,
                                      height: 56,
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: .7,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: captchaLoading
                                          ? const Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            )
                                          : captcha == null
                                          ? const Icon(
                                              Icons.refresh_rounded,
                                              color: AppColors.primary,
                                            )
                                          : Image.memory(
                                              captcha!,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, error, stack) =>
                                                  const Icon(
                                                    Icons.broken_image_outlined,
                                                    color: AppColors.muted,
                                                  ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (captchaError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '验证码加载失败：$captchaError',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    Text(
                                      '当前接口：${AppScope.of(context).httpUrl}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        TextButton(
                                          onPressed: refreshCaptcha,
                                          child: const Text('重试验证码'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            await pushPage(
                                              context,
                                              const ServerPage(),
                                            );
                                            if (mounted) refreshCaptcha();
                                          },
                                          child: const Text('检查连接设置'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 26),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: FilledButton(
                                onPressed: busy ? null : login,
                                child: busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('登 录'),
                                          SizedBox(width: 12),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () => pushPage(context, const RegisterPage()),
                          child: const Text('还没有账号？  创建账号'),
                        ),
                      ),
                      const SizedBox(height: 38),
                      Center(
                        child: Text(
                          '轻 聊  /  连接生活中的美好',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(letterSpacing: 2),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  PlatformFile? avatar;
  int gender = 0;
  bool busy = false;
  bool codeBusy = false;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> pickAvatar() async {
    await runAction(context, () async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && mounted) {
        if (result.files.single.size > 5 * 1024 * 1024) {
          throw Exception('请选择 5 MB 以内的头像');
        }
        setState(() => avatar = result.files.single);
      }
    });
  }

  Future<void> register() async {
    if (busy || !form.currentState!.validate()) return;
    if (avatar?.bytes == null) {
      toast(context, '请先选择头像');
      return;
    }
    setState(() => busy = true);
    final app = AppScope.of(context);
    try {
      final data = FormData.fromMap({
        'username': name.text.trim(),
        'phone': phone.text.trim(),
        'password': password.text,
        'phoneCode': code.text.trim(),
        'gender': gender,
        'avatarFile': MultipartFile.fromBytes(
          avatar!.bytes!,
          filename: avatar!.name,
          contentType: DioMediaType.parse(avatarMime(avatar!.name)),
        ),
      });
      final profile = asJson(await app.api.post('/user/register', data: data));
      profile['id'] = profile['userId'] ?? profile['id'];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('账号创建成功'),
          content: SelectableText(
            '你的登录账号是：\n${profile['account']}\n\n请保存好这个账号。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('开始聊天'),
            ),
          ],
        ),
      );
      await app.acceptUser(profile);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: '创建账号',
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: InkWell(
                  onTap: pickAvatar,
                  borderRadius: BorderRadius.circular(30),
                  child: avatar?.bytes == null
                      ? const GlassCard(
                          child: SizedBox(
                            width: 66,
                            height: 66,
                            child: Icon(
                              Icons.add_a_photo_outlined,
                              size: 30,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: Image.memory(
                            avatar!.bytes!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  '选择一个喜欢的头像',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 28),
              _field(name, '昵称'),
              const SizedBox(height: 14),
              _field(phone, '手机号', keyboard: TextInputType.phone),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _field(code, '手机验证码')),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: codeBusy
                        ? null
                        : () async {
                            if (!RegExp(r'^1\d{10}$')
                                .hasMatch(phone.text.trim())) {
                              toast(context, '请输入正确的手机号');
                              return;
                            }
                            setState(() => codeBusy = true);
                            await runAction(context, () async {
                              final result = await AppScope.of(context).api
                                  .post(
                                    '/user/phoneCode',
                                    query: {'phone': phone.text.trim()},
                                    data: {},
                                  );
                              if (!context.mounted) return;
                              if (str(result).isNotEmpty) {
                                code.text = str(result);
                                toast(context, '当前服务返回的验证码已填入');
                              } else {
                                toast(context, '验证码已发送');
                              }
                            });
                            if (mounted) setState(() => codeBusy = false);
                          },
                    child: Text(codeBusy ? '获取中…' : '获取验证码'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _field(password, '设置密码', secret: true),
              const SizedBox(height: 18),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('保密')),
                  ButtonSegment(value: 1, label: Text('男')),
                  ButtonSegment(value: 2, label: Text('女')),
                ],
                selected: {gender},
                onSelectionChanged: (v) => setState(() => gender = v.first),
              ),
              const SizedBox(height: 30),
              FilledButton(
                onPressed: busy ? null : register,
                child: Text(busy ? '正在创建…' : '创建账号'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    TextInputType? keyboard,
  }) => TextFormField(
    controller: controller,
    obscureText: secret,
    keyboardType: keyboard,
    decoration: InputDecoration(hintText: label),
    validator: (v) => v == null || v.trim().isEmpty ? '请输入$label' : null,
  );
}

String avatarMime(String name) => name.toLowerCase().endsWith('.png')
    ? 'image/png'
    : name.toLowerCase().endsWith('.webp')
    ? 'image/webp'
    : 'image/jpeg';
