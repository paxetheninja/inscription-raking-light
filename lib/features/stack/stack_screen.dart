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
import '../../core/settings/settings_providers.dart';
import '../../core/sidecar/sidecar_schema.dart';
import 'results_gallery.dart';

class StackScreen extends ConsumerStatefulWidget {
  const StackScreen({super.key});

  @override
  ConsumerState<StackScreen> createState() => _StackScreenState();
}

class _StackScreenState extends ConsumerState<StackScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _calibratedOnly = false;
  bool _withNotesOnly = false;
  bool _withLocationOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesFilters(SidecarV1? sc) {
    if (sc == null) return false;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final inLabel = sc.label.toLowerCase().contains(q);
      final inNotes = (sc.notes ?? '').toLowerCase().contains(q);
      final inId = sc.sessionId.toLowerCase().contains(q);
      if (!inLabel && !inNotes && !inId) return false;
    }
    if (_calibratedOnly && sc.scaleMmPerPixel == null) return false;
    if (_withNotesOnly && (sc.notes ?? '').trim().isEmpty) return false;
    if (_withLocationOnly && sc.location == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final ids = ref.watch(sessionListProvider);
    final sidecars = ref.watch(sessionSidecarsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick a session to compute per-pixel reductions, fusion, '
            'PCA layers, normal map, and more.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search label, notes, or id',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                label: const Text('calibrated'),
                avatar: const Icon(Icons.straighten, size: 14),
                selected: _calibratedOnly,
                onSelected: (v) => setState(() => _calibratedOnly = v),
                visualDensity: VisualDensity.compact,
              ),
              FilterChip(
                label: const Text('has notes'),
                avatar: const Icon(Icons.sticky_note_2_outlined, size: 14),
                selected: _withNotesOnly,
                onSelected: (v) => setState(() => _withNotesOnly = v),
                visualDensity: VisualDensity.compact,
              ),
              FilterChip(
                label: const Text('has location'),
                avatar: const Icon(Icons.place_outlined, size: 14),
                selected: _withLocationOnly,
                onSelected: (v) => setState(() => _withLocationOnly = v),
                visualDensity: VisualDensity.compact,
              ),
            ],
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
                // Filter on top of the sidecars cache. While the sidecar
                // map is still loading, we render the unfiltered list so
                // the user never sees a stuck spinner just because filters
                // are inactive.
                final scMap = sidecars.value;
                final filtered = scMap == null
                    ? list
                    : list.where((id) => _matchesFilters(scMap[id])).toList();
                if (filtered.isEmpty) {
                  return _NoMatches(
                    hasQuery: _query.isNotEmpty ||
                        _calibratedOnly ||
                        _withNotesOnly ||
                        _withLocationOnly,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(sessionListProvider);
                    await ref.read(sessionListProvider.future);
                  },
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _SessionTile(sessionId: filtered[i]),
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

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.hasQuery});
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'No sessions match your search and filters.'
                  : 'No sessions yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
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
        final sc = snap.data;
        final framesAndDate = sc != null
            ? '${sc.frames.length} frames · ${sc.capturedAt}'
            : sessionId;
        final notes = sc?.notes;
        // Show the first line of notes (truncated) on a second subtitle row
        // so the tile carries real metadata, not just plumbing data.
        final firstNoteLine = (notes == null || notes.isEmpty)
            ? null
            : notes.split('\n').first.trim();
        final subtitle = firstNoteLine == null
            ? Text(framesAndDate,
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(framesAndDate,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          firstNoteLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
        final title = sc != null && sc.label.isNotEmpty
            ? sc.label
            : sessionId;
        return ListTile(
          leading: const Icon(Icons.collections_outlined),
          title: Text(title),
          subtitle: subtitle,
          isThreeLine: firstNoteLine != null,
          trailing: PopupMenuButton<String>(
            tooltip: 'Session actions',
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  final result = await _promptEditDetails(
                    context,
                    initialLabel: title,
                    initialNotes: sc?.notes ?? '',
                  );
                  if (result != null) {
                    await store.updateDetails(
                      sessionId,
                      label: result.label.isEmpty ? null : result.label,
                      notes: result.notes,
                    );
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
              PopupMenuItem(value: 'edit', child: Text('Edit details')),
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

class _EditDetailsResult {
  const _EditDetailsResult({required this.label, required this.notes});
  final String label;
  final String notes;
}

Future<_EditDetailsResult?> _promptEditDetails(
  BuildContext context, {
  required String initialLabel,
  required String initialNotes,
}) {
  final labelCtrl = TextEditingController(text: initialLabel);
  final notesCtrl = TextEditingController(text: initialNotes);
  return showDialog<_EditDetailsResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Label',
                helperText: 'Stone name, find no., ...',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes',
                helperText:
                    'Site, condition, light source, anything else worth '
                    'remembering — included in the sidecar.',
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(
            _EditDetailsResult(
              label: labelCtrl.text.trim(),
              notes: notesCtrl.text.trim(),
            ),
          ),
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
  RegistrationMode? _registrationMode;

  RegistrationMode get _effectiveRegMode =>
      _registrationMode ?? ref.read(settingsProvider).defaultRegistration;

  Future<void> _compute() async {
    final store = ref.read(sessionStoreProvider);
    final previewMaxEdge = ref.read(settingsProvider).previewMaxEdge;
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
        previews.add(
          await loadGrayPreview(frames[i].path, maxEdge: previewMaxEdge),
        );
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
      var effectiveMode = _effectiveRegMode;
      List<FrameTransform>? preTransforms;
      List<double>? preScores;
      if (_effectiveRegMode == RegistrationMode.orb) {
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
              value: _effectiveRegMode,
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

