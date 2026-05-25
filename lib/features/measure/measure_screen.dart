import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_providers.dart';

/// Two modes:
/// - Calibrate: tap two points on a ruler visible in the frame, enter the
///   real-world distance in mm, save `scale_mm_per_pixel` to the sidecar.
/// - Measure: tap two points, read the distance in mm using the saved scale.
class MeasureScreen extends ConsumerStatefulWidget {
  const MeasureScreen({super.key});

  @override
  ConsumerState<MeasureScreen> createState() => _MeasureScreenState();
}

enum _Mode { calibrate, measure }

class _MeasureScreenState extends ConsumerState<MeasureScreen> {
  String? _sessionId;
  File? _frame;
  Size? _imageSize;
  double? _scaleMmPerPx;

  _Mode _mode = _Mode.calibrate;
  Offset? _a;
  Offset? _b;

  @override
  Widget build(BuildContext context) {
    final sessionList = ref.watch(sessionListProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Measure', style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: 8),
          sessionList.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (ids) => _SessionDropdown(
              ids: ids,
              selected: _sessionId,
              onChanged: (id) => _selectSession(id),
            ),
          ),
          if (_sessionId == null) ...[
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Pick a session, then tap two points on the frame to calibrate or measure.',
              ),
            ),
            const Spacer(),
          ] else if (_frame == null || _imageSize == null) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const Spacer(),
          ] else ...[
            const SizedBox(height: 8),
            _ModeBar(
              mode: _mode,
              onModeChanged: (m) => setState(() => _mode = m),
              onClear: () => setState(() {
                _a = null;
                _b = null;
              }),
              scale: _scaleMmPerPx,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _FrameCanvas(
                frame: _frame!,
                imageSize: _imageSize!,
                a: _a,
                b: _b,
                onTap: _placeMarker,
              ),
            ),
            const SizedBox(height: 8),
            _ResultBar(
              mode: _mode,
              a: _a,
              b: _b,
              scaleMmPerPx: _scaleMmPerPx,
              onCalibrate: _onCalibrateConfirm,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectSession(String? id) async {
    setState(() {
      _sessionId = id;
      _frame = null;
      _imageSize = null;
      _scaleMmPerPx = null;
      _a = null;
      _b = null;
    });
    if (id == null) return;
    final store = ref.read(sessionStoreProvider);
    final sc = await store.readSidecar(id);
    final frames = await store.listFrames(id);
    if (!mounted) return;
    if (frames.isEmpty) {
      setState(() => _frame = null);
      return;
    }
    final size = await _loadImageSize(frames.first);
    if (!mounted) return;
    setState(() {
      _frame = frames.first;
      _imageSize = size;
      _scaleMmPerPx = sc?.scaleMmPerPixel;
    });
  }

  void _placeMarker(Offset imagePoint) {
    setState(() {
      if (_a == null) {
        _a = imagePoint;
      } else if (_b == null) {
        _b = imagePoint;
      } else {
        _a = imagePoint;
        _b = null;
      }
    });
  }

  Future<void> _onCalibrateConfirm() async {
    final a = _a;
    final b = _b;
    final id = _sessionId;
    if (a == null || b == null || id == null) return;
    final mm = await _promptDistanceMm();
    if (mm == null || mm <= 0) return;
    final pixDist = (b - a).distance;
    if (pixDist < 1) return;
    final mmPerPx = mm / pixDist;
    final store = ref.read(sessionStoreProvider);
    await store.updateScale(id, mmPerPx);
    if (!mounted) return;
    setState(() => _scaleMmPerPx = mmPerPx);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved scale: ${mmPerPx.toStringAsFixed(5)} mm/pixel')),
    );
  }

  Future<double?> _promptDistanceMm() async {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Real distance between markers'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'mm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

Future<Size> _loadImageSize(File file) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
}

class _SessionDropdown extends StatelessWidget {
  const _SessionDropdown({
    required this.ids,
    required this.selected,
    required this.onChanged,
  });

  final List<String> ids;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Session',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final id in ids)
          DropdownMenuItem(
            value: id,
            child: Text(id, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.onModeChanged,
    required this.onClear,
    required this.scale,
  });

  final _Mode mode;
  final ValueChanged<_Mode> onModeChanged;
  final VoidCallback onClear;
  final double? scale;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SegmentedButton<_Mode>(
          segments: const [
            ButtonSegment(value: _Mode.calibrate, label: Text('Calibrate')),
            ButtonSegment(value: _Mode.measure, label: Text('Measure')),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.refresh),
          label: const Text('Clear'),
        ),
        const Spacer(),
        if (scale != null)
          Chip(
            avatar: const Icon(Icons.straighten, size: 16),
            label: Text('${scale!.toStringAsFixed(5)} mm/px'),
          )
        else
          const Chip(label: Text('uncalibrated')),
      ],
    );
  }
}

