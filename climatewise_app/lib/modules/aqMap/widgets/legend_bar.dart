// lib/modules/aqMap/widgets/legend_bar.dart
//
// A compact legend bar that renders each legend step as a vertical “column”:
// [■ color] on top and [label/value] directly under the same box.
//
// Notes:
// - Uses Wrap so items can flow onto multiple lines on small screens.
// - If labels are empty, falls back to formatted numeric values.
// - The lists are aligned using the minimum length across colors/labels/values
//   to avoid out-of-range access.

import 'package:flutter/material.dart';
import '../models/legend.dart';

class LegendBar extends StatelessWidget {
  final Legend legend;

  /// Width of the colored rectangle for each legend item.
  final double rectWidth;

  /// Height of the colored rectangle for each legend item.
  final double rectHeight;

  /// Horizontal/vertical spacing between items in the Wrap.
  final double spacing;

  /// Outer padding around the entire legend bar.
  final EdgeInsetsGeometry padding;

  /// Optional text style for labels.
  final TextStyle? labelStyle;

  /// Gap between the color rectangle and its label.
  final double itemGap;

  const LegendBar({
    super.key,
    required this.legend,
    this.rectWidth = 28,
    this.rectHeight = 12,
    this.spacing = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
    this.labelStyle,
    this.itemGap = 4,
  });

  @override
  Widget build(BuildContext context) {
    // Data sources: colors + labels (+ values as fallback).
    final colors = legend.colors;
    final labels = legend.labels;
    final values = legend.values;

    // Use the minimum length across inputs to avoid index issues.
    final int n = _min3(colors.length, labels.length, values.length);

    // If labels are empty, use formatted numeric values.
    final useLabels = (labels.isNotEmpty)
        ? labels.take(n).toList()
        : values.take(n).map(_formatValue).toList();

    // Colors aligned to the same minimal length.
    final useColors = colors.take(n).toList();

    final textStyle = labelStyle ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        );

    return Padding(
      padding: padding,
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: spacing,
        runSpacing: spacing,
        children: List.generate(n, (i) {
          final c = useColors[i];
          final label = useLabels[i];

          return _LegendItem(
            color: c,
            label: label,
            rectWidth: rectWidth,
            rectHeight: rectHeight,
            gap: itemGap,
            labelStyle: textStyle,
          );
        }),
      ),
    );
  }

  static int _min3(int a, int b, int c) => (a < b ? a : b) < c ? (a < b ? a : b) : c;

  // Lightweight number formatting for large/small values.
  String _formatValue(double v) {
    // For very large magnitudes, use scientific notation.
    if (v.abs() >= 1e6) {
      return v.toStringAsExponential(1); // e.g., 1.2e16
    }
    // Otherwise, trim unnecessary decimals.
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final double rectWidth;
  final double rectHeight;
  final double gap;
  final TextStyle labelStyle;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.rectWidth,
    required this.rectHeight,
    required this.gap,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Color swatch
        Container(
          width: rectWidth,
          height: rectHeight,
          decoration: BoxDecoration(
            color: color.withOpacity(0.9),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.black26, width: .8),
          ),
        ),
        SizedBox(height: gap),
        // Label directly below the swatch
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: rectWidth + 20),
          child: Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: labelStyle,
          ),
        ),
      ],
    );
  }
}
