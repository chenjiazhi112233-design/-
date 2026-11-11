import 'dart:math' as math;

/// All dimensions are millimetres and all weights are kilograms.
class PackingInput {
  const PackingInput({
    required this.boxLength,
    required this.boxWidth,
    required this.boxHeight,
    required this.boxWeight,
    required this.palletLength,
    required this.palletWidth,
    required this.palletHeight,
    required this.maxHeight,
    required this.maxLoad,
    this.gap = 0,
    this.margin = 0,
  });

  static const defaults = PackingInput(
    boxLength: 400,
    boxWidth: 300,
    boxHeight: 250,
    boxWeight: 8,
    palletLength: 1200,
    palletWidth: 1000,
    palletHeight: 150,
    maxHeight: 1500,
    maxLoad: 1000,
  );

  final double boxLength;
  final double boxWidth;
  final double boxHeight;
  final double boxWeight;
  final double palletLength;
  final double palletWidth;
  final double palletHeight;

  /// Maximum overall height, including the pallet itself.
  final double maxHeight;

  /// Maximum cargo weight; pallet tare weight is not included.
  final double maxLoad;
  final double gap;
  final double margin;

  PackingInput copyWith({
    double? boxLength,
    double? boxWidth,
    double? boxHeight,
    double? boxWeight,
    double? palletLength,
    double? palletWidth,
    double? palletHeight,
    double? maxHeight,
    double? maxLoad,
    double? gap,
    double? margin,
  }) => PackingInput(
    boxLength: boxLength ?? this.boxLength,
    boxWidth: boxWidth ?? this.boxWidth,
    boxHeight: boxHeight ?? this.boxHeight,
    boxWeight: boxWeight ?? this.boxWeight,
    palletLength: palletLength ?? this.palletLength,
    palletWidth: palletWidth ?? this.palletWidth,
    palletHeight: palletHeight ?? this.palletHeight,
    maxHeight: maxHeight ?? this.maxHeight,
    maxLoad: maxLoad ?? this.maxLoad,
    gap: gap ?? this.gap,
    margin: margin ?? this.margin,
  );

  Map<String, double> toJson() => {
    'boxLength': boxLength,
    'boxWidth': boxWidth,
    'boxHeight': boxHeight,
    'boxWeight': boxWeight,
    'palletLength': palletLength,
    'palletWidth': palletWidth,
    'palletHeight': palletHeight,
    'maxHeight': maxHeight,
    'maxLoad': maxLoad,
    'gap': gap,
    'margin': margin,
  };

  factory PackingInput.fromJson(Map<String, dynamic> json) {
    double number(String key, {double? fallback}) {
      final value = json[key];
      if (value == null && fallback != null) return fallback;
      if (value is! num) throw FormatException('参数 $key 必须是数字');
      return value.toDouble();
    }

    return PackingInput(
      boxLength: number('boxLength'),
      boxWidth: number('boxWidth'),
      boxHeight: number('boxHeight'),
      boxWeight: number('boxWeight'),
      palletLength: number('palletLength'),
      palletWidth: number('palletWidth'),
      palletHeight: number('palletHeight'),
      maxHeight: number('maxHeight'),
      maxLoad: number('maxLoad'),
      gap: number('gap', fallback: 0),
      margin: number('margin', fallback: 0),
    );
  }

  void validate() {
    final positive = {
      '箱长': boxLength,
      '箱宽': boxWidth,
      '箱高': boxHeight,
      '单箱重量': boxWeight,
      '托盘长': palletLength,
      '托盘宽': palletWidth,
      '总限高': maxHeight,
      '最大载重': maxLoad,
    };
    for (final entry in positive.entries) {
      if (!entry.value.isFinite || entry.value <= 0) {
        throw ArgumentError('${entry.key}必须是大于 0 的有限数值');
      }
    }
    for (final entry in {
      '托盘高': palletHeight,
      '箱间距': gap,
      '边距': margin,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0) {
        throw ArgumentError('${entry.key}必须是大于或等于 0 的有限数值');
      }
      if (entry.value > 100000) {
        throw ArgumentError('${entry.key}不得超过 100000 mm，请检查输入单位');
      }
    }
    // Bound numerical work and memory when a unit or decimal point is wrong.
    for (final value in [
      boxLength,
      boxWidth,
      boxHeight,
      palletLength,
      palletWidth,
      maxHeight,
    ]) {
      if (value < 1 || value > 100000) {
        throw ArgumentError('尺寸范围为 1–100000 mm，请检查输入单位');
      }
    }
    if (boxWeight < 0.001 || boxWeight > 100000000 || maxLoad > 100000000) {
      throw ArgumentError('单箱重量范围为 0.001–100000000 kg，载重不得超过 100000000 kg');
    }
    final usableLength = math.max(0.0, palletLength - margin * 2);
    final usableWidth = math.max(0.0, palletWidth - margin * 2);
    if (usableLength * usableWidth / (boxLength * boxWidth) > 10000) {
      throw ArgumentError('单层理论箱数超过 10000，请检查尺寸单位');
    }
  }
}

class BoxPlacement {
  const BoxPlacement({
    required this.x,
    required this.y,
    required this.length,
    required this.width,
    required this.rotated,
  });

  final double x;
  final double y;

  /// Extent along the pallet's length / x axis.
  final double length;

  /// Extent along the pallet's width / y axis.
  final double width;
  final bool rotated;
}

