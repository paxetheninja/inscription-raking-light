import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/export/session_archiver.dart';
import '../../core/session/session_providers.dart';

/// Export tab: lists every session on disk with size + frame count.
///
/// **Tap** a tile to share that session's `.zip`. **Long-press** any tile to
/// enter multi-select mode — tapping additional tiles toggles them, the
/// bottom bar shows the current selection count, and "Share zips" bundles
/// all selected sessions into one combined zip suitable for the desktop
/// pipeline.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  final Set<String> _selected = {};
  bool _bundling = false;

  bool get _selectMode => _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<String> ids) {
    setState(() => _selected.addAll(ids));
  }

  void _clear() {
    setState(_selected.clear);
  }

  Future<void> _shareSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _bundling = true);
    try {
      final store = ref.read(sessionStoreProvider);
      final ids = _selected.toList();
      final zip = await SessionArchiver(store).zipMultipleSessions(ids);
      await Share.shareXFiles(
        [XFile(zip.path, name: zip.path.split(RegExp(r'[\\/]')).last)],
        subject: 'Raking-light export: ${ids.length} session(s)',
        text:
            'Bundle of ${ids.length} inscription raking-light sessions.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bundled export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _bundling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(sessionListProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Each session bundles `raw/`, `preview/`, and `sidecar.json` '
            'into a `.zip` the desktop pipeline can consume. Long-press to '
            'select multiple — they\'re combined into one zip.',
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
                        itemBuilder: (_, i) => _ExportTile(
                          sessionId: ids[i],
                          selectMode: _selectMode,
                          selected: _selected.contains(ids[i]),
                          onToggle: () => _toggle(ids[i]),
                        ),
                      ),
                    ),
            ),
          ),
          if (_selectMode)
            _SelectionBar(
              count: _selected.length,
              busy: _bundling,
              onClear: _clear,
              onSelectAll: list.maybeWhen(
                data: (ids) =>
                    ids.length > _selected.length ? () => _selectAll(ids) : null,
                orElse: () => null,
              ),
              onShare: _bundling ? null : _shareSelected,
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

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onClear,
    required this.onSelectAll,
    required this.onShare,
  });

  final int count;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback? onSelectAll;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Clear selection',
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
            Text(
              '$count selected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            if (onSelectAll != null)
              TextButton.icon(
                onPressed: onSelectAll,
                icon: const Icon(Icons.select_all),
                label: const Text('All'),
              ),
            FilledButton.icon(
              onPressed: onShare,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share),
              label: Text(busy ? 'Bundling…' : 'Share zip'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportTile extends ConsumerStatefulWidget {
  const _ExportTile({
    required this.sessionId,
    required this.selectMode,
    required this.selected,
    required this.onToggle,
  });

  final String sessionId;
  final bool selectMode;
  final bool selected;
  final VoidCallback onToggle;

  @override
  ConsumerState<_ExportTile> createState() => _ExportTileState();
}

class _ExportTileState extends ConsumerState<_ExportTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(sessionStoreProvider);
    return FutureBuilder(
      future: Future.wait([
        store.readSidecar(widget.sessionId),
        store.sessionByteSize(widget.sessionId),
      ]),
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
          leading: widget.selectMode
              ? Icon(
                  widget.selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: widget.selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                )
              : const Icon(Icons.archive_outlined),
          title: Text(title),
          subtitle: Text(
            '$frames frames · ${_humanSize(bytes)}'
            '${calibrated ? ' · calibrated' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.selectMode
              ? null
              : (_busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Share zip',
                      icon: const Icon(Icons.ios_share),
                      onPressed: () => _shareZip(title),
                    )),
          selected: widget.selectMode && widget.selected,
          onTap: widget.selectMode ? widget.onToggle : null,
          onLongPress: widget.onToggle,
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
