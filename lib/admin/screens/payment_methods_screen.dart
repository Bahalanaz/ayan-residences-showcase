import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../screens/payments_screen.dart' show payAccountIcon;
import '../../screens/shell.dart' show SubPage;
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/chat_view.dart' show choosePhoto;
import '../../widgets/common.dart';

/// The GCash, Maya and bank accounts tenants send rent to. What is listed here
/// is exactly what tenants see under Payment Details.
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final list = appState.payAccounts;
        return SubPage(
          title: 'Payment methods',
          bottom: GoldButton(
            label: 'Add payment method',
            icon: Icons.add,
            onPressed: () => showAppSheet(
              context,
              title: 'Add payment method',
              builder: (_) => const _AccountForm(null),
            ),
          ),
          children: [
            const Text(
              'Tenants see these under Payment Details when they pay outside the app, and on their payment history.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.slate300,
              ),
            ),
            if (list.isEmpty)
              const EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No payment methods yet',
                message: 'Add the GCash, Maya or bank account tenants should send rent to.',
              ),
            for (final a in list)
              AppCard(
                radius: 20,
                onTap: () => showAppSheet(
                  context,
                  title: 'Edit payment method',
                  builder: (_) => _AccountForm(a),
                ),
                child: Row(
                  children: [
                    IconBadge(payAccountIcon(a), size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800,
                            ),
                          ),
                          Text(
                            a.accountName,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.slate500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            a.qr == null
                                ? a.number
                                : '${a.number}  ·  QR code added',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.gold700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: AppColors.slate400,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AccountForm extends StatefulWidget {
  const _AccountForm(this.account);

  /// Null when adding a new one.
  final PayAccount? account;
  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  static const _types = ['GCash', 'Maya', 'Bank', 'Other'];

  final _key = GlobalKey<FormState>();
  late String _type = widget.account?.type ?? 'GCash';
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _holder = TextEditingController(
    text: widget.account?.accountName ?? '',
  );
  late final _number = TextEditingController(
    text: widget.account?.number ?? '',
  );
  late Uint8List? _qr = widget.account?.qr;

  @override
  void dispose() {
    _name.dispose();
    _holder.dispose();
    _number.dispose();
    super.dispose();
  }

  bool get _wallet => _type == 'GCash' || _type == 'Maya';

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Type'),
          DropdownField(
            value: _type,
            items: _types,
            onChanged: (v) => setState(() {
              _type = v;
              // GCash and Maya are named after themselves.
              if (_wallet) _name.text = v;
            }),
          ),
          if (!_wallet) ...[
            const SizedBox(height: 12),
            const FieldLabel('Bank or wallet name'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. BDO Unibank, BPI, UnionBank',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the name' : null,
            ),
          ],
          const SizedBox(height: 12),
          const FieldLabel('Account name'),
          TextFormField(
            controller: _holder,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Who the account is registered to',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter the account name' : null,
          ),
          const SizedBox(height: 12),
          FieldLabel(_wallet ? '$_type number' : 'Account number'),
          TextFormField(
            controller: _number,
            keyboardType: TextInputType.phone,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter the number' : null,
          ),
          const SizedBox(height: 12),
          // GCash and banks give a QR code; tenants can scan or save it.
          const FieldLabel('QR code (optional)'),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final bytes = await choosePhoto(context);
              if (bytes != null && mounted) setState(() => _qr = bytes);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Row(
                children: [
                  if (_qr == null)
                    const IconBadge(Icons.qr_code_2_rounded, size: 56)
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _qr!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const IconBadge(Icons.qr_code_2_rounded, size: 56),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _qr == null ? 'Upload the QR code' : 'QR code added',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                        Text(
                          _qr == null
                              ? 'A screenshot or photo of it'
                              : 'Tap to change it',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_qr != null)
                    IconButton(
                      tooltip: 'Remove QR code',
                      onPressed: () => setState(() => _qr = null),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.slate400,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: a == null ? 'Add payment method' : 'Save changes',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              appState.savePayAccount(
                a,
                PayAccount(
                  type: _type,
                  name: _wallet ? _type : _name.text.trim(),
                  accountName: _holder.text.trim(),
                  number: _number.text.trim(),
                  qr: _qr,
                ),
              );
              popOnce(context);
              toast(
                context,
                a == null ? 'Payment method added' : 'Payment method updated',
              );
            },
          ),
          if (a != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  appState.deletePayAccount(a);
                  popOnce(context);
                  toast(context, 'Payment method removed');
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.red,
                ),
                label: const Text(
                  'Remove this payment method',
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
