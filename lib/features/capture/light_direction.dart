import 'package:flutter/material.dart';

/// 8-way azimuth + 3-way elevation picker. Optional — a frame can be saved
/// without a light direction and the sidecar will simply omit the fields.
class LightDirection {
  const LightDirection({this.azimuthDeg, this.elevationDeg});

  /// 0 = N, 45 = NE, 90 = E, … (compass convention).
  final double? azimuthDeg;

  /// 15 (low), 35 (mid), 60 (high) — coarse buckets.
  final double? elevationDeg;

  bool get isSet => azimuthDeg != null;

  LightDirection copyWith({double? azimuthDeg, double? elevationDeg}) =>
      LightDirection(
        azimuthDeg: azimuthDeg ?? this.azimuthDeg,
        elevationDeg: elevationDeg ?? this.elevationDeg,
      );

  static const azimuthSteps = [0, 45, 90, 135, 180, 225, 270, 315];
  static const azimuthLabels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  static const elevationSteps = <(String, double)>[
    ('low', 15),
    ('mid', 35),
    ('high', 60),
  ];
}

class LightDirectionPicker extends StatelessWidget {
  const LightDirectionPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LightDirection value;
  final ValueChanged<LightDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Light dir.', style: theme.textTheme.labelMedium),
            const SizedBox(width: 8),
            if (value.isSet)
              TextButton.icon(
                onPressed: () => onChanged(const LightDirection()),
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('clear'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            for (var i = 0; i < LightDirection.azimuthSteps.length; i++)
              _Chip(
                label: LightDirection.azimuthLabels[i],
                selected: value.azimuthDeg == LightDirection.azimuthSteps[i],
                onTap: () => onChanged(value.copyWith(
                    azimuthDeg: LightDirection.azimuthSteps[i].toDouble())),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            for (final (label, deg) in LightDirection.elevationSteps)
              _Chip(
                label: label,
                selected: value.elevationDeg == deg,
                onTap: () => onChanged(value.copyWith(elevationDeg: deg)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}
