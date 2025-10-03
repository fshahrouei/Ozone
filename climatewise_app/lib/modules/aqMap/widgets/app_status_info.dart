// lib/modules/aqMap/widgets/app_status_info.dart
//
// Full-width bottom info bar (renamed from BottomInfoBar → AppStatusInfo)
// Row 1 (top): day/night icon + TEMPO icon + product chip + one-line subtext + close button
// Row 2 (bottom): metadata chips (mode/frame/sources/...)

import 'package:flutter/material.dart';
import '../models/app_status.dart';

class AppStatusInfo extends StatelessWidget {
  final AppStatus? status;
  final VoidCallback onClose;
  final double bottomGap;

  /// Current product name (optional).
  final String? product;

  /// End time (UTC) of the selected frame (optional override; preference is `status.frameUtc`).
  final DateTime? frameUtc;

  /// Freshness threshold (minutes) used to color the TEMPO icon.
  final int liveThresholdMin;

  // -------- Optional extra inputs shown as chips (can be overridden by `status`) --------
  final String? mode;                 // 'real' | 'forecast'
  final int? tHours;                  // 0..12 (not shown directly)
  final String? gid;                  // (not shown directly)
  final int? zBucket;                 // 3..12 (not shown directly)

  final int? stationsInBBox;          // number of stations in viewport (UI count)
  final String? source;               // legacy: single source string (e.g., "TEMPO")
  final List<String>? sources;        // optional override; prefer `status.sources` if present
  final DateTime? runGeneratedUtc;    // forecast run generation time
  final int? clockMin;                // distance to now (minutes; model: always positive)
  final List<String>? stationsProducts; // e.g., ['no2','o3']

  const AppStatusInfo({
    super.key,
    required this.status,
    required this.onClose,
    this.bottomGap = 72,
    this.product,
    this.frameUtc,
    this.liveThresholdMin = 180,
    this.mode,
    this.tHours,
    this.gid,
    this.zBucket,
    this.stationsInBBox,
    this.source,
    this.sources,
    this.runGeneratedUtc,
    this.clockMin,
    this.stationsProducts,
  });

  // ----- Helpers -----

  String _fmtZ(DateTime dt) {
    final h = dt.toUtc().hour.toString().padLeft(2, '0');
    final m = dt.toUtc().minute.toString().padLeft(2, '0');
    return '$h:${m}Z'; // Explicit string interpolation.
  }

  int _signedMinutesFrom(DateTime utc) {
    final now = DateTime.now().toUtc();
    final diff = now.difference(utc);
    return diff.inMinutes; // Negative ⇒ future.
  }

  /// "1 min ago" / "2 mins ago" / "1 hour ago" / "2 hours ago".
  String _fmtAgeMins(int mins) {
    final m = mins.abs();
    if (m < 180) {
      return m == 1 ? '1 min ago' : '$m mins ago';
    }
    final h = (m / 60).floor();
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }

  /// TEMPO icon color: green = live, red = stale (based on NOW).
  Color _tempoBinaryColor({
    required int? tempoAgeMinFromStatus,           // from model: tempoAgeMin
    required DateTime? frameUtcFromStatusOrProp,   // fallback
    required int liveThresholdMin,
  }) {
    bool isLive;
    if (tempoAgeMinFromStatus != null) {
      isLive = tempoAgeMinFromStatus <= liveThresholdMin;
    } else if (frameUtcFromStatusOrProp != null) {
      final mins = _signedMinutesFrom(frameUtcFromStatusOrProp).abs();
      isLive = mins <= liveThresholdMin;
    } else {
      isLive = false;
    }
    return isLive ? Colors.green[700]! : Colors.red[600]!;
  }

  Chip _chip(BuildContext ctx, String label) {
    final theme = Theme.of(ctx);
    return Chip(
      label: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.white.withValues(alpha: 0.7),
      side: const BorderSide(color: Colors.black12),
      visualDensity: VisualDensity.compact,
    );
  }

