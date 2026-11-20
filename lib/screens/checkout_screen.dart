import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// A way to pay online through the payment gateway (Xendit or similar).
class PayMethod {
  const PayMethod(this.id, this.name, this.sub, this.icon, this.percent, this.minFee,
      {this.fixedFee = 0, this.recommended = false});
  final String id, name, sub;
  final IconData icon;

  /// Estimated gateway fee: percent of the amount plus a fixed part, never
  /// below [minFee]. Demo rates; confirm on the provider's pricing page.
  final double percent, minFee, fixedFee;
  final bool recommended;

  double feeFor(double amount) => max(minFee, amount * percent / 100 + fixedFee);
}

const payMethods = [
  PayMethod('qrph', 'QR Ph', 'Scan with any bank or e-wallet app', Icons.qr_code_2_rounded, 1.4, 15,
      recommended: true),
  PayMethod('gcash', 'GCash', 'Pay in the GCash app', Icons.account_balance_wallet_rounded, 2.3, 0),
  PayMethod('maya', 'Maya', 'Pay in the Maya app', Icons.account_balance_wallet_outlined, 2.0, 0),
  PayMethod('bank', 'Online banking', 'BDO, BPI, UnionBank and more', Icons.account_balance_rounded, 1.0, 25),
  PayMethod('card', 'Credit / debit card', 'Visa or Mastercard', Icons.credit_card_rounded, 3.2, 0,
      fixedFee: 10),
];

/// Result of a finished checkout.
class CheckoutResult {
  const CheckoutResult(this.reference, this.paidAt);
  final String reference;
  final DateTime paidAt;
}

