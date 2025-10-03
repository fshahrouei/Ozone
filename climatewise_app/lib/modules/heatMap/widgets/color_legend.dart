import 'package:flutter/material.dart';

class ColorLegend extends StatelessWidget {
  final List<Color> colors;
  final List<String> values; // anomaly ranges, e.g. -2 to -1.5°C
  final double rectWidth;
  final double rectHeight;

  const ColorLegend({
    super.key,
    required this.colors,
    required this.values,
    this.rectWidth = 30,
    this.rectHeight = 10,
  })  : assert(colors.length == values.length,
            'Colors and values length must match');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
              Text(
                values[index], // anomaly range label
                style: const TextStyle(fontSize: 10),
              ),
            ],
          );
        },
      ),
    );
  }
}
