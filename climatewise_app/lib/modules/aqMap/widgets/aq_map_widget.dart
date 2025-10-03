// lib/modules/aqMap/widgets/aq_map_widget.dart
//
// Air-quality map with:
// 1) Floating controls (OverlayProductSelector, HorizontalTimeSelector, LegendBar) — now key-tagged
// 2) PNG overlay over North America (zoom buckets 3..7)
// 3) JSON heatmap rendered to current viewport (zoom >= 8) via custom ImageProvider
// 4) Bottom AppStatusInfo pill + Center crosshair + Zoom indicator (+ zoom panel)
// 5) Debounced map events + overlay pre-cache + centered loader
//
// Restored:
// - Clickable stations pins opening StationDetailsSheet.
//
// Extras:
// - Small spinner for stationsLoading (bottom-right).
// - BBOX-too-tiny guard to skip wasteful heatmap rendering.
// - Dynamic heatmap texture size by zoom (better perf).
// - Accepts optional Keys to integrate with tutorial_coach_mark (coach marks).
//
// NOTE: AqMapController must expose takePendingCameraMove(), setViewportBbox(), etc.
//
// New:
// - OSM attribution pill (bottom-left) to comply with © OpenStreetMap requirements,
//   placed to avoid overlap with existing floating controls.

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// For synchronous ImageProvider keys
import 'package:flutter/foundation.dart' show SynchronousFuture;

// Legend model
import '../models/legend.dart';

// Controller & models
import '../controllers/aq_map_controller.dart';
import '../models/overlay_slot.dart';
import '../models/overlay_grid.dart';
import '../models/forecast_grid.dart';

// UI widgets
import 'app_status_info.dart';
import 'center_crosshair.dart';
import 'zoom_indicator.dart';
import 'horizontal_time_selector.dart';
import 'overlay_product_selector.dart';
import 'legend_bar.dart';

// Stations pins & details
import 'stations_pins_layer.dart';
import 'station_details_sheet.dart';

// Buttons
import 'point_assess_button.dart';
import 'app_status_toggle_button.dart';

class AQMapWidget extends StatefulWidget {
  // Keys for coach marks
  final Key? productSelectorKey;
  final Key? timelineKey;
  final Key? legendKey;
  final Key? appStatusKey;
  final Key? zoomIndicatorKey;
  final Key? pointAssessKey;

  const AQMapWidget({
    super.key,
    this.productSelectorKey,
    this.timelineKey,
    this.legendKey,
    this.appStatusKey,
    this.zoomIndicatorKey,
    this.pointAssessKey,
  });

  @override
  State<AQMapWidget> createState() => _AQMapWidgetState();
}

class _AQMapWidgetState extends State<AQMapWidget> {
  // NA bounds for PNG overlays (zoom buckets 3..7)
  static const double _naSouth = 15.0;
  static const double _naNorth = 75.0;
  static const double _naWest = -170.0;
  static const double _naEast = -50.0;

  static final LatLngBounds _naBounds = LatLngBounds(
    LatLng(_naSouth, _naWest), // SW
    LatLng(_naNorth, _naEast), // NE
  );

  late final MapController _map;
  late final MapOptions _options;

  // UI-only zoom value
  double _zoomForUi = 3.6;

  // Throttle app-status when in overview
  DateTime _lastStatusFetch = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _statusFetchThrottle = Duration(seconds: 3);

  // Bottom info pill
  bool _showInfoBar = true;
  bool _statusDismissed = false; // user intentionally closed → don't auto-show

  // Zoom panel (right-center)
  bool _zoomPanelOpen = false;

  // Avoid double kickstart for legend
  bool _legendKickstarted = false;

  // Debounce for map events
  Timer? _debounceTimer;
  static const Duration _mapDebounce = Duration(milliseconds: 200);

  // Overlay pre-cache guard
  String? _lastPrecachedUrl;

  // Keep last viewport bounds for heatmap
  LatLngBounds? _lastViewportBounds;

