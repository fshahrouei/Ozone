import 'package:flutter/material.dart';

class ColorLegend extends StatelessWidget {
  final List<Color> colors;
  final List<String> labels;
  final double rectWidth;
  final double rectHeight;
  final double spacing;

  const ColorLegend({
    super.key,
    required this.colors,
    required this.labels,
    this.rectWidth = 30,
    this.rectHeight = 10,
    this.spacing = 8,
  })  : assert(colors.length == labels.length,
            'Colors and labels length must match');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(colors.length, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: Column(
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
              Text(
                labels[index],
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        );
      }),
    );
  }
}
