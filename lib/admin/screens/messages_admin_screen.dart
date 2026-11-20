import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/shell.dart' show SubPage;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

class MessagesAdminScreen extends StatelessWidget {
  const MessagesAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) => SubPage(
        title: 'Messages',
        children: [
          for (final m in adminState.messages)
            AppCard(
              radius: 18,
              onTap: () => push(context, _ThreadScreen(m)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${m.tenant} · ${m.unit}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                      ),
                      Text(
                        m.date,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    m.category,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.slate600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  m.reply == null
                      ? Pill.pending('Needs reply')
                      : Pill.verified('Replied'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThreadScreen extends StatefulWidget {
  const _ThreadScreen(this.m);
  final AdminMessage m;
  @override
  State<_ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<_ThreadScreen> {
  late final _reply = TextEditingController(text: widget.m.reply ?? '');

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return SubPage(
      title: m.tenant,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m.category} · ${m.date}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gold700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                m.body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.green800,
                ),
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('Your reply (private to this tenant)'),
              TextField(controller: _reply, maxLines: 4),
              const SizedBox(height: 14),
              GoldButton(
                label: 'Send reply',
                icon: Icons.send_rounded,
                onPressed: () {
                  if (_reply.text.trim().isEmpty) return;
                  adminState.reply(m, _reply.text.trim());
                  popOnce(context);
                  toast(context, 'Reply sent');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