  // Expected zoom range for panel logic
  static const double _panelMinZoom = 3.0;
  static const double _panelMaxZoom = 12.0;

  @override
  void initState() {
    super.initState();
    _map = MapController();

    _options = MapOptions(
      // Start centered over NA
      initialCenter: LatLng(
        (_naSouth + _naNorth) / 2,
        (_naWest + _naEast) / 2,
      ),
      initialZoom: 3.6,
      minZoom: 2.0,
      maxZoom: 13.0,

      // Constrain camera to NA
      cameraConstraint: CameraConstraint.contain(bounds: _naBounds),

      interactionOptions: const InteractionOptions(
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),

      // Tap to move & refresh app-status
      onTap: (tapPos, latLng) {
        _map.move(latLng, _zoomForUi);

        final c = context.read<AqMapController>();
        c.updateView(center: latLng, zoom: _zoomForUi);
        c.refreshAppStatus();
      },

      // Debounced map events
      onMapEvent: (e) {
        final cam = e.camera;
        final z = cam.zoom;

        // Smooth zoom text
        if (z.isFinite && (z - _zoomForUi).abs() >= 0.01) {
          if (mounted) setState(() => _zoomForUi = z);
        }

        void commit() {
          if (!mounted) return;
          final c = context.read<AqMapController>();
          c.updateView(center: cam.center, zoom: cam.zoom);

          // Pass viewport BBOX to controller and save for heatmap bounds
          final bounds = cam.visibleBounds;
          final sw = bounds.southWest;
          final ne = bounds.northEast;
          _lastViewportBounds = bounds;
          c.setViewportBbox([sw.longitude, sw.latitude, ne.longitude, ne.latitude]);

          // Throttle app-status on overview zooms
          if (cam.zoom <= 4.5) {
            final now = DateTime.now();
            if (now.difference(_lastStatusFetch) >= _statusFetchThrottle) {
              _lastStatusFetch = now;
              c.refreshAppStatus();
            }
            // only if user didn't dismiss intentionally
            if (!_showInfoBar && !_statusDismissed) {
              setState(() => _showInfoBar = true);
            }
          }
        }

        // End events: commit immediately; otherwise debounce
        if (e is MapEventMoveEnd ||
            e is MapEventFlingAnimationEnd ||
            e is MapEventDoubleTapZoomEnd) {
          _debounceTimer?.cancel();
          commit();
        } else {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(_mapDebounce, commit);
        }
      },
    );

    // Kickstart legend once on first frame if still null
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final c = context.read<AqMapController>();
      if (!_legendKickstarted && c.legend == null) {
        _legendKickstarted = true;
        await c.loadLegend(force: false);
      }
    });
  }

  bool get _timelineVisible => true;

  // Pre-cache PNG overlay and notify controller
  void _precacheOverlayIfNeeded(BuildContext context, AqMapController c) {
    final url = c.overlayUrl;
    if (url == null) return;
    if (url == _lastPrecachedUrl) return;

    _lastPrecachedUrl = url;
    c.onOverlayImageLoadStarted();

    final img = NetworkImage(url);
    precacheImage(img, context).then((_) {
      if (!mounted) return;
      if (c.overlayUrl == _lastPrecachedUrl) {
        c.onOverlayImageLoadSucceeded();
      }
    }).catchError((_) {
      if (!mounted) return;
      if (c.overlayUrl == _lastPrecachedUrl) {
        c.onOverlayImageLoadFailed();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Clamp to 3..8 buckets for PNG pre-cache helpers
  int _zb(int z) => z < 3 ? 3 : (z > 8 ? 8 : z);

  // Choose heatmap texture size by current zoom bucket
  int _heatmapTexFor(int zoomBucket) {
    if (zoomBucket <= 9) return 1024;
    if (zoomBucket == 10) return 1280;
    return 1536; // 11+
  }

  // Open the bottom sheet with station details
  void _openStationDetails(BuildContext context, dynamic p) {
    final c = context.read<AqMapController>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StationDetailsSheet(controller: c, point: p),
    );
  }

  // Zoom helper (±1.0 steps) — within 3..12
  void _zoomBy(double delta) {
    final targetZ = (_zoomForUi + delta).clamp(_panelMinZoom, _panelMaxZoom);
    final center = _map.camera.center;
    _map.move(center, targetZ);
  }

  // Launch OSM copyright page (outside of the app if possible).
  Future<void> _openOSMCopyright() async {
    final uri = Uri.parse('https://www.openstreetmap.org/copyright');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Swallow errors; attribution text remains visible even if link fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AqMapController>();

    // If controller requested a camera move, apply it exactly once here
    final moveReq = c.takePendingCameraMove();
    if (moveReq != null) {
      _map.move(moveReq.center, moveReq.zoom);
      _zoomForUi = moveReq.zoom; // we're inside build; no setState needed
    }

    // Selected slot (sometimes used for pre-cache logic)
    OverlaySlot? selectedSlot;
    if (c.selectedGid != null && c.slots.isNotEmpty) {
      final idx = c.slots.indexWhere((s) => s.gid == c.selectedGid);
      if (idx >= 0) selectedSlot = c.slots[idx];
    }

    // Pre-cache overlay PNG if URL changed
    if (c.overlayVisibleForZoom && c.overlayUrl != null) {
      _precacheOverlayIfNeeded(context, c);
    }

    // Heatmap bounds: viewport or NA on first frame
    final LatLngBounds heatmapBounds = _lastViewportBounds ?? _naBounds;

    // Tiny-BBOX guard (deg thresholds are conservative)
    final bool bboxTooTiny =
        (heatmapBounds.east - heatmapBounds.west).abs() < 0.08 ||
        (heatmapBounds.north - heatmapBounds.south).abs() < 0.08;

    // Which grid to render
    final bool showPastGrid = c.isJsonGridMode &&
        !c.isForecast &&
        c.overlayGridResponse != null &&
        c.legend != null &&
        !bboxTooTiny;

    final bool showFutureGrid = c.isJsonGridMode &&
        c.isForecast &&
        c.forecastGridResponse != null &&
        c.legend != null &&
        !bboxTooTiny;

    // Conditions for pins layer (keep in sync with controller guards)
    final bool showPinsLayer = c.pinsOn && c.stationsSupported && _zoomForUi >= 9.0;

    // Pick heatmap texture size based on zoom
    final int texSize = _heatmapTexFor(c.zoomBucket);

    // Booleans for enabling/disabling zoom buttons
    final bool canZoomIn  = _zoomForUi < _panelMaxZoom;
    final bool canZoomOut = _zoomForUi > _panelMinZoom;

    return Stack(
      children: [
        // ---------------- Fullscreen map ----------------
        FlutterMap(
          mapController: _map,
          options: _options,
          children: [
            // Base tiles
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'cloud.dinamit.climatewise',
              keepBuffer: 2,
              panBuffer: 1,
            ),

            // PNG overlay 3..7 (over entire NA)
            if (c.overlayVisibleForZoom && c.overlayUrl != null)
              OverlayImageLayer(
                overlayImages: [
                  OverlayImage(
                    bounds: _naBounds,
                    opacity: 0.78,
                    imageProvider: NetworkImage(c.overlayUrl!),
                  ),
                ],
              ),

            // JSON heatmap (>=8) — PAST
            if (showPastGrid)
              OverlayImageLayer(
                overlayImages: [
                  OverlayImage(
                    bounds: heatmapBounds,
                    opacity: 0.85,
                    imageProvider: _PastGridHeatmapImage(
                      response: c.overlayGridResponse!,
                      legend: c.legend!,
                      bboxWest: heatmapBounds.southWest.longitude,
                      bboxSouth: heatmapBounds.southWest.latitude,
                      bboxEast: heatmapBounds.northEast.longitude,
                      bboxNorth: heatmapBounds.northEast.latitude,
                      texSize: texSize,
                    ),
                  ),
                ],
              ),

            // JSON heatmap (>=8) — FUTURE
            if (showFutureGrid)
              OverlayImageLayer(
                overlayImages: [
                  OverlayImage(
                    bounds: heatmapBounds,
                    opacity: 0.85,
                    imageProvider: _FutureGridHeatmapImage(
                      response: c.forecastGridResponse!,
                      legend: c.legend!,
                      bboxWest: heatmapBounds.southWest.longitude,
                      bboxSouth: heatmapBounds.southWest.latitude,
                      bboxEast: heatmapBounds.northEast.longitude,
                      bboxNorth: heatmapBounds.northEast.latitude,
                      texSize: texSize,
                    ),
                  ),
                ],
              ),

            // CLICKABLE STATIONS LAYER (guarded)
            if (showPinsLayer)
              StationsPinsLayer(
                controller: c,
                points: c.stationsResponse?.points ?? const [],
                currentZoom: _zoomForUi,
                minZoomToShow: 9.0,
                onTapPoint: (p) => _openStationDetails(context, p),
              ),
          ],
        ),

        // ---------------- Floating top controls ----------------
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product selector (coach-tagged)
                  KeyedSubtree(
                    key: widget.productSelectorKey,
                    child: const OverlayProductSelector(),
                  ),
                  const SizedBox(height: 6),

                  // Timeline (coach-tagged)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: (_timelineVisible && c.slots.isNotEmpty && c.overlayOn)
                        ? KeyedSubtree(
                            key: widget.timelineKey,
                            child: HorizontalTimeSelector(
                              items: c.slots,
                              selectedGid: c.selectedGid,
                              selectedForecastHour: c.selectedForecastHour,
                              // Select past slot
                              onSelect: (OverlaySlot? slot) {
                                if (slot == null) return;
                                c.selectOverlayByGid(slot.gid);

                                // Pre-cache neighbor PNGs for 3..7
                                final int zb = _zb(c.zoomBucket);
                                final idx = c.slots.indexWhere((s) => s.gid == slot.gid);
                                if (idx >= 0) {
                                  final next = (idx + 1 < c.slots.length) ? c.slots[idx + 1] : null;
                                  final prev = (idx - 1 >= 0) ? c.slots[idx - 1] : null;
                                  if (next != null) {
                                    precacheImage(
                                      NetworkImage(
                                        c.repository.buildOverlayUrl(
                                          product: c.product, gid: next.gid, z: zb,
                                        ),
                                      ),
                                      context,
                                    );
                                  }
                                  if (prev != null) {
                                    precacheImage(
                                      NetworkImage(
                                        c.repository.buildOverlayUrl(
                                          product: c.product, gid: prev.gid, z: zb,
                                        ),
                                      ),
                                      context,
                                    );
                                  }
                                }
                              },
                              // Select +H forecast hour
                              onSelectForecastHour: (int h) {
                                c.selectForecastHour(h);

                                // Optional: pre-cache ±1h PNGs for 3..7
                                final int zb = _zb(c.zoomBucket);
                                final nextH = (h + 1 <= 12) ? h + 1 : null;
                                final prevH = (h - 1 >= 0) ? h - 1 : null;

                                if (nextH != null) {
                                  precacheImage(
                                    NetworkImage(
                                      c.repository.buildForecastUrl(
                                        product: c.product, z: zb, tHours: nextH,
                                      ),
                                    ),
                                    context,
                                  );
                                }
                                if (prevH != null) {
                                  precacheImage(
                                    NetworkImage(
                                      c.repository.buildForecastUrl(
                                        product: c.product, z: zb, tHours: prevH,
                                      ),
                                    ),
                                    context,
                                  );
                                }
                              },
                              height: 36,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  // Legend (coach-tagged)
                  if (c.overlayOn && c.legend != null) ...[
                    const SizedBox(height: 6),
                    KeyedSubtree(
                      key: widget.legendKey,
                      child: LegendBar(
                        legend: c.legend!,
                        rectWidth: 24,
                        rectHeight: 10,
                        spacing: 6,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Center crosshair
        const Center(child: CenterCrosshair()),

        // ---- Zoom panel (right-center) ----
        Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: IgnorePointer(
              ignoring: !_zoomPanelOpen,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                offset: _zoomPanelOpen ? Offset.zero : const Offset(0.2, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _zoomPanelOpen ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: IntrinsicWidth(
                      child: Material(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ZoomBtn(
                              icon: Icons.add,
                              enabled: canZoomIn,
                              onTap: () => _zoomBy(1.0),
                            ),
                            const Divider(height: 1, color: Colors.white24),
                            _ZoomBtn(
                              icon: Icons.remove,
                              enabled: canZoomOut,
                              onTap: () => _zoomBy(-1.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ---------------- Bottom AppStatusInfo (coach-tagged) ----------------
        Consumer<AqMapController>(
          builder: (context, ctrl, _) {
            if (!_showInfoBar) {
              return const SizedBox.shrink();
            }

            final String uiMode = ctrl.isForecast ? 'forecast' : 'real';
            final int? uiTHours = ctrl.isForecast ? (ctrl.selectedForecastHour ?? 0) : null;
            final String? uiGid = ctrl.isForecast ? null : ctrl.selectedGid;
            final int uiZ = ctrl.zoomBucket;

            final bool canCountStations =
                _zoomForUi >= 9.0 && ctrl.stationsResponse?.points != null;
            final int? uiStationsCount =
                canCountStations ? ctrl.stationsResponse!.points.length : null;

            return KeyedSubtree(
              key: widget.appStatusKey,
              child: AppStatusInfo(
                status: ctrl.status,
                onClose: () => setState(() {
                  _showInfoBar = false;
                  _statusDismissed = true;
                }),
                bottomGap: 53,
                product: ctrl.product,
                mode: uiMode,
                tHours: uiTHours,
                gid: uiGid,
                zBucket: uiZ,
                stationsInBBox: uiStationsCount,
              ),
            );
          },
        ),

        // ---- Bottom-right row: [AppStatusToggle(if hidden)] [PointAssess pill] [ZoomIndicator] ----
        Align(
          alignment: Alignment.bottomRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_showInfoBar)
                AppStatusToggleButton(
                  onTap: () => setState(() {
                    _showInfoBar = true;
                    _statusDismissed = false;
                  }),
                  margin: const EdgeInsets.only(right: 8, bottom: 12),
                ),

              // PointAssess (coach-tagged)
              KeyedSubtree(
                key: widget.pointAssessKey,
                child: PointAssessFab(
                  controller: c,
                  margin: const EdgeInsets.only(right: 8, bottom: 12),
                ),
              ),

              // Zoom indicator (coach-tagged)
              KeyedSubtree(
                key: widget.zoomIndicatorKey,
                child: ZoomIndicator(
                  zoom: _zoomForUi,
                  active: _zoomPanelOpen,
                  onTap: () => setState(() => _zoomPanelOpen = !_zoomPanelOpen),
                  margin: const EdgeInsets.only(right: 12, bottom: 12),
                ),
              ),
            ],
          ),
        ),

        // ---------------- Bottom-left: OSM attribution (non-overlapping) ----------------
Align(
  alignment: Alignment.bottomLeft,
  child: SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 250),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.6),
        ),
        child: const Text(
          '© OSM',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.0,
            fontWeight: FontWeight.w600,
            decorationColor: Colors.white70,
            decorationThickness: 1.0,
          ),
        ),
      ),
    ),
  ),
),


        // Centered overlay/grid loader
        if (c.overlayLoading || c.overlayGridLoading || c.forecastGridLoading)
          const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),

        // Tiny spinner for stationsLoading
        if (c.stationsLoading)
          const Positioned(
            right: 16,
            bottom: 84,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

// ---------- Private zoom button with ripple & disabled look ----------
class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ZoomBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Icon(
          icon,
          color: Colors.white,
        ),
      ),
    );

    if (!enabled) {
      return Opacity(opacity: 0.35, child: content);
    }

    return InkWell(
      onTap: onTap,
      splashColor: Colors.white24,
      highlightColor: Colors.white10,
      child: content,
    );
  }
}

// ===================================================================
// ImageProvider: soft "cloudy" heatmap for PAST (OverlayGrids)
// ===================================================================

class _PastGridHeatmapImage extends ImageProvider<_PastGridHeatmapImage> {
  final OverlayGridResponse response;
  final Legend legend;

  // Viewport BBOX (the same bounds used by OverlayImage)
  final double bboxWest;
  final double bboxSouth;
  final double bboxEast;
  final double bboxNorth;

  // Dynamic output texture resolution (square)
  final int texSize;

  _PastGridHeatmapImage({
    required this.response,
    required this.legend,
    required this.bboxWest,
    required this.bboxSouth,
    required this.bboxEast,
    required this.bboxNorth,
    required this.texSize,
  });

  @override
  Future<_PastGridHeatmapImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_PastGridHeatmapImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _PastGridHeatmapImage key,
    ImageDecoderCallback decode,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final cells = response.cells;
    final meta = response.meta;

    if (cells.isEmpty) {
      final picture = recorder.endRecording();
      final image = picture.toImageSync(texSize, texSize);
      return OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image)));
    }

    final double pxPerLonDeg = texSize / (bboxEast - bboxWest);
    final double pxPerLatDeg = texSize / (bboxNorth - bboxSouth);
    double xFromLon(double lon) => (lon - bboxWest) * pxPerLonDeg;
    double yFromLat(double lat) => (bboxNorth - lat) * pxPerLatDeg;

    final double gridDeg = (meta.gridDeg > 0 ? meta.gridDeg : 0.1);
    final double cellWpx = pxPerLonDeg * gridDeg;
    final double cellHpx = pxPerLatDeg * gridDeg;
    final double baseRadius = 0.6 * (cellWpx > cellHpx ? cellWpx : cellHpx);
    final double sigma = baseRadius * 0.65;

    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver;

    final double rOuter = baseRadius * 1.25;
    final double rInner = baseRadius * 0.85;
    final double sigmaOuter = sigma * 1.15;
    final double sigmaInner = sigma * 0.85;

    for (final cell in cells) {
      final col = _valueToColorPast(cell.value, legend, meta);
      final double cx = xFromLon(cell.lon);
      final double cy = yFromLat(cell.lat);

      paint
        ..color = col.withOpacity(0.35)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigmaOuter);
      canvas.drawCircle(Offset(cx, cy), rOuter, paint);

      paint
        ..color = col.withOpacity(0.60)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigmaInner);
      canvas.drawCircle(Offset(cx, cy), rInner, paint);
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(texSize, texSize);
    return OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image)));
  }

  Color _valueToColorPast(double value, Legend legend, OverlayGridMeta meta) {
    final v = value.clamp(meta.domainMin, meta.domainMax);
    final stops = legend.values;
    final colors = legend.colors;
    if (stops.isEmpty || colors.isEmpty) return Colors.grey;

    int idx = 0;
    for (int i = 0; i < stops.length - 1; i++) {
      if (v >= stops[i] && v <= stops[i + 1]) {
        idx = i;
        break;
      }
    }
    if (idx < 0) idx = 0;
    if (idx >= colors.length) idx = colors.length - 1;
    return colors[idx];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PastGridHeatmapImage &&
          other.response == response &&
          other.legend == legend &&
          other.bboxWest == bboxWest &&
          other.bboxSouth == bboxSouth &&
          other.bboxEast == bboxEast &&
          other.bboxNorth == bboxNorth &&
          other.texSize == texSize;

  @override
  int get hashCode => Object.hash(
        response, legend, bboxWest, bboxSouth, bboxEast, bboxNorth, texSize,
      );
}

