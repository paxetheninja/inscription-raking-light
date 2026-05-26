import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/image_ops/morphology_cv.dart';
import '../../core/image_ops/photometric_stereo.dart';
import '../../core/image_ops/preview_loader.dart';
import '../../core/image_ops/registration.dart';
import '../../core/image_ops/registration_orb.dart';
import '../../core/image_ops/stack_reductions.dart';
import '../../core/session/session_providers.dart';
import 'results_gallery.dart';

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
          trailing: PopupMenuButton<String>(
            tooltip: 'Session actions',
            onSelected: (v) async {
              switch (v) {
                case 'rename':
                  final newLabel = await _promptRename(context, title);
                  if (newLabel != null && newLabel.isNotEmpty) {
                    await store.renameLabel(sessionId, newLabel);
                    ref.invalidate(sessionListProvider);
                  }
                case 'delete':
                  final ok = await _confirmDelete(context, title);
                  if (ok == true) {
                    await store.deleteSession(sessionId);
                    ref.invalidate(sessionListProvider);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename label')),
              PopupMenuItem(value: 'delete', child: Text('Delete session')),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SessionDetailScreen(
                sessionId: sessionId,
                label: title,
              ),
            ));
          },
        );
      },
    );
  }
}

Future<String?> _promptRename(BuildContext context, String current) {
  final ctrl = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename session'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Label'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmDelete(BuildContext context, String title) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete session?'),
      content: Text(
          'This permanently deletes "$title" and all of its frames + previews. '
          'There is no undo.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
              foregroundColor: const Color(0xFFB00020)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    this.label,
  });

  final String sessionId;
  final String? label;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  bool _busy = false;
  String? _status;
  String? _error;
  StackPipelineOutput? _pipeline;
  RegistrationMode _registrationMode = RegistrationMode.fast;

  Future<void> _compute() async {
    final store = ref.read(sessionStoreProvider);
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Loading frames…';
      _pipeline = null;
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

      // Build per-frame light vectors from sidecar metadata, if every frame
      // has both an azimuth and an elevation set. Anything less is treated
      // as "no lights" — the pipeline records why the normal map is absent.
      final sc = await store.readSidecar(widget.sessionId);
      List<LightVec>? lights;
      if (sc != null && sc.frames.length == previews.length) {
        final maybe = <LightVec>[];
        var allSet = true;
        for (final f in sc.frames) {
          final az = f.lightAzimuthDeg;
          final el = f.lightElevationDeg;
          if (az == null || el == null) {
            allSet = false;
            break;
          }
          maybe.add(LightVec.fromCompass(az, el));
        }
        if (allSet) lights = maybe;
      }

      // For ORB we compute the transforms on the main isolate via
      // opencv_dart (its FFI handles aren't safe to send across isolate
      // boundaries) and pass the resulting transforms into the worker.
      // If the native ORB symbol fails to resolve (some opencv_dart
      // platform binaries ship without cv_ORB_create_1 etc.), we fall back
      // to the pure-Dart Accurate mode and tell the user.
      var effectiveMode = _registrationMode;
      List<FrameTransform>? preTransforms;
      List<double>? preScores;
      if (_registrationMode == RegistrationMode.orb) {
        setState(() => _status = 'Running ORB feature matching on '
            '${previews.length} frames…');
        try {
          final frameBytes = previews.map((p) => p.bytes).toList();
          final (t, s) = computeOrbTransforms(frameBytes, w, h);
          preTransforms = t;
          preScores = s;
        } catch (e) {
          effectiveMode = RegistrationMode.accurate;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(
                'ORB unavailable on this device — falling back to Accurate. '
                'Details: $e',
              )),
            );
          }
        }
      }

      final modeLabel = switch (effectiveMode) {
        RegistrationMode.none => 'no alignment',
        RegistrationMode.fast => 'fast alignment',
        RegistrationMode.accurate => 'accurate alignment',
        RegistrationMode.orb => 'ORB + RANSAC',
      };

      setState(() => _status = lights != null
          ? 'Aligning ($modeLabel) + reductions + fusion + CLAHE + Retinex + normal map…'
          : 'Aligning ($modeLabel) + reductions + fusion + CLAHE + Retinex…');
      final result = await runStackPipeline(StackInput(
        width: w,
        height: h,
        frames: previews.map((p) => p.bytes).toList(),
        lights: lights,
        registrationMode: effectiveMode,
        precomputedTransforms: preTransforms,
        precomputedScores: preScores,
      ));

      // Black hat morphology runs on the main isolate (opencv_dart FFI
      // handles can't cross isolate boundaries) using the fusion image.
      setState(() => _status = 'Computing black hat morphology…');
      var pipelineWithExtras = result;
      try {
        final bh = computeBlackHat(result.fusion, result.width, result.height);
        pipelineWithExtras = result.withBlackHat(bh);
      } catch (e) {
        // Black hat is a bonus; fail soft.
        debugPrint('Black hat failed: $e');
      }

      setState(() {
        _pipeline = pipelineWithExtras;
        _status = 'Saving previews…';
      });
      await _persistPreviews(pipelineWithExtras);
      await store.updateRegistration(widget.sessionId, result.registration);
      final rect = result.registration.validRect;
      final cropped = rect.width != w || rect.height != h;
      setState(() {
        _status = 'Done · ${frames.length} frames · ${result.width}×${result.height}'
            '${cropped ? " (cropped from $w×$h)" : ""}.';
      });
      if (mounted) _openGallery();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openGallery() {
    final p = _pipeline;
    if (p == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsGalleryScreen(
        headerSubtitle: widget.label ?? widget.sessionId,
        pipeline: p,
      ),
    ));
  }

  Future<void> _persistPreviews(StackPipelineOutput pipe) async {
    final store = ref.read(sessionStoreProvider);
    final r = pipe.reductions;
    final w = pipe.width;
    final h = pipe.height;
    final entries = <(String, List<int>)>[
      ('fusion-clahe.png', grayToPng(pipe.fusionClahe, w, h)),
      ('fusion-retinex.png', grayToPng(pipe.fusionRetinex, w, h)),
      ('fusion.png', grayToPng(pipe.fusion, w, h)),
      ('combined-relief.png', grayToPng(pipe.combinedRelief, w, h)),
      ('multiscale-dog.png', grayToPng(pipe.multiscaleDog, w, h)),
      ('range.png', grayToPng(r.rangeImg, r.width, r.height)),
      ('stddev.png', grayToPng(r.stddevImg, r.width, r.height)),
      ('max.png', grayToPng(r.maxImg, r.width, r.height)),
      ('min.png', grayToPng(r.minImg, r.width, r.height)),
    ];
    for (var i = 0; i < pipe.pcaComponents.length; i++) {
      entries.add((
        'pca-pc${i + 1}.png',
        grayToPng(pipe.pcaComponents[i], w, h),
      ));
    }
    for (final (name, bytes) in entries) {
      await store.writePreview(widget.sessionId, name, bytes);
    }
    if (pipe.normalMap != null) {
      await store.writePreview(
        widget.sessionId,
        'normal-map.png',
        rgbToPng(pipe.normalMap!, w, h),
      );
    }
    if (pipe.blackHat != null) {
      await store.writePreview(
        widget.sessionId,
        'black-hat.png',
        grayToPng(pipe.blackHat!, w, h),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label ?? widget.sessionId),
        bottom: widget.label != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.sessionId,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RegistrationSelector(
              value: _registrationMode,
              onChanged: _busy
                  ? null
                  : (m) => setState(() => _registrationMode = m),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _compute,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(_busy ? 'Working…' : 'Compute reductions'),
            ),
            if (_pipeline != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _openGallery,
                icon: const Icon(Icons.collections),
                label: const Text('Open results gallery'),
              ),
            ],
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
            Expanded(child: _FrameList(sessionId: widget.sessionId)),
          ],
        ),
      ),
    );
  }
}

class _RegistrationSelector extends StatelessWidget {
  const _RegistrationSelector({required this.value, required this.onChanged});

  final RegistrationMode value;
  final ValueChanged<RegistrationMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.compare_arrows, size: 18),
        const SizedBox(width: 6),
        Text('align:', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<RegistrationMode>(
            value: value,
            isExpanded: true,
            isDense: true,
            onChanged: onChanged == null
                ? null
                : (v) {
                    if (v != null) onChanged!(v);
                  },
            items: const [
              DropdownMenuItem(
                value: RegistrationMode.none,
                child: Text('None — assume aligned'),
              ),
              DropdownMenuItem(
                value: RegistrationMode.fast,
                child: Text('Fast — NCC translation (2-DoF)'),
              ),
              DropdownMenuItem(
                value: RegistrationMode.accurate,
                child: Text('Accurate — NCC + rot/scale (4-DoF)'),
              ),
              DropdownMenuItem(
                value: RegistrationMode.orb,
                child: Text('ORB + RANSAC — feature matching (OpenCV)'),
              ),
            ],
          ),
        ),
      ],
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

