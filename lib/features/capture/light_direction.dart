import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Manual light-direction tag attached to a captured frame. 8 compass azimuths
/// × 3 elevation buckets — coarse but useful as input to photometric stereo
/// and for cross-referencing the desktop pipeline.
class LightDirection {
  const LightDirection({this.azimuthDeg, this.elevationDeg});

  /// 0 = N, 45 = NE, 90 = E, … (compass convention).
  final double? azimuthDeg;

  /// 15 (low), 35 (mid), 60 (high).
  final double? elevationDeg;

  bool get isSet => azimuthDeg != null && elevationDeg != null;

  LightDirection copyWith({double? azimuthDeg, double? elevationDeg}) =>
      LightDirection(
        azimuthDeg: azimuthDeg ?? this.azimuthDeg,
        elevationDeg: elevationDeg ?? this.elevationDeg,
      );

  /// Index into the 24-step auto-advance sequence
  /// (low N → low NE → … → low NW → mid N → … → high NW), or null if the
  /// current value doesn't sit on the grid.
  int? get step {
    final az = azimuthDeg;
    final el = elevationDeg;
    if (az == null || el == null) return null;
    final aIdx = azimuthSteps.indexOf(az.round());
    if (aIdx < 0) return null;
    final eIdx = elevationSteps.indexWhere((e) => e.$2 == el);
    if (eIdx < 0) return null;
    return eIdx * azimuthSteps.length + aIdx;
  }

  /// Construct the [step]-th direction (wrapping at 24).
  static LightDirection fromStep(int step) {
    final wrapped = step % (azimuthSteps.length * elevationSteps.length);
    final eIdx = wrapped ~/ azimuthSteps.length;
    final aIdx = wrapped % azimuthSteps.length;
    return LightDirection(
      azimuthDeg: azimuthSteps[aIdx].toDouble(),
      elevationDeg: elevationSteps[eIdx].$2,
    );
  }

  /// The next direction in the auto-advance sequence — wraps around so the
  /// user can keep capturing for a second sweep without manual intervention.
  LightDirection get next {
    final s = step;
    if (s == null) return fromStep(0);
    return fromStep(s + 1);
  }

  String get shortLabel {
    if (!isSet) return 'no light';
    final aIdx = azimuthSteps.indexOf(azimuthDeg!.round());
    final eIdx = elevationSteps.indexWhere((e) => e.$2 == elevationDeg);
    final az = aIdx >= 0 ? azimuthLabels[aIdx] : '${azimuthDeg!.round()}°';
    final el = eIdx >= 0 ? elevationSteps[eIdx].$1 : '${elevationDeg!.round()}°';
    return '$az · $el';
  }

  static const azimuthSteps = [0, 45, 90, 135, 180, 225, 270, 315];
  static const azimuthLabels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  static const elevationSteps = <(String, double)>[
    ('low', 15),
    ('mid', 35),
    ('high', 60),
  ];
}

/// Compact picker: a single ActionChip showing the current direction +
/// a small auto-advance toggle. Tapping the chip opens a bottom sheet with
/// the full grid for manual overrides.
class LightDirectionCompactPicker extends StatelessWidget {
  const LightDirectionCompactPicker({
    super.key,
    required this.value,
    required this.autoAdvance,
    required this.onChanged,
    required this.onAutoChanged,
  });

  final LightDirection value;
  final bool autoAdvance;
  final ValueChanged<LightDirection> onChanged;
  final ValueChanged<bool> onAutoChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ActionChip(
          avatar: _CompassGlyph(azimuth: value.azimuthDeg),
          label: Text(value.shortLabel),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: () => _openSheet(context),
        ),
        FilterChip(
          label: const Text('auto'),
          selected: autoAdvance,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: onAutoChanged,
        ),
      ],
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        var v = value;
        return StatefulBuilder(
          builder: (ctx, setSt) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Light direction',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                _DirectionGrid(
                  value: v,
                  onChanged: (next) {
                    setSt(() => v = next);
                    onChanged(next);
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompassGlyph extends StatelessWidget {
  const _CompassGlyph({required this.azimuth});

  final double? azimuth;

  @override
  Widget build(BuildContext context) {
    if (azimuth == null) {
      return const Icon(Icons.help_outline, size: 16);
    }
    return Transform.rotate(
      angle: azimuth! * math.pi / 180.0,
      child: const Icon(Icons.navigation, size: 16),
    );
  }
}

class _DirectionGrid extends StatelessWidget {
  const _DirectionGrid({required this.value, required this.onChanged});

  final LightDirection value;
  final ValueChanged<LightDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('azimuth', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 8),
            if (value.isSet)
              TextButton(
                onPressed: () => onChanged(const LightDirection()),
                child: const Text('clear'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < LightDirection.azimuthSteps.length; i++)
              ChoiceChip(
                label: Text(LightDirection.azimuthLabels[i]),
                selected: value.azimuthDeg == LightDirection.azimuthSteps[i],
                onSelected: (_) => onChanged(value.copyWith(
                    azimuthDeg: LightDirection.azimuthSteps[i].toDouble())),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('elevation', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (final (label, deg) in LightDirection.elevationSteps)
              ChoiceChip(
                label: Text(label),
                selected: value.elevationDeg == deg,
                onSelected: (_) =>
                    onChanged(value.copyWith(elevationDeg: deg)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}