class _FrameCanvas extends StatelessWidget {
  const _FrameCanvas({
    required this.frame,
    required this.imageSize,
    required this.a,
    required this.b,
    required this.onTap,
  });

  final File frame;
  final Size imageSize;
  final Offset? a;
  final Offset? b;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final scale = math.min(
          c.maxWidth / imageSize.width,
          c.maxHeight / imageSize.height,
        );
        final dispW = imageSize.width * scale;
        final dispH = imageSize.height * scale;
        return Center(
          child: SizedBox(
            width: dispW,
            height: dispH,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => onTap(d.localPosition / scale),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(frame, fit: BoxFit.fill),
                  CustomPaint(
                    painter: _MarkerPainter(scale: scale, a: a, b: b),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter({required this.scale, required this.a, required this.b});

  final double scale;
  final Offset? a;
  final Offset? b;

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = a == null ? null : a! * scale;
    final p2 = b == null ? null : b! * scale;
    final stroke = Paint()
      ..color = const Color(0xFFFFD400)
      ..strokeWidth = 2;
    final outline = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = 4;

    if (p1 != null && p2 != null) {
      canvas.drawLine(p1, p2, outline);
      canvas.drawLine(p1, p2, stroke);
    }
    if (p1 != null) _drawHandle(canvas, p1, 'A');
    if (p2 != null) _drawHandle(canvas, p2, 'B');
  }

  void _drawHandle(Canvas canvas, Offset p, String label) {
    final ring = Paint()
      ..color = const Color(0xFFFFD400)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final core = Paint()..color = const Color(0xCC000000);
    canvas.drawCircle(p, 10, core);
    canvas.drawCircle(p, 10, ring);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFD400),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter old) =>
      old.a != a || old.b != b || old.scale != scale;
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({
    required this.mode,
    required this.a,
    required this.b,
    required this.scaleMmPerPx,
    required this.onCalibrate,
  });

  final _Mode mode;
  final Offset? a;
  final Offset? b;
  final double? scaleMmPerPx;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (a == null || b == null) {
      return Text(
        a == null
            ? 'Tap to place marker A.'
            : 'Tap to place marker B.',
        style: theme.textTheme.bodyMedium,
      );
    }
    final pixDist = (b! - a!).distance;
    if (mode == _Mode.calibrate) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Distance: ${pixDist.toStringAsFixed(1)} px',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          FilledButton.icon(
            onPressed: onCalibrate,
            icon: const Icon(Icons.straighten),
            label: const Text('Enter real distance…'),
          ),
        ],
      );
    }
    if (scaleMmPerPx == null) {
      return Text(
        'Distance: ${pixDist.toStringAsFixed(1)} px — calibrate first to see mm.',
        style: theme.textTheme.bodyMedium,
      );
    }
    final mm = pixDist * scaleMmPerPx!;
    return Text(
      'Distance: ${pixDist.toStringAsFixed(1)} px · ${mm.toStringAsFixed(2)} mm',
      style: theme.textTheme.titleMedium,
    );
  }
}
