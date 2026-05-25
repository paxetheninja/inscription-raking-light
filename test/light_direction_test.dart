import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/features/capture/light_direction.dart';

void main() {
  group('LightDirection auto-advance', () {
    test('fromStep(0) is N + low', () {
      final d = LightDirection.fromStep(0);
      expect(d.azimuthDeg, 0);
      expect(d.elevationDeg, 15);
      expect(d.shortLabel, 'N · low');
    });

    test('fromStep(8) wraps azimuth and bumps elevation to mid', () {
      final d = LightDirection.fromStep(8);
      expect(d.azimuthDeg, 0);
      expect(d.elevationDeg, 35);
      expect(d.shortLabel, 'N · mid');
    });

    test('fromStep(23) is NW + high (final position)', () {
      final d = LightDirection.fromStep(23);
      expect(d.azimuthDeg, 315);
      expect(d.elevationDeg, 60);
      expect(d.shortLabel, 'NW · high');
    });

    test('fromStep wraps after 24', () {
      final d = LightDirection.fromStep(24);
      expect(d.azimuthDeg, 0);
      expect(d.elevationDeg, 15);
    });

    test('step round-trips for grid positions', () {
      for (var i = 0; i < 24; i++) {
        expect(LightDirection.fromStep(i).step, i);
      }
    });

    test('step is null for unset and off-grid values', () {
      expect(const LightDirection().step, isNull);
      expect(const LightDirection(azimuthDeg: 10, elevationDeg: 35).step,
          isNull);
      expect(const LightDirection(azimuthDeg: 45, elevationDeg: 50).step,
          isNull);
    });

    test('next advances to the next step and wraps at NW+high', () {
      expect(LightDirection.fromStep(0).next.step, 1);
      expect(LightDirection.fromStep(7).next.step, 8); // NW low → N mid
      expect(LightDirection.fromStep(23).next.step, 0); // NW high → N low
    });

    test('next from unset starts at N+low', () {
      expect(const LightDirection().next.step, 0);
    });
  });
}
