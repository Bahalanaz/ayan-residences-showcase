import 'package:flutter/material.dart';

import '../../screens/shell.dart' show SubPage;
import '../../state/backend.dart';
import '../../state/sync.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart' show formatDate;

/// How full the file storage is (photos, IDs, contracts...), what is cleaned
/// up automatically, and a button to clean up now.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  bool _busy = false;
  String? _error;

  static const _areas = {
    'tenant-documents': 'Tenant IDs and clearances',
    'payment-proofs': 'Payment receipts',
    'cheque-photos': 'Cheque photos',
    'contracts': 'Contracts',
    'chat-files': 'Chat photos, files and signed papers',
    'report-photos': 'Report photos',
    'guest-files': 'Condo guest files',
    'public-assets': 'Unit photos and QR codes',
  };

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    if (!backendOn) return;
    try {
      await Sync.readStorage();
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the storage. Check your internet connection.',
        );
      }
    }
  }

  Future<void> _cleanNow() async {
    setState(() => _busy = true);
    try {
      final removed = await Sync.cleanUp(force: true);
      await Sync.readStorage();
      if (removed > 0) await Sync.load();
      if (mounted) {
        toast(
          context,
          removed == 0
              ? 'Nothing old enough to remove.'
              : 'Removed $removed old items.',
        );
      }
    } catch (_) {
      if (mounted) {
        toast(context, 'Could not clean up. Check your internet connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).ceil()} KB';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StorageReport?>(
      valueListenable: Sync.storage,
      builder: (context, r, _) {
        final full = r?.fraction ?? 0;
        final warn = full >= .8;
        return SubPage(
          title: 'Storage & cleanup',
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'File storage',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!backendOn)
                    const Text(
                      'Storage is measured in the live app only.',
                      style: TextStyle(fontSize: 13, color: AppColors.slate500),
                    )
                  else if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.red,
                      ),
                    )
                  else if (r == null)
                    const LinearProgressIndicator()
                  else ...[
                    Text(
                      '${_size(r.usedBytes)} of ${_size(r.limitBytes)} used',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: warn ? AppColors.red : AppColors.green800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: full,
                        minHeight: 10,
                        backgroundColor: AppColors.slate100,
                        color: warn ? AppColors.red : AppColors.emerald,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      warn
                          ? '${(full * 100).round()}% full. Time to move to the Pro plan, or clean up.'
                          : '${(full * 100).round()}% full.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: warn ? AppColors.red : AppColors.slate500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (r != null && r.byArea.isNotEmpty)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What uses it',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final e
                        in (r.byArea.entries.toList()
                          ..sort((a, b) => b.value.$1.compareTo(a.value.$1))))
                      KeyValueRow(
                        _areas[e.key] ?? e.key,
                        '${_size(e.value.$1)} · ${e.value.$2} files',
                      ),
                  ],
                ),
              ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cleaned up automatically',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final line in const [
                    'Condo guest files: 90 days after check-out',
                    'Chat photos: after 1 year (the message text stays)',
                    'Former tenants: IDs, clearances, cheque photos and receipts 2 years after move-out (contracts and signed papers are kept)',
                    'Activity log: entries older than 2 years',
                    'Leftover files nothing points to any more (a removed or replaced photo or PDF)',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.auto_delete_outlined,
                              size: 16,
                              color: AppColors.gold600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.slate600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Runs once a day when the admin app opens. Last run: '
                    '${r?.lastCleanup == null ? 'not yet' : formatDate(r!.lastCleanup!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate400,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GoldButton(
                    label: _busy ? 'Cleaning up…' : 'Clean up now',
                    icon: Icons.cleaning_services_outlined,
                    onPressed: _busy || !backendOn ? null : _cleanNow,
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