/// Stand-in for the gateway's checkout page. In the real app the backend
/// creates the payment and this screen shows the gateway's page (or hands off
/// to the GCash / Maya / bank app); the gateway then tells the backend it was
/// paid. Here the "pay" step is simulated so the whole flow can be tried.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.method,
    required this.what,
    required this.amount,
    required this.fee,
  });
  final PayMethod method;
  final String what;
  final double amount, fee;

  double get total => amount + fee;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _waiting = false;

  Future<void> _pay() async {
    setState(() => _waiting = true);
    // The real app waits for the gateway's confirmation here.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    final now = DateTime.now();
    final ref = 'XND-${now.millisecondsSinceEpoch.toString().substring(5)}';
    popOnce(context, CheckoutResult(ref, now));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.method;
    return PopScope(
      canPop: !_waiting,
      child: Scaffold(
        backgroundColor: AppColors.slate50,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.green800,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Cancel payment',
            onPressed: _waiting ? null : () => popOnce(context),
            icon: const Icon(Icons.close),
          ),
          title: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_rounded, size: 16, color: AppColors.emerald),
            SizedBox(width: 6),
            Text('Secure checkout',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  // Merchant + amount
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.green800,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(children: [
                      const Text('Ayan Residences',
                          style: TextStyle(
                              color: AppColors.gold400, fontSize: 13, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(widget.what,
                          style: const TextStyle(color: AppColors.slate300, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      Text(peso(widget.total),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                      if (widget.fee > 0)
                        Text('includes ${peso(widget.fee)} processing fee',
                            style: const TextStyle(color: AppColors.slate300, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  AppCard(
                    child: Column(children: [
                      Row(children: [
                        IconBadge(m.icon, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.name,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.green800)),
                            Text(m.sub,
                                style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      ..._methodBody(m),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  GoldButton(
                    label: _waiting ? 'Waiting for confirmation…' : _action(m),
                    icon: _waiting ? null : Icons.lock_rounded,
                    onPressed: _waiting ? null : _pay,
                  ),
                  if (_waiting) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.gold600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Demo checkout. In the live app this page comes from the payment provider and nothing is charged here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppColors.slate400),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _action(PayMethod m) => switch (m.id) {
        'qrph' => "I've paid",
        'gcash' => 'Continue to GCash',
        'maya' => 'Continue to Maya',
        'bank' => 'Continue to your bank',
        _ => 'Pay ${peso(widget.total)}',
      };

  List<Widget> _methodBody(PayMethod m) {
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(gradient: goldGradient, shape: BoxShape.circle),
              child: Text('$n',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.green900)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.slate600)),
            ),
          ]),
        );
    switch (m.id) {
      case 'qrph':
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate200),
            ),
            child: const SizedBox(width: 190, height: 190, child: CustomPaint(painter: _FakeQr())),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => toast(context, 'QR code saved to your photos (demo)'),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Save QR to photos'),
          ),
          const SizedBox(height: 4),
          step(1, 'Open your bank or e-wallet app and choose Scan QR / QR Ph.'),
          step(2, 'Scan this code, or upload the saved image from your photos.'),
          step(3, 'Confirm the payment. This page updates by itself once it goes through.'),
        ];
      case 'card':
        return [
          step(1, 'Enter your card details on the provider\'s secure page.'),
          step(2, 'Approve the one-time PIN (OTP) your bank sends you.'),
          const SizedBox(height: 4),
          const Text('Card details never pass through Ayan Residences.',
              style: TextStyle(fontSize: 12, color: AppColors.slate500)),
        ];
      case 'bank':
        return [
          step(1, 'Choose your bank and log in to its online banking.'),
          step(2, 'Approve the payment. You come back here automatically.'),
        ];
      default:
        return [
          step(1, 'The ${m.name} app opens with the amount filled in.'),
          step(2, 'Enter your MPIN and confirm.'),
          step(3, 'You come back here automatically when it\'s done.'),
        ];
    }
  }
}

/// A QR-looking pattern for the demo (not a real, scannable code).
class _FakeQr extends CustomPainter {
  const _FakeQr();

  @override
  void paint(Canvas canvas, Size size) {
    const n = 25;
    final cell = size.width / n;
    final dark = Paint()..color = AppColors.green900;
    final rnd = Random(42);
    bool finder(int x, int y) =>
        (x < 7 && y < 7) || (x >= n - 7 && y < 7) || (x < 7 && y >= n - 7);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (finder(x, y)) continue;
        if (rnd.nextBool()) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), dark);
      }
    }
    void eye(double ox, double oy) {
      final o = Offset(ox * cell, oy * cell);
      canvas.drawRect(o & Size(7 * cell, 7 * cell), dark);
      canvas.drawRect((o + Offset(cell, cell)) & Size(5 * cell, 5 * cell), Paint()..color = Colors.white);
      canvas.drawRect((o + Offset(2 * cell, 2 * cell)) & Size(3 * cell, 3 * cell), dark);
    }

    eye(0, 0);
    eye(n - 7, 0);
    eye(0, n - 7);
  }

  @override
  bool shouldRepaint(_FakeQr old) => false;
}

/// Shown after a successful online payment.
class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.what,
    required this.method,
    required this.amount,
    required this.fee,
    required this.result,
  });
  final String what, method;
  final double amount, fee;
  final CheckoutResult result;

  @override
  Widget build(BuildContext context) {
    final d = result.paidAt;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final when =
        '${months[d.month - 1]} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
              children: [
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutBack,
                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: const BoxDecoration(gradient: goldGradient, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, size: 48, color: AppColors.green900),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Payment successful',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Confirmed by the payment provider. No need to upload a receipt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.slate300)),
                const SizedBox(height: 22),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(children: [
                    KeyValueRow('Paid for', what),
                    KeyValueRow('Amount', peso(amount)),
                    if (fee > 0) KeyValueRow('Processing fee', peso(fee)),
                    KeyValueRow('Total paid', peso(amount + fee)),
                    KeyValueRow('Method', method),
                    KeyValueRow('Date', when),
                    Row(children: [
                      Expanded(child: KeyValueRow('Reference', result.reference, last: true)),
                      IconButton(
                        tooltip: 'Copy reference',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: result.reference));
                          toast(context, 'Reference copied');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.slate400),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 18),
                GoldButton(label: 'Done', onPressed: () => popOnce(context)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => toast(context, 'Receipt download comes with the backend'),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.gold400),
                  label: const Text('Download receipt',
                      style: TextStyle(color: AppColors.gold400, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
