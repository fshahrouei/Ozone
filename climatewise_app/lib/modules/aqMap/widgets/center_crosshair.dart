import 'package:flutter/material.dart';

/// A lightweight crosshair overlay to indicate the exact map center.
/// - IgnorePointer so it won't block map gestures.
/// - Subtle shadow + semi-transparent fill to stay unobtrusive.
class CenterCrosshair extends StatelessWidget {
  final double size;   // total size (px)
  final double stroke; // border width

  const CenterCrosshair({
    super.key,
    this.size = 28,
    this.stroke = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final color = Colors.black54;
    final fill  = Colors.white24;

    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // soft shadow ring
            Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    offset: Offset(0, 2),
                    color: Colors.black26,
                  ),
                ],
              ),
            ),
            // circle fill
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(color: Colors.black38, width: stroke),
              ),
            ),
            // plus sign
            Icon(
              Icons.add,
              size: size * 0.6,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
