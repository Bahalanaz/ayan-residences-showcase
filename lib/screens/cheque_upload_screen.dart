import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../admin/admin_state.dart';
import '../admin/screens/cheques_screen.dart' show ChequesScreen;
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/chat_view.dart' show choosePhoto;
import '../widgets/common.dart';
import 'home_screen.dart' show push;
import 'shell.dart';

/// Villa tenants pay with cheques. Here they pick which cheque, take or
/// choose a photo of it, and send it; management then checks the photo and
/// marks the cheque deposited, cleared or bounced.
class ChequeUploadScreen extends StatefulWidget {
  const ChequeUploadScreen({super.key});
  @override
  State<ChequeUploadScreen> createState() => _ChequeUploadScreenState();
}

class _ChequeUploadScreenState extends State<ChequeUploadScreen> {
  /// The cheque picked; null with [_other] false means "the first one".
  ChequeRec? _picked;

  /// "Another cheque": one that is not on the list yet.
  bool _other = false;
  Uint8List? _photo;

  String get _me => appState.currentTenant;

  Future<void> _pickPhoto() async {
    final bytes = await choosePhoto(context);
    if (bytes != null && mounted) setState(() => _photo = bytes);
  }

  void _send(ChequeRec? target) {
    final c = adminState.uploadChequePhoto(_me, _photo!, to: target);
    setState(() {
      _photo = null;
      _picked = null;
      _other = false;
    });
    toast(context,
        'Photo sent for the ${peso(c.amount, dhs: true)} cheque. Management will check it.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final needed = adminState.chequesNeedingPhoto(_me);
        final target = _other
            ? null
            : (needed.contains(_picked) ? _picked : needed.firstOrNull);
        final sent = adminState
            .chequesFor(_me)
            .where((c) =>
                c.hasPhoto &&
                (c.status == ChequeStatus.held || c.status == ChequeStatus.deposited))
            .toList();
        return SubPage(
          title: 'Upload Cheques',
          bottom: GoldButton(
            label: 'Send cheque photo',
            icon: Icons.send_rounded,
            onPressed: _photo == null ? null : () => _send(target),
          ),
          children: [
            const Text(
                'Take a clear photo of the front of each cheque. Management checks it against your contract before it counts as paid.',
                style: TextStyle(color: AppColors.slate300, fontSize: 12.5, height: 1.4)),

            // 1. Which cheque
            const _Label('1', 'Which cheque is this?'),
            AppCard(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                for (final c in needed)
                  _Option(
                    title: peso(c.amount, dhs: true),
                    sub: c.kind == ChequeKind.deposit
                        ? 'Deposit cheque'
                        : 'Post-dated · banks on ${formatDate(c.date)}',
                    selected: !_other && target == c,
                    onTap: () => setState(() {
                      _picked = c;
                      _other = false;
                    }),
                  ),
                _Option(
                  title: 'Another cheque',
                  sub: needed.isEmpty
                      ? 'All your listed cheques have photos. Send a new one here.'
                      : 'Not on this list. Management will fill in the details.',
                  selected: _other || needed.isEmpty,
                  onTap: () => setState(() => _other = true),
                ),
              ]),
            ),

            // 2. The photo
            const _Label('2', 'Photo of the cheque'),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: _photo == null
                  ? InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickPhoto,
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: AppColors.slate50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.slate200),
                        ),
                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          IconBadge(Icons.add_a_photo_outlined, size: 52),
                          SizedBox(height: 10),
                          Text('Take or choose a photo',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green800)),
                          Text('Front of the cheque, flat and in good light',
                              style: TextStyle(fontSize: 12, color: AppColors.slate500)),
                        ]),
                      ),
                    )
                  : Column(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_photo!,
                            height: 190, width: double.infinity, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                                height: 190,
                                color: AppColors.slate100,
                                alignment: Alignment.center,
                                child: const Icon(Icons.image_outlined, color: AppColors.gold600))),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.check_circle, size: 18, color: AppColors.emerald),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text('Photo ready',
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.green800)),
                        ),
                        TextButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.gold700),
                          label: const Text('Change',
                              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.gold700)),
                        ),
                      ]),
                    ]),
            ),

            // What was already sent and is waiting.
            if (sent.isNotEmpty) ...[
              const _Label(null, 'Sent'),
              for (final c in sent)
                AppCard(
                  child: Row(children: [
                    const IconBadge(Icons.receipt_long_outlined, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(peso(c.amount, dhs: true),
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.green800)),
                        Text('Banks on ${formatDate(c.date)} · sent ${c.uploadedOn}',
                            style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                      ]),
                    ),
                    c.photoChecked ? Pill.verified('CHECKED') : Pill.pending('WAITING'),
                  ]),
                ),
            ],
            Center(
              child: TextButton(
                onPressed: () => push(context, ChequesScreen(_me)),
                child: const Text('See all my cheques',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.gold400)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.step, this.text);
  final String? step;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        if (step != null) ...[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(gradient: goldGradient, shape: BoxShape.circle),
            child: Text(step!,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.green900)),
          ),
          const SizedBox(width: 8),
        ],
        Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
      ]);
}

class _Option extends StatelessWidget {
  const _Option({required this.title, required this.sub, required this.selected, required this.onTap});
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: selected ? AppColors.gold500.withValues(alpha: .12) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.gold500 : AppColors.slate200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(selected ? Icons.check_circle : Icons.radio_button_off,
                  color: selected ? AppColors.gold600 : AppColors.slate300),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.green800)),
                  Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
