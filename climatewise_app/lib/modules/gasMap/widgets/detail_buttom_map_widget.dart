import 'dart:async';
import 'package:flutter/material.dart';

/// A bottom banner shown on the map that presents a brief country summary
/// (country name + year) and auto-hides after a timeout.
/// Tapping the banner triggers [onTap]; tapping the close icon triggers [onClose].
class DetailBottomMapWidget extends StatefulWidget {
  /// Callback fired when the banner is explicitly closed.
  final VoidCallback? onClose;

  /// Callback fired when the banner itself is tapped (e.g., navigate to details).
  final VoidCallback? onTap;

  /// Country display name (will be uppercased in UI).
  final String countryName;

  /// Selected year to display alongside the country name.
  final int year;

  const DetailBottomMapWidget({
    super.key,
    this.onClose,
    this.onTap,
    required this.countryName,
    required this.year,
  });

  @override
  DetailBottomMapWidgetState createState() => DetailBottomMapWidgetState();
}

class DetailBottomMapWidgetState extends State<DetailBottomMapWidget> {
  /// Auto-dismiss timer for the banner.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  /// Starts (or restarts) the auto-dismiss timer.
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 15), () {
      if (mounted) _close();
    });
  }

  /// Public method to reset the timer from parent/controllers.
  void resetTimer() {
    _startTimer();
  }

  /// Closes the banner and cancels the timer, invoking [onClose] if provided.
  void _close() {
    _timer?.cancel();
    if (widget.onClose != null) widget.onClose!();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DetailBottomMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart timer when country name or year changes.
    if (widget.countryName != oldWidget.countryName ||
        widget.year != oldWidget.year) {
      resetTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.09),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- CTA chip styled like a tappable button (visual affordance) ---
              Expanded(
                child: Transform.translate(
                  offset: const Offset(-8, 0), // shift inner chip 8px left
                  child: _CtaChip(
                    title: '${widget.countryName.toUpperCase()} ${widget.year}',
                    subtitle: 'Tap to view details',
                  ),
                ),
              ),

              // --- Modern blue close button (X) ---
              Container(
                margin: const EdgeInsets.only(left: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _close,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact pill-shaped CTA that looks like a tappable control inside the banner.
/// It inherits tap from the parent InkWell, so we only provide visual affordance here.
class _CtaChip extends StatefulWidget {
  final String title;
  final String subtitle;

  const _CtaChip({required this.title, required this.subtitle});

  @override
  State<_CtaChip> createState() => _CtaChipState();
}

class _CtaChipState extends State<_CtaChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Light pill with subtle border and hover/elevation feedback (desktop/web friendly).
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        label: '${widget.title}. ${widget.subtitle}.',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(_hovered ? 0.08 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.touch_app_outlined,
                size: 18,
                color: Colors.black54,
              ),
              const SizedBox(width: 8),
              // Text block (title + subtitle)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title: COUNTRY YEAR
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: .4,
                        fontFamily: 'Segoe UI',
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // Subtitle
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.black54,
                        fontFamily: 'Segoe UI',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Chevron to suggest forward navigation
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
