import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/image_ops/preview_loader.dart';
import '../../core/image_ops/stack_reductions.dart';
import '../../core/session/session_providers.dart';

class StackScreen extends ConsumerWidget {
  const StackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(sessionListProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stack', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Pick a session to compute per-pixel reductions (downsampled preview).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ids.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (list) {
                if (list.isEmpty) {
                  return const _Empty();
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(sessionListProvider);
                    await ref.read(sessionListProvider.future);
                  },
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _SessionTile(sessionId: list[i]),
                  ),
                );
              },
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
          'No sessions yet. Capture a burst on the Capture tab to get started.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(sessionStoreProvider);
    return FutureBuilder(
      future: store.readSidecar(sessionId),
      builder: (ctx, snap) {
        final sub = snap.hasData && snap.data != null
            ? '${snap.data!.frames.length} frames · ${snap.data!.capturedAt}'
            : sessionId;
        final title = snap.hasData && snap.data != null && snap.data!.label.isNotEmpty
            ? snap.data!.label
            : sessionId;
        return ListTile(
          leading: const Icon(Icons.collections_outlined),
          title: Text(title),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SessionDetailScreen(sessionId: sessionId),
            ));
          },
        );
      },
    );
  }
}

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  bool _busy = false;
  String? _status;
  String? _error;
  StackReductions? _reductions;

  Future<void> _compute() async {
    final store = ref.read(sessionStoreProvider);
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Loading frames…';
      _reductions = null;
    });
    try {
      final frames = await store.listFrames(widget.sessionId);
      if (frames.length < 2) {
        throw StateError(
            'Need at least 2 frames to compute reductions (found ${frames.length}).');
      }

      final previews = <GrayPreview>[];
      for (var i = 0; i < frames.length; i++) {
        setState(() => _status = 'Loading frame ${i + 1}/${frames.length}…');
        previews.add(await loadGrayPreview(frames[i].path));
      }

      final w = previews.first.width;
      final h = previews.first.height;
      for (final p in previews.skip(1)) {
        if (p.width != w || p.height != h) {
          throw StateError(
              'Frame sizes differ (${p.width}x${p.height} vs ${w}x$h). '
              'Lock the framing and try again.');
        }
      }

      setState(() => _status = 'Computing reductions…');
      final result = await computeStackReductions(StackInput(
        width: w,
        height: h,
        frames: previews.map((p) => p.bytes).toList(),
      ));

      setState(() {
        _reductions = result;
        _status = 'Done (${frames.length} frames, $w×$h).';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Session ${widget.sessionId}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _compute,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(_busy ? 'Working…' : 'Compute reductions'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(_status!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _reductions == null
                  ? _FrameList(sessionId: widget.sessionId)
                  : _ReductionsGrid(reductions: _reductions!),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameList extends ConsumerWidget {
  const _FrameList({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(sessionStoreProvider);
    return FutureBuilder<List<File>>(
      future: store.listFrames(sessionId),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final files = snap.data!;
        if (files.isEmpty) {
          return const Center(child: Text('No frames in this session yet.'));
        }
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: files.length,
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(files[i], fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

class _ReductionsGrid extends StatelessWidget {
  const _ReductionsGrid({required this.reductions});

  final StackReductions reductions;

  @override
  Widget build(BuildContext context) {
    final r = reductions;
    final items = <(String, Uint8List)>[
      ('max', grayToPng(r.maxImg, r.width, r.height)),
      ('min', grayToPng(r.minImg, r.width, r.height)),
      ('range', grayToPng(r.rangeImg, r.width, r.height)),
      ('stddev', grayToPng(r.stddevImg, r.width, r.height)),
    ];
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items
          .map((e) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(e.$2, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(child: Text(e.$1)),
                ],
              ))
          .toList(),
    );
  }
}
