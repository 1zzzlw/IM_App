import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';

/// 金额先按分校验，提交十进制字符串，避免浮点计算影响支付参数。
String validAmount(String input) {
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input.trim())) {
    throw Exception('请输入最多两位小数的金额');
  }
  final parts = input.trim().split('.');
  final cents =
      BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (cents <= BigInt.zero) throw Exception('金额必须大于 0');
  return '${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
}

String money(dynamic value) =>
    (double.tryParse(str(value)) ?? 0).toStringAsFixed(2);

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '我的钱包',
      actions: [
        TextButton(
          onPressed: () => pushPage(context, const WalletRecordsPage()),
          child: const Text('账单'),
        ),
      ],
      child: Loadable(
        load: () => app.api.get('/wallet/info'),
        builder: (context, result, reload) {
          final wallet = asJson(result);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 22),
                GlassCard(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppColors.primary,
                        size: 36,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '可用余额',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '¥ ${money(wallet['balance'])}',
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '冻结金额  ¥ ${money(wallet['freezeBalance'])}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => changeBalance(context, 'recharge', reload),
                  child: const Text('充值'),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => changeBalance(context, 'withdraw', reload),
                  child: const Text('提现'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> changeBalance(
    BuildContext context,
    String operation,
    Future<void> Function() reload,
  ) async {
    final api = AppScope.of(context).api;
    final title = operation == 'recharge' ? '充值' : '提现';
    final input = await editText(
      context,
      title: '$title金额',
      hint: '0.00',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (input == null || !context.mounted) return;
    await runAction(context, () async {
      final amount = validAmount(input);
      if (!await confirm(context, '确认$title', '$title ¥ $amount')) return;
      await api.post(
        '/wallet/$operation',
        data: {'amount': amount, 'remark': '移动端$title'},
      );
      await reload();
    });
  }
}

class WalletRecordsPage extends StatefulWidget {
  const WalletRecordsPage({super.key});
  @override
  State<WalletRecordsPage> createState() => _WalletRecordsPageState();
}

class _WalletRecordsPageState extends State<WalletRecordsPage> {
  final List<Json> records = [];
  int page = 1;
  int type = 0;
  bool busy = false;
  bool more = true;
  String? error;
  static const labels = [
    '全部',
    '充值',
    '提现',
    '打赏支出',
    '打赏收入',
    '红包支出',
    '红包收入',
    '转账支出',
    '转账收入',
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final next = reset ? 1 : page;
      final result = asList(
        await AppScope.of(context).api.get(
          '/wallet/records',
          query: {'page': next, 'pageSize': 20, 'type': type},
        ),
      );
      if (mounted) {
        setState(() {
          if (reset) records.clear();
          records.addAll(result);
          more = result.length == 20;
          page = next + 1;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: '钱包账单',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: DropdownButtonFormField<int>(
            initialValue: type,
            decoration: const InputDecoration(labelText: '账单类型'),
            items: List.generate(
              labels.length,
              (i) => DropdownMenuItem(value: i, child: Text(labels[i])),
            ),
            onChanged: busy
                ? null
                : (v) {
                    setState(() => type = v!);
                    load(reset: true);
                  },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => load(reset: true),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (error != null)
                  ListTile(
                    title: Text(error!),
                    trailing: TextButton(
                      onPressed: () => load(reset: true),
                      child: const Text('重试'),
                    ),
                  ),
                if (records.isEmpty && !busy && error == null)
                  const EmptyState(
                    title: '还没有账单记录',
                    icon: Icons.receipt_long_outlined,
                  ),
                for (final record in records)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 0,
                    ),
                    leading: const Icon(
                      Icons.receipt_long_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      str(record['remark']).isEmpty
                          ? labels[number(record['type']).clamp(0, 8)]
                          : str(record['remark']),
                    ),
                    subtitle: Text(
                      str(record['createTime'] ?? record['createdAt']),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                    trailing: Text(
                      '¥ ${money(record['amount'])}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (busy)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (more)
                  TextButton(onPressed: load, child: const Text('加载更多')),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