// ===================================================================
// ImageProvider: soft "cloudy" heatmap for FUTURE (ForecastGrids)
// ===================================================================

class _FutureGridHeatmapImage extends ImageProvider<_FutureGridHeatmapImage> {
  final ForecastGridResponse response;
  final Legend legend;

  final double bboxWest;
  final double bboxSouth;
  final double bboxEast;
  final double bboxNorth;

  final int texSize;

  _FutureGridHeatmapImage({
    required this.response,
    required this.legend,
    required this.bboxWest,
    required this.bboxSouth,
    required this.bboxEast,
    required this.bboxNorth,
    required this.texSize,
  });

  @override
  Future<_FutureGridHeatmapImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_FutureGridHeatmapImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _FutureGridHeatmapImage key,
    ImageDecoderCallback decode,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final cells = response.cells;
    final meta = response.meta;

    if (cells.isEmpty) {
      final picture = recorder.endRecording();
      final image = picture.toImageSync(texSize, texSize);
      return OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image)));
    }

    final double pxPerLonDeg = texSize / (bboxEast - bboxWest);
    final double pxPerLatDeg = texSize / (bboxNorth - bboxSouth);
    double xFromLon(double lon) => (lon - bboxWest) * pxPerLonDeg;
    double yFromLat(double lat) => (bboxNorth - lat) * pxPerLatDeg;

    final double gridDeg = (meta.gridDeg > 0 ? meta.gridDeg : 0.1);
    final double cellWpx = pxPerLonDeg * gridDeg;
    final double cellHpx = pxPerLatDeg * gridDeg;
    final double baseRadius = 0.6 * (cellWpx > cellHpx ? cellWpx : cellHpx);
    final double sigma = baseRadius * 0.65;

    final Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver;

    final double rOuter = baseRadius * 1.25;
    final double rInner = baseRadius * 0.85;
    final double sigmaOuter = sigma * 1.15;
    final double sigmaInner = sigma * 0.85;

    for (final cell in cells) {
      final col = _valueToColorFuture(cell.value, legend, meta);

      final double cx = xFromLon(cell.lon);
      final double cy = yFromLat(cell.lat);

      paint
        ..color = col.withOpacity(0.35)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigmaOuter);
      canvas.drawCircle(Offset(cx, cy), rOuter, paint);

      paint
        ..color = col.withOpacity(0.60)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigmaInner);
      canvas.drawCircle(Offset(cx, cy), rInner, paint);
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(texSize, texSize);
    return OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image)));
  }

  Color _valueToColorFuture(double value, Legend legend, ForecastGridMeta meta) {
    final double dMin = meta.domainMin;
    final double dMax = meta.domainMax;
    final v = value.clamp(dMin, dMax);
    final stops = legend.values;
    final colors = legend.colors;
    if (stops.isEmpty || colors.isEmpty) return Colors.grey;

    int idx = 0;
    for (int i = 0; i < stops.length - 1; i++) {
      if (v >= stops[i] && v <= stops[i + 1]) {
        idx = i;
        break;
      }
    }
    if (idx < 0) idx = 0;
    if (idx >= colors.length) idx = colors.length - 1;
    return colors[idx];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FutureGridHeatmapImage &&
          other.response == response &&
          other.legend == legend &&
          other.bboxWest == bboxWest &&
          other.bboxSouth == bboxSouth &&
          other.bboxEast == bboxEast &&
          other.bboxNorth == bboxNorth &&
          other.texSize == texSize;

  @override
  int get hashCode => Object.hash(
        response, legend, bboxWest, bboxSouth, bboxEast, bboxNorth, texSize,
      );
}
