import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:zhongyi_pallet/domain/packing.dart';

void main() {
  group('packing calculator', () {
    test(
      'mixes orientations to improve the default pallet from 9 to 10 boxes',
      () {
        final result = calculatePacking(PackingInput.defaults);
        expect(result.boxesPerLayer, 10);
        expect(result.maxLayers, 5);
        expect(result.layers, 5);
        expect(result.totalBoxes, 50);
        expect(result.totalWeight, 400);
        expect(result.packedHeight, 1400);
        expect(result.utilization, 1);
        expect(result.placements.any((box) => box.rotated), isTrue);
        expect(result.placements.any((box) => !box.rotated), isTrue);
        expect(result.limitingFactor, '限高限制');
        _expectLegalLayout(result);
      },
    );

    test('can select a fully rotated rectangular layout', () {
      final result = calculatePacking(
        PackingInput.defaults.copyWith(
          boxLength: 400,
          boxWidth: 600,
          palletLength: 1200,
          palletWidth: 800,
        ),
      );
      expect(result.boxesPerLayer, 4);
      expect(result.placements.every((box) => box.rotated), isTrue);
      _expectLegalLayout(result);
    });

    test('respects margin and gap in both row and column variants', () {
      for (final pallet in [(1200.0, 1000.0), (1000.0, 1200.0)]) {
        final result = calculatePacking(
          PackingInput.defaults.copyWith(
            palletLength: pallet.$1,
            palletWidth: pallet.$2,
            gap: 10,
            margin: 20,
          ),
        );
        expect(result.boxesPerLayer, greaterThan(0));
        expect(result.utilization, lessThan(1));
        _expectLegalLayout(result);
      }
    });

    test('applies cargo weight limit including a partial top layer', () {
      final result = calculatePacking(
        PackingInput.defaults.copyWith(maxLoad: 100),
      );
      expect(result.boxesPerLayer, 10);
      expect(result.totalBoxes, 12);
      expect(result.layers, 2);
      expect(result.topLayerBoxes, 2);
      expect(result.totalWeight, 96);
      expect(result.packedHeight, 650);
      expect(result.limitingFactor, '载重限制');
      expect(result.firstLayerPlacements.length, 10);
    });

    test('first layer preview contains only boxes allowed by cargo weight', () {
      final result = calculatePacking(
        PackingInput.defaults.copyWith(maxLoad: 20),
      );
      expect(result.totalBoxes, 2);
      expect(result.layers, 1);
      expect(result.firstLayerPlacements.length, 2);
      expect(result.utilization, closeTo(0.2, 1e-12));
    });

    test('subtracts pallet height from the overall height limit', () {
      final result = calculatePacking(
        PackingInput.defaults.copyWith(maxHeight: 649),
      );
      expect(result.maxLayers, 1);
      expect(result.layers, 1);
      expect(result.totalBoxes, 10);
      expect(result.packedHeight, 400);
    });

    test('reports no fit when dimensions, height or weight disallow a box', () {
      final inputs = [
        PackingInput.defaults.copyWith(boxLength: 1300, boxWidth: 1300),
        PackingInput.defaults.copyWith(maxHeight: 399),
        PackingInput.defaults.copyWith(maxLoad: 7.9),
        PackingInput.defaults.copyWith(margin: 600),
        PackingInput.defaults.copyWith(palletHeight: 1600),
      ];
      for (final input in inputs) {
        final result = calculatePacking(input);
        expect(result.isFeasible, isFalse);
        expect(result.totalBoxes, 0);
        expect(result.layers, 0);
        expect(result.topLayerBoxes, 0);
        expect(result.firstLayerPlacements, isEmpty);
        expect(result.utilization, 0);
      }
    });

    test('rejects invalid, non-finite, and excessive-work inputs', () {
      final inputs = [
        PackingInput.defaults.copyWith(boxLength: 0),
        PackingInput.defaults.copyWith(boxWidth: -1),
        PackingInput.defaults.copyWith(boxHeight: double.nan),
        PackingInput.defaults.copyWith(boxWeight: double.infinity),
        PackingInput.defaults.copyWith(gap: -1),
        PackingInput.defaults.copyWith(margin: double.nan),
        PackingInput.defaults.copyWith(palletHeight: -1),
        PackingInput.defaults.copyWith(palletHeight: 1e300),
        PackingInput.defaults.copyWith(margin: 1e300),
        PackingInput.defaults.copyWith(gap: 1e300),
        PackingInput.defaults.copyWith(boxWeight: 1e300),
        PackingInput.defaults.copyWith(maxLoad: 0),
        PackingInput.defaults.copyWith(boxLength: 1, boxWidth: 1),
      ];
      for (final input in inputs) {
        expect(() => calculatePacking(input), throwsArgumentError);
      }
    });

    test('serializes all input parameters without changing a result', () {
      final original = PackingInput.defaults.copyWith(gap: 7, margin: 14);
      final restored = PackingInput.fromJson(original.toJson());
      expect(restored.toJson(), original.toJson());
      expect(
        calculatePacking(restored).totalBoxes,
        calculatePacking(original).totalBoxes,
      );
      expect(
        () => PackingInput.fromJson({'boxLength': '400'}),
        throwsFormatException,
      );
    });

    test('all generated positions stay in bounds and never overlap', () {
      final random = math.Random(2048);
      for (var run = 0; run < 120; run++) {
        final input = PackingInput.defaults.copyWith(
          boxLength: 100 + random.nextInt(500).toDouble(),
          boxWidth: 100 + random.nextInt(500).toDouble(),
          palletLength: 800 + random.nextInt(600).toDouble(),
          palletWidth: 800 + random.nextInt(600).toDouble(),
          margin: random.nextInt(60).toDouble(),
          gap: random.nextInt(30).toDouble(),
          maxLoad: 100 + random.nextInt(1200).toDouble(),
        );
        final result = calculatePacking(input);
        _expectLegalLayout(result);
        expect(result.totalWeight, lessThanOrEqualTo(input.maxLoad + 1e-8));
        expect(result.packedHeight, lessThanOrEqualTo(input.maxHeight + 1e-8));
      }
    });

    test('large gaps do not create a false fit for an oversized box', () {
      final result = calculatePacking(
        PackingInput.defaults.copyWith(
          boxLength: 1500,
          boxWidth: 1400,
          gap: 100000,
        ),
      );
      expect(result.boxesPerLayer, 0);
    });

    test(
      'extreme aspect ratio does not create excessive rows or false fits',
      () {
        final input = PackingInput.defaults.copyWith(
          boxLength: 1,
          boxWidth: 100000,
          palletLength: 100000,
          palletWidth: 1,
        );
        final result = calculatePacking(input);
        expect(result.boxesPerLayer, 1);
        expect(result.placements.single.rotated, isTrue);
        _expectLegalLayout(result);
      },
    );
  });
}