class PackingResult {
  PackingResult({
    required this.input,
    required List<BoxPlacement> placements,
    required this.maxLayers,
    required this.totalBoxes,
    required this.patternName,
    required this.limitingFactor,
  }) : placements = List.unmodifiable(placements);

  final PackingInput input;

  /// All geometric slots in the selected full-layer pattern.
  final List<BoxPlacement> placements;

  /// Number of full-height layers allowed by the height limit alone.
  final int maxLayers;
  final int totalBoxes;
  final String patternName;
  final String limitingFactor;

  int get boxesPerLayer => placements.length;
  bool get isFeasible => totalBoxes > 0;
  int get layers =>
      totalBoxes == 0 ? 0 : (totalBoxes + boxesPerLayer - 1) ~/ boxesPerLayer;
  int get topLayerBoxes =>
      totalBoxes == 0 ? 0 : ((totalBoxes - 1) % boxesPerLayer) + 1;
  double get totalWeight => totalBoxes * input.boxWeight;
  double get packedHeight => input.palletHeight + layers * input.boxHeight;
  double get utilization =>
      firstLayerPlacements.length *
      input.boxLength *
      input.boxWidth /
      (input.palletLength * input.palletWidth);
  List<BoxPlacement> get firstLayerPlacements => placements
      .take(math.min(totalBoxes, boxesPerLayer))
      .toList(growable: false);
}

/// A deterministic row/column heuristic. It considers both uniform orientations,
/// mixed rows and mixed columns. It does not promise a global packing optimum
/// or assess carton compression, friction, stability or equipment clearance.
PackingResult calculatePacking(PackingInput input) {
  input.validate();
  final usableLength = input.palletLength - 2 * input.margin;
  final usableWidth = input.palletWidth - 2 * input.margin;
  final maxLayers = _fit(
    input.maxHeight - input.palletHeight,
    input.boxHeight,
    0,
  );

  var best = <BoxPlacement>[];
  var patternName = '无可行布局';
  if (usableLength > 0 && usableWidth > 0) {
    for (final transpose in [false, true]) {
      final rowLength = transpose ? usableWidth : usableLength;
      final rowDepth = transpose ? usableLength : usableWidth;
      final a = transpose ? input.boxWidth : input.boxLength;
      final b = transpose ? input.boxLength : input.boxWidth;
      final normalPerRow = _fit(rowLength, a, input.gap);
      final rotatedPerRow = _fit(rowLength, b, input.gap);
      final maxNormalRows = normalPerRow == 0
          ? 0
          : _fit(rowDepth, b, input.gap);
      for (var normalRows = 0; normalRows <= maxNormalRows; normalRows++) {
        final normalDepth = normalRows == 0
            ? 0.0
            : normalRows * b + (normalRows - 1) * input.gap;
        final remaining =
            rowDepth - normalDepth - (normalRows > 0 ? input.gap : 0);
        final rotatedRows = rotatedPerRow == 0
            ? 0
            : _fit(remaining, a, input.gap);
        final count = normalRows * normalPerRow + rotatedRows * rotatedPerRow;
        if (count <= best.length) continue;

        final candidate = <BoxPlacement>[];
        void appendRows(
          int rows,
          int perRow,
          double xSize,
          double ySize,
          double yStart,
          bool rotated,
        ) {
          for (var row = 0; row < rows; row++) {
            for (var column = 0; column < perRow; column++) {
              final localX = column * (xSize + input.gap);
              final localY = yStart + row * (ySize + input.gap);
              candidate.add(
                BoxPlacement(
                  x: input.margin + (transpose ? localY : localX),
                  y: input.margin + (transpose ? localX : localY),
                  length: transpose ? ySize : xSize,
                  width: transpose ? xSize : ySize,
                  rotated: rotated,
                ),
              );
            }
          }
        }

        appendRows(normalRows, normalPerRow, a, b, 0, false);
        appendRows(
          rotatedRows,
          rotatedPerRow,
          b,
          a,
          normalRows > 0 ? normalDepth + input.gap : 0,
          true,
        );
        best = candidate;
        patternName = normalRows > 0 && rotatedRows > 0
            ? (transpose ? '混合列排布' : '混合行排布')
            : (normalRows > 0 ? '标准方向排布' : '旋转方向排布');
      }
    }
  }

  final weightLimit = _fit(input.maxLoad, input.boxWeight, 0);
  final heightLimit = best.length * maxLayers;
  final totalBoxes = math.min(heightLimit, weightLimit);
  final String limitingFactor;
  if (best.isEmpty) {
    limitingFactor = '箱体无法放入托盘有效区域';
  } else if (maxLayers == 0) {
    limitingFactor = '总限高不足以放下一层箱体';
  } else if (weightLimit == 0) {
    limitingFactor = '最大载重小于单箱重量';
  } else if (weightLimit < heightLimit) {
    limitingFactor = '载重限制';
  } else if (weightLimit == heightLimit) {
    limitingFactor = '限高与载重限制';
  } else {
    limitingFactor = '限高限制';
  }
  return PackingResult(
    input: input,
    placements: best,
    maxLayers: maxLayers,
    totalBoxes: totalBoxes,
    patternName: patternName,
    limitingFactor: limitingFactor,
  );
}

int _fit(double available, double size, double gap) {
  if (available < 0) return 0;
  if (available + 1e-8 < size) return 0;
  // Relative tolerance only covers arithmetic rounding at an exact boundary.
  final quotient = (available + gap) / (size + gap);
  return math.max(0, (quotient + 1e-10).floor());
}
