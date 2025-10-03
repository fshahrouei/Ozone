// lib/modules/aqMap/widgets/horizontal_time_selector.dart
//
// Horizontal timeline selector for past/future frames.
// - Past section: a scrollable row of OverlaySlot pills (+ optional date chips)
// - NOW: a distinct pill in the middle
// - Future section: +1h .. +12h pills
//
// Behavior:
// - Auto-centers to NOW (or last past as a fallback) after the first layout
// - Re-centers adaptively when data or selections change
// - Keeps layout resilient to late layout/viewport availability

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // For RenderAbstractViewport

import '../models/overlay_slot.dart';

class HorizontalTimeSelector extends StatefulWidget {
  // ---- Past ----
  final List<OverlaySlot> items;
  final String? selectedGid;
  final ValueChanged<OverlaySlot?> onSelect;

  // ---- Future (optional) ----
  final int? selectedForecastHour; // 0..12 (0 = NOW)
  final ValueChanged<int>? onSelectForecastHour;

  // ---- UI ----
  final double height;
  final EdgeInsetsGeometry horizontalPadding;
  final bool showDateChips;

  // ---- Typographic tuning ----
  final double textLineHeight;
  final double textSize;
  final double iconSize;

  const HorizontalTimeSelector({
    super.key,
    required this.items,
    required this.selectedGid,
    required this.onSelect,
    this.selectedForecastHour,
    this.onSelectForecastHour,
    this.height = 44,
    this.horizontalPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.showDateChips = true,
    this.textLineHeight = 1.7,
    this.textSize = 13,
    this.iconSize = 14,
  });

  @override
  State<HorizontalTimeSelector> createState() => _HorizontalTimeSelectorState();
}

class _HorizontalTimeSelectorState extends State<HorizontalTimeSelector> {
  final ScrollController _ctrl = ScrollController();