  Chip? _productChip(BuildContext ctx, String? product) {
    if (product == null || product.isEmpty) return null;
    final theme = Theme.of(ctx);
    return Chip(
      label: Text(
        product.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.white.withValues(alpha: 0.7),
      side: const BorderSide(color: Colors.black12),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final isDay = s?.isDay ?? false;

    final theme = Theme.of(context);
    final bg = Colors.white.withValues(alpha: 0.92);
    final onBg = Colors.black87;

    // ===== Core values =====
    final DateTime? refUtc = s?.frameUtc ?? frameUtc; // frame_utc
    final String headline = (s?.message ?? '').trim().isNotEmpty
        ? s!.message!.trim()
        : 'Status unavailable';

    final String resolvedMode = (mode != null && mode!.isNotEmpty) ? mode! : (s?.mode ?? '');
    final int cmAbs = (clockMin ?? s?.clockMin ?? 0).abs(); // model: always positive
    final int? ageNowMin = s?.tempoAgeMin; // TEMPO age at "now" (minutes)

    // Determine if frame is future (potentially used elsewhere).
    bool isFuture;
    if (tHours != null) {
      isFuture = tHours! > 0;
    } else if (refUtc != null) {
      isFuture = _signedMinutesFrom(refUtc) < 0;
    } else {
      isFuture = (resolvedMode == 'forecast') && cmAbs > 0;
    }

    // Build subline: "Last TEMPO update: …"
    String? lastUpdateText;
    if (ageNowMin != null) {
      lastUpdateText = _fmtAgeMins(ageNowMin);
    } else if (refUtc != null) {
      lastUpdateText = _fmtAgeMins(_signedMinutesFrom(refUtc));
    }
    final String subline = (lastUpdateText == null) ? '—' : 'Last TEMPO update: $lastUpdateText';

    // TEMPO icon color (NOW-based).
    final Color tempoColor = _tempoBinaryColor(
      tempoAgeMinFromStatus: s?.tempoAgeMin,
      frameUtcFromStatusOrProp: refUtc,
      liveThresholdMin: liveThresholdMin,
    );

    // -------- Chips (order matters) --------
    final chips = <Widget>[];

    // 1) mode
    if (resolvedMode.isNotEmpty) {
      chips.add(_chip(context, 'mode: $resolvedMode'));
    }

    // 2) frame — immediately after mode (same style)
    if (refUtc != null) {
      chips.add(_chip(context, 'frame: ${_fmtZ(refUtc)}'));
    }

    // 3) stations count (optional)
    if (stationsInBBox != null) {
      chips.add(_chip(context, 'stations: $stationsInBBox'));
    }

    // 4) stations products (optional)
    if (stationsProducts != null && stationsProducts!.isNotEmpty) {
      chips.add(_chip(context, 'stations•prod: ${stationsProducts!.join(",")}'));
    }

    // 5) sources
    final List<String> effectiveSources = <String>[];
    final List<String> statusSources = s?.sources ?? const <String>[];
    if (statusSources.isNotEmpty) {
      effectiveSources.addAll(
        statusSources.where((e) => e.trim().isNotEmpty).map((e) => e.trim()),
      );
    } else if (sources != null && sources!.isNotEmpty) {
      effectiveSources.addAll(
        sources!.where((e) => e.trim().isNotEmpty).map((e) => e.trim()),
      );
    } else if (source != null && source!.trim().isNotEmpty) {
      effectiveSources.add(source!.trim());
    }
    if (effectiveSources.isNotEmpty) {
      for (final src in effectiveSources) {
        chips.add(_chip(context, 'src: $src'));
      }
    }

    // 6) clock/run hidden for now; uncomment if needed later
    // final int? cm = clockMin ?? s?.clockMin;
    // if (cm != null) {
    //   final String sign = resolvedMode == 'real' ? '+' : (resolvedMode == 'forecast' ? '-' : '');
    //   final String label = sign.isEmpty ? 'clock: ${cm}m' : 'clock: $sign${cm}m';
    //   chips.add(_chip(context, label));
    // }
    // final DateTime? resolvedRunUtc = runGeneratedUtc ?? s?.runGeneratedUtc;
    // if (resolvedRunUtc != null) {
    //   chips.add(_chip(context, 'run: ${_fmtZ(resolvedRunUtc)}'));
    // }

    // ===== UI =====
    final dayNightIcon = Icon(
      isDay ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
      size: 18,
      color: onBg,
    );

    final tempoIcon = Icon(
      Icons.satellite_alt_outlined,
      size: 18,
      color: tempoColor,
    );

    final pChip = _productChip(context, product);

    return Positioned(
      left: 12,
      right: 12,
      bottom: bottomGap,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                blurRadius: 10,
                offset: Offset(0, 2),
                color: Colors.black26,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- Top row ----------------
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  dayNightIcon,
                  const SizedBox(width: 6),
                  tempoIcon,
                  const SizedBox(width: 8),

                  if (pChip != null) ...[
                    pChip,
                    const SizedBox(width: 8),
                  ],

                  // Headline + Subline
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: onBg,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subline, // "Last TEMPO update: …"
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onBg.withValues(alpha: 0.75),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Close button
                  IconButton(
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: onBg.withValues(alpha: 0.9),
                    onPressed: onClose,
                  ),
                ],
              ),

              // ---------------- Divider + Chips ----------------
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(
                  height: 10,
                  thickness: 0.6,
                  color: Color(0x1F000000),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chips,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
