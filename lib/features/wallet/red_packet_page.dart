import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'wallet_page.dart';

class SendRedPacketPage extends StatefulWidget {
  const SendRedPacketPage({super.key, required this.conversation});
  final Conversation conversation;
  @override
  State<SendRedPacketPage> createState() => _SendRedPacketPageState();
}

class _SendRedPacketPageState extends State<SendRedPacketPage> {
  final amount = TextEditingController();
  final count = TextEditingController(text: '1');
  final greeting = TextEditingController(text: '愿好事与你相遇');
  bool busy = false;
  int type = 0;
  @override
  void dispose() {
    amount.dispose();
    count.dispose();
    greeting.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy) return;
    final app = AppScope.of(context);
    setState(() => busy = true);
    try {
      final sum = validAmount(amount.text);
      final total = widget.conversation.isGroup
          ? int.tryParse(count.text) ?? 0
          : 1;
      if (total <= 0 || total > 200) throw Exception('红包个数应在 1 至 200 之间');
      final cents = BigInt.parse(sum.replaceAll('.', ''));
      if (cents < BigInt.from(total)) throw Exception('每个红包至少 0.01 元');
      if (!await confirm(context, '确认发红包', '共 $total 个红包，总额 ¥ $sum')) return;
      if (app.socket.state.name != 'online') throw Exception('聊天连接尚未就绪，请稍后再发');
      if (widget.conversation.isGroup) {
        await app.loadMembers(widget.conversation.id);
      }
      final messageId = app.nextId();
      final data = asJson(
        await app.api.post(
          '/redPacket/send',
          data: {
            'messageId': messageId,
            'conversationId': widget.conversation.id,
            'receiverId': widget.conversation.isGroup
                ? null
                : widget.conversation.targetId,
            'receiverIds': widget.conversation.isGroup
                ? (app.members[widget.conversation.id] ?? [])
                      .map((m) => str(m['userId']))
                      .where((id) => id != app.user!.id)
                      .toList()
                : [],
            'totalAmount': sum,
            'totalCount': total,
            'type': widget.conversation.isGroup ? type : 0,
            'greeting': greeting.text.trim(),
          },
        ),
      );
      if (str(data['id']).isEmpty) throw Exception('服务未返回红包 ID');
      await app.send(
        widget.conversation,
        '[红包]',
        type: 6,
        extra: {'id': messageId, 'redPacketId': str(data['id'])},
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
    title: '送出一份心意',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.redeem_rounded, size: 70, color: Color(0xFFE8A168)),
        const SizedBox(height: 30),
        GlassCard(
          child: Column(
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '总金额',
                  prefixText: '¥ ',
                ),
              ),
              if (widget.conversation.isGroup) ...[
                const SizedBox(height: 18),
                TextField(
                  controller: count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '红包个数'),
                ),
                const SizedBox(height: 18),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('普通红包')),
                    ButtonSegment(value: 1, label: Text('拼手气')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setState(() => type = s.first),
                ),
              ],
              const SizedBox(height: 18),
              TextField(
                controller: greeting,
                maxLength: 60,
                decoration: const InputDecoration(labelText: '祝福语'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: busy ? null : send,
          child: Text(busy ? '正在发送…' : '发红包'),
        ),
      ],
    ),
  );
}

class RedPacketDetailPage extends StatefulWidget {
  const RedPacketDetailPage({super.key, required this.id});
  final String id;
  @override
  State<RedPacketDetailPage> createState() => _RedPacketDetailPageState();
}

class _RedPacketDetailPageState extends State<RedPacketDetailPage> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PageScaffold(
      title: '红包详情',
      child: Loadable(
        load: () => app.api.get('/redPacket/detail/${widget.id}'),
        builder: (context, result, reload) {
          final data = asJson(result);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 25),
              const Icon(
                Icons.redeem_rounded,
                size: 68,
                color: Color(0xFFE8A168),
              ),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  '${data['senderName'] ?? '好友'}的红包',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  str(data['greeting']),
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 28),
              if (flag(data['grabbed']))
                Center(
                  child: Text(
                    '¥ ${money(data['grabbedAmount'])}',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (number(data['remainCount']) > 0 &&
                  number(data['status']) == 0)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await runAction(context, () async {
                            await app.api.post('/redPacket/grab/${widget.id}');
                            await reload();
                          });
                          if (mounted) setState(() => busy = false);
                        },
                  child: Text(busy ? '正在领取…' : '打开红包'),
                ),
              const SectionLabel('领取记录'),
              Text(
                '已领取 ${number(data['totalCount']) - number(data['remainCount'])}/${data['totalCount']} 个 · 共 ¥ ${money(data['totalAmount'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 15),
              for (final record in asList(data['records']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(
                    name: str(record['username']),
                    url: str(record['avatar']),
                    size: 42,
                  ),
                  title: Text(str(record['username'])),
                  subtitle: Text(
                    str(record['createdAt']),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text('¥ ${money(record['amount'])}'),
                ),
            ],
          );
        },
      ),
    );
  }
}
