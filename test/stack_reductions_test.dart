import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/image_ops/stack_reductions.dart';

void main() {
  group('computeStackReductionsSync', () {
    test('two-frame stack: max / min / range', () {
      final a = Uint8List.fromList([10, 50, 200]);
      final b = Uint8List.fromList([90, 50, 100]);
      final r = computeStackReductionsSync(
        StackInput(width: 3, height: 1, frames: [a, b]),
      );
      expect(r.maxImg, equals(Uint8List.fromList([90, 50, 200])));
      expect(r.minImg, equals(Uint8List.fromList([10, 50, 100])));
      expect(r.rangeImg, equals(Uint8List.fromList([80, 0, 100])));
    });

    test('stddev: identical frames → all zeros', () {
      final a = Uint8List.fromList([100, 100, 100]);
      final r = computeStackReductionsSync(
        StackInput(width: 3, height: 1, frames: [a, a, a]),
      );
      expect(r.stddevImg, equals(Uint8List.fromList([0, 0, 0])));
    });

    test('stddev: known variance', () {
      // values 0 and 100 alternating across frames → population stddev = 50
      final a = Uint8List.fromList([0]);
      final b = Uint8List.fromList([100]);
      final r = computeStackReductionsSync(
        StackInput(width: 1, height: 1, frames: [a, b]),
      );
      expect(r.stddevImg[0], equals(50));
    });

    test('empty frames throws', () {
      expect(
        () => computeStackReductionsSync(
          const StackInput(width: 1, height: 1, frames: []),
        ),
        throwsArgumentError,
      );
    });

    test('mismatched frame size throws', () {
      expect(
        () => computeStackReductionsSync(StackInput(
          width: 2,
          height: 1,
          frames: [Uint8List(2), Uint8List(3)],
        )),
        throwsArgumentError,
      );
    });
  });
}
