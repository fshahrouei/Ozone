import 'package:flutter/material.dart';

/// A compact horizontal color legend composed of colored rectangles with labels.
/// 
/// Use this to display a mapping from colors to their corresponding numeric or
/// textual values (e.g., for heatmaps, choropleths, or categorical charts).
class ColorLegend extends StatelessWidget {
  /// Color swatches to be shown in order.
  final List<Color> colors;

  /// Labels corresponding to each color (e.g., tick values or category names).
  final List<String> values;

  /// Width of each color rectangle.
  final double rectWidth;

  /// Height of each color rectangle.
  final double rectHeight;

  const ColorLegend({
    super.key,
    required this.colors,
    required this.values,
    this.rectWidth = 30,
    this.rectHeight = 10,
  }) : assert(
          colors.length == values.length,
          'Colors and values length must match',
        );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Rectangle height plus vertical space for the label.
      height: rectHeight + 20,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: rectWidth,
                height: rectHeight,
                decoration: BoxDecoration(
                  color: colors[index].withOpacity(0.8),
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              // Show the actual label/value for this swatch.
              Text(
                values[index],
                style: const TextStyle(fontSize: 10),
              ),
            ],
          );
        },
      ),
    );
  }
}
