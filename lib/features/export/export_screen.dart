import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/export/session_archiver.dart';
import '../../core/session/session_providers.dart';

/// Export tab: lists every session on disk with size + frame count and a
/// "Share zip" action that bundles `raw/`, `preview/`, and `sidecar.json`
/// into a temp .zip and opens the OS share sheet.
class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(sessionListProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Export', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Each session bundles `raw/` (original captures), `preview/` '
            '(computed enhancement PNGs), and `sidecar.json` into a single '
            'zip that the desktop pipeline can consume.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (ids) => ids.isEmpty
                  ? const _Empty()
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(sessionListProvider);
                        await ref.read(sessionListProvider.future);
                      },
                      child: ListView.separated(
                        itemCount: ids.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) =>
                            _ExportTile(sessionId: ids[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No sessions yet. Capture a burst on the Capture tab first.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ExportTile extends ConsumerStatefulWidget {
  const _ExportTile({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_ExportTile> createState() => _ExportTileState();
}

class _ExportTileState extends ConsumerState<_ExportTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(sessionStoreProvider);
    return FutureBuilder(
      future:
          Future.wait([store.readSidecar(widget.sessionId), store.sessionByteSize(widget.sessionId)]),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return ListTile(
            title: Text(widget.sessionId),
            trailing: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final sc = snap.data![0] as dynamic;
        final bytes = snap.data![1] as int;
        final title = (sc?.label as String? ?? '').isNotEmpty
            ? sc!.label as String
            : widget.sessionId;
        final frames = (sc?.frames as List?)?.length ?? 0;
        final calibrated = sc?.scaleMmPerPixel != null;
        return ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(title),
          subtitle: Text(
            '$frames frames · ${_humanSize(bytes)}'
            '${calibrated ? ' · calibrated' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Share zip',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _shareZip(title),
                ),
        );
      },
    );
  }

  Future<void> _shareZip(String title) async {
    setState(() => _busy = true);
    try {
      final store = ref.read(sessionStoreProvider);
      final zip = await SessionArchiver(store).zipSession(widget.sessionId);
      await Share.shareXFiles(
        [XFile(zip.path, name: '${widget.sessionId}.zip')],
        subject: 'Raking-light session: $title',
        text: 'Inscription raking-light session export.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
