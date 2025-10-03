import 'package:flutter/material.dart';

class StatsSquareButton extends StatelessWidget {
  final VoidCallback? onTap;
  final double size;

  const StatsSquareButton({
    super.key,
    this.onTap,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final double bottom = MediaQuery.of(context).padding.bottom + 20;
    return Positioned(
      right: 16,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(size / 4),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(size / 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.09),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.bar_chart,
                size: size * 0.6,
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
