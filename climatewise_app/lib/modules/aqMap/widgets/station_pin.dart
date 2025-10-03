import 'package:flutter/material.dart';

/// A pill-style station marker used on the map.
/// - Displays provider-specific color
/// - Shows either numeric value or provider name
/// - Can be highlighted when selected
/// - Responds to tap with [onTap]
class StationPin extends StatelessWidget {
  /// Data provider name (e.g., "airnow", "openaq").
  final String? provider;

  /// Measured value (e.g., NO2 concentration in ppb).
  final num? value;

  /// Whether the pin is currently selected (affects highlight styling).
  final bool selected;

  /// Callback when the pin is tapped.
  final VoidCallback? onTap;

  const StationPin({
    super.key,
    this.provider,
    this.value,
    this.selected = false,
    this.onTap,
  });

  /// Determine base color depending on provider.
  Color _baseColor() {
    switch ((provider ?? '').toLowerCase()) {
      case 'airnow':
        return const Color(0xFF1668C1);
      case 'openaq':
        return const Color(0xFF10B981);
      default:
        return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _baseColor();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.95) : c.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.white : Colors.black.withOpacity(0.15),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_rounded,
              size: selected ? 16 : 14,
              color: Colors.white.withOpacity(0.95),
            ),
            const SizedBox(width: 4),
            Text(
              (value != null)
                  ? value!.toStringAsFixed(0)
                  : (provider ?? 'Station'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