void _expectLegalLayout(PackingResult result) {
  final input = result.input;
  const tolerance = 1e-7;
  for (final box in result.placements) {
    expect(box.x, greaterThanOrEqualTo(input.margin - tolerance));
    expect(box.y, greaterThanOrEqualTo(input.margin - tolerance));
    expect(
      box.x + box.length,
      lessThanOrEqualTo(input.palletLength - input.margin + tolerance),
    );
    expect(
      box.y + box.width,
      lessThanOrEqualTo(input.palletWidth - input.margin + tolerance),
    );
    expect(box.length, box.rotated ? input.boxWidth : input.boxLength);
    expect(box.width, box.rotated ? input.boxLength : input.boxWidth);
  }
  for (var i = 0; i < result.placements.length; i++) {
    final a = result.placements[i];
    for (var j = i + 1; j < result.placements.length; j++) {
      final b = result.placements[j];
      final separated =
          a.x + a.length + input.gap <= b.x + tolerance ||
          b.x + b.length + input.gap <= a.x + tolerance ||
          a.y + a.width + input.gap <= b.y + tolerance ||
          b.y + b.width + input.gap <= a.y + tolerance;
      expect(
        separated,
        isTrue,
        reason: 'Boxes $i and $j must not overlap and must retain the gap',
      );
    }
  }
}
