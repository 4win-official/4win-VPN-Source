import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders its child through a low-resolution, nearest-neighbor image filter.
///
/// Keeping the original widget tree underneath means taps, scrolling, text
/// selection, and accessibility semantics continue to work normally.
class PixelationFilter extends StatelessWidget {
  const PixelationFilter({super.key, required this.child});

  final Widget child;

  static const double _pixelCellSize = 3;
  static final ui.ImageFilter _filter = _createFilter();

  static ui.ImageFilter _createFilter() {
    final reduction = 1 / _pixelCellSize;
    final enlargement = _pixelCellSize;
    final reduceMatrix = _scaleMatrix(reduction);
    final enlargeMatrix = _scaleMatrix(enlargement);

    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.matrix(
        enlargeMatrix,
        filterQuality: FilterQuality.none,
      ),
      inner: ui.ImageFilter.matrix(
        reduceMatrix,
        filterQuality: FilterQuality.none,
      ),
    );
  }

  static Float64List _scaleMatrix(double scale) => Float64List.fromList([
    scale,
    0,
    0,
    0,
    0,
    scale,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(imageFilter: _filter, child: child);
  }
}