  // Keys per past item for centering logic.
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  GlobalKey _k(String id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'HTS_$id'));

  // Unique key for NOW pill.
  final GlobalKey _nowKey = GlobalKey(debugLabel: 'HTS_NOW');

  // Auto-centering guards.
  bool _autoCenteredOnce = false;
  bool _kickInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _kickstartToNow());
  }

  @override
  void didUpdateWidget(covariant HorizontalTimeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final itemsChanged = oldWidget.items.length != widget.items.length;
    final selPastChanged = oldWidget.selectedGid != widget.selectedGid;
    final selFutureChanged = oldWidget.selectedForecastHour != widget.selectedForecastHour;

    if (itemsChanged || selPastChanged || selFutureChanged) {
      _autoCenteredOnce = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _kickstartToNow());
    }
  }

  Future<void> _waitScrollReady({int retries = 50}) async {
    int left = retries;
    while (left-- > 0) {
      if (!mounted) return;
      if (_ctrl.hasClients && _ctrl.position.hasViewportDimension) return;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<bool> _centerContext(BuildContext ctx, {double alignment = 0.5}) async {
    if (!mounted) return false;
    if (!_ctrl.hasClients) return false;

    final RenderObject? itemRender = ctx.findRenderObject();
    if (itemRender == null) return false;

    final viewport = RenderAbstractViewport.of(itemRender);
    if (viewport == null) return false;

    final ro = viewport.getOffsetToReveal(itemRender, alignment);
    double target = ro.offset;
    final min = _ctrl.position.minScrollExtent;
    final max = _ctrl.position.maxScrollExtent;
    target = math.max(min, math.min(max, target));

    try {
      await _ctrl.animateTo(
        target,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return false;
      return true;
    } catch (_) {
      try {
        _ctrl.jumpTo(target);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> _kickstartToNow() async {
    if (!mounted) return;
    if (_autoCenteredOnce) return;
    if (_kickInProgress) return;

    _kickInProgress = true;
    await _waitScrollReady();

    // If NOW is already built, center immediately.
    final nowCtx0 = _nowKey.currentContext;
    if (nowCtx0 != null) {
      final ok = await _centerContext(nowCtx0, alignment: 0.5);
      debugPrint(ok
          ? '[HTS] ✅ Centered NOW immediately (already built).'
          : '[HTS] ❌ Failed to center NOW immediately.');
      _autoCenteredOnce = ok;
      _kickInProgress = false;
      return;
    }

    // Ensure content dimensions are available.
    if (!(_ctrl.hasClients && _ctrl.position.hasContentDimensions)) {
      debugPrint('[HTS] ⏳ Waiting for content dimensions...');
      await Future<void>.delayed(const Duration(milliseconds: 48));
    }

    if (!(_ctrl.hasClients && _ctrl.position.hasContentDimensions)) {
      debugPrint('[HTS] ⚠️ No content dimensions; giving up this frame.');
      _kickInProgress = false;
      return;
    }

    // Adaptive nudge phases: 70% → … → 98% to ensure NOW gets built and visible.
    final List<double> factors = [0.70, 0.78, 0.84, 0.90, 0.94, 0.97, 0.98];

    for (final f in factors) {
      if (!mounted) break;
      if (_autoCenteredOnce) break;

      final max = _ctrl.position.maxScrollExtent;
      final target = max * f;

      try {
        await _ctrl.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        try {
          _ctrl.jumpTo(target);
        } catch (_) {}
      }

      if (!mounted) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));

      final nowCtx = _nowKey.currentContext;
      if (nowCtx != null) {
        final ok = await _centerContext(nowCtx, alignment: 0.5);
        debugPrint(ok
            ? '[HTS] ✅ Centered NOW after adaptive nudge f=$f.'
            : '[HTS] ❌ Failed to center NOW after nudge f=$f.');
        _autoCenteredOnce = ok;
        if (ok) break;
      } else {
        debugPrint('[HTS] 🔎 NOW not built yet (after f=$f).');
      }
    }

    // Fallback: center to the last past slot.
    if (!_autoCenteredOnce && widget.items.isNotEmpty) {
      final lastCtx = _k(widget.items.last.gid).currentContext;
      if (lastCtx != null) {
        final ok = await _centerContext(lastCtx, alignment: 0.5);
        debugPrint(ok
            ? '[HTS] ✅ Fallback centered to last past.'
            : '[HTS] ❌ Fallback failed to center last past.');
        _autoCenteredOnce = ok;
      } else {
        debugPrint('[HTS] ⚠️ Last past not built; cannot fallback.');
      }
    }

    _kickInProgress = false;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;

    if (items.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text('No data', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
      );
    }

    // Register keys for past items.
    for (final s in items) {
      _k(s.gid);
    }

    // Build future slots +1..+12.
    final futureSlots = List.generate(12, (i) {
      final h = i + 1;
      final gid = 'future_$h';
      _k(gid);
      return _FutureSlot(hour: h, gid: gid, label: '+${h}h');
    });

    return SizedBox(
      height: widget.height,
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          if (!_autoCenteredOnce) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _kickstartToNow());
          }
          return false;
        },
        child: SizeChangedLayoutNotifier(
          child: ListView(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            padding: widget.horizontalPadding,
            physics: const ClampingScrollPhysics(),
            children: [
              // ---- Past ----
              for (int i = 0; i < items.length; i++) ...[
                if (i == 0) const SizedBox(width: 2),
                if (widget.showDateChips &&
                    (i == 0 || !items[i].isSameLocalDay(items[i - 1]))) ...[
                  _DateChip(label: items[i].shortDateLabelLocal),
                  const SizedBox(width: 8),
                ],
                KeyedSubtree(
                  key: _k(items[i].gid),
                  child: _TimePill(
                    label: items[i].labelLocal,
                    isSelected: items[i].gid == widget.selectedGid,
                    lineHeight: widget.textLineHeight,
                    textSize: widget.textSize,
                    onTap: () => widget.onSelect(items[i]),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // ---- NOW ----
              KeyedSubtree(
                key: _nowKey,
                child: _NowPill(
                  isSelected: widget.selectedForecastHour == 0,
                  lineHeight: widget.textLineHeight,
                  textSize: widget.textSize,
                  iconSize: widget.iconSize,
                  onTap: () {
                    if (widget.onSelectForecastHour != null) {
                      widget.onSelectForecastHour!(0);
                    } else {
                      widget.onSelect(null);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),

              // ---- Future (+1..+12) ----
              for (final f in futureSlots) ...[
                KeyedSubtree(
                  key: _k(f.gid),
                  child: _FuturePill(
                    label: f.label,
                    isSelected: widget.selectedForecastHour != null &&
                        widget.selectedForecastHour == f.hour,
                    lineHeight: widget.textLineHeight,
                    textSize: widget.textSize,
                    iconSize: widget.iconSize,
                    onTap: () {
                      if (widget.onSelectForecastHour != null) {
                        widget.onSelectForecastHour!(f.hour);
                      } else {
                        widget.onSelect(null);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Internal UI widgets ====================

class _TimePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final double lineHeight;
  final double textSize;
  final VoidCallback onTap;

  const _TimePill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.lineHeight,
    required this.textSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isSelected ? Colors.black : Colors.white;
    final Color fg = isSelected ? Colors.white : Colors.black87;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black26, width: 1),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: textSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                height: lineHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPill extends StatelessWidget {
  final bool isSelected;
  final double lineHeight;
  final double textSize;
  final double iconSize;
  final VoidCallback onTap;

  const _NowPill({
    super.key,
    required this.isSelected,
    required this.lineHeight,
    required this.textSize,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isSelected ? Colors.blue[800]! : Colors.white;
    final Color fg = isSelected ? Colors.white : Colors.blue[900]!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade300, width: 1),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time,
                  size: iconSize,
                  color: isSelected ? Colors.white : Colors.blueGrey,
                ),
                const SizedBox(width: 4),
                // Not const: uses dynamic color `fg`.
                Text(
                  'NOW',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: textSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: lineHeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FuturePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final double lineHeight;
  final double textSize;
  final double iconSize;
  final VoidCallback onTap;

  const _FuturePill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.lineHeight,
    required this.textSize,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isSelected ? Colors.blue[800]! : Colors.white;
    final Color fg = isSelected ? Colors.white : Colors.blue[900]!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade300, width: 1),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time,
                  size: iconSize,
                  color: isSelected ? Colors.white : Colors.blueGrey,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: textSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    height: lineHeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.black12, width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          height: 1.0,
        ),
      ),
    );
  }
}

class _FutureSlot {
  final int hour; // +H (1..12)
  final String gid;
  final String label;
  _FutureSlot({required this.hour, required this.gid, required this.label});
}
