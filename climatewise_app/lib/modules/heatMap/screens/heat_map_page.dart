// lib/modules/heatMap/pages/heat_map_page.dart
//
// Safe coach + soft refresh + async guards + single loading overlay
// - Coach text constrained (max 70% height) + shared ScrollController
// - Step order: Help → Refresh → My Location → Year → Legend → Stats
// - Soft refresh: like first boot (no MapController.move before first render)
// - During loading: map/banner/stats not built ⇒ prevents double spinners

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/custom_app_bar.dart';
import '../data/heat_map_repository.dart';
import '../models/heat_data.dart';
import '../widgets/horizontal_year_selector.dart';
import '../widgets/color_legend.dart';
import '../widgets/heat_map_widget.dart';
import '../widgets/detail_bottom_map_widget.dart';
import '../widgets/stats_square_button.dart';
import 'country_detail_page.dart';
import 'statistics_page.dart';

class HeatMapPage extends StatefulWidget {
  const HeatMapPage({super.key});

  @override
  State<HeatMapPage> createState() => _HeatMapPageState();
}

class _HeatMapPageState extends State<HeatMapPage> {
  // Map & data
  final MapController _mapController = MapController();
  final HeatMapRepository _repository = HeatMapRepository();

  List<HeatData> _heatData = [];
  List<int> _years = [];
  int _selectedYear = 0;
  bool _isLoading = true;
  bool _isUpdatingYear = false;

  // Country detail banner
  bool _showDetailBottom = false;
  String _selectedCountryIsoA3 = '';
  final GlobalKey<DetailBottomMapWidgetState> _detailButtonKey = GlobalKey();

  // Tap hit test
  final ValueNotifier<LayerHitResult<Object>?> _hitNotifier = ValueNotifier(null);

  // Color ramp
  final List<Color> colors = const [
    Color(0xFF063970),
    Color(0xFF2675BF),
    Color(0xFF00B6EC),
    Color(0xFF92E3F5),
    Color(0xFFFFFFB3),
    Color(0xFFFFD65A),
    Color(0xFFFFA500),
    Color(0xFFFF5500),
    Color(0xFFFF0000),
    Color(0xFF800000),
  ];

  // Legend labels
  final List<String> anomalyValues = const [
    '<-2', '-2~-1.5', '-1.5~-1', '-1~-0.5', '-0.5~0',
    '0~0.5', '0.5~1', '1~1.5', '1.5~2', '>2'
  ];

  // Bounds & default center
  final LatLngBounds bounds = LatLngBounds(
    const LatLng(-85.0, -180.0),
    const LatLng(85.0, 180.0),
  );
  final LatLng mapCenter = const LatLng(40.7128, -74.0060);

  // Coach keys
  final GlobalKey _keyHelp = GlobalKey();
  final GlobalKey _keyRefresh = GlobalKey(); // step #2
  final GlobalKey _keyMyLocation = GlobalKey();
  final GlobalKey _keyYearSelector = GlobalKey();
  final GlobalKey _keyLegend = GlobalKey();
  final GlobalKey _keyStats = GlobalKey();

  TutorialCoachMark? _coach;

  // Rebuild subtree on soft refresh
  Key _pageInstanceKey = UniqueKey();

  // Async safety
  int _opSeq = 0;
  void safeSetState(VoidCallback fn) { if (mounted) setState(fn); }

  @override
  void initState() {
    super.initState();
    _initializeMapData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _createCoach();
    });
  }

  @override
  void dispose() {
    _opSeq++; // invalidate inflight ops
    _coach = null;
    _hitNotifier.dispose();
    super.dispose();
  }

  // Initialize data
  Future<void> _initializeMapData() async {
    final mySeq = ++_opSeq;
    try {
      final countryResponse = await _repository.fetchCountries();
      if (!mounted || mySeq != _opSeq) return;
      _selectedYear = countryResponse['currentYear'] ?? 2023;
      _heatData = countryResponse['data'];

      final yearsList = await _repository.fetchYears();
      if (!mounted || mySeq != _opSeq) return;

      safeSetState(() {
        _years = yearsList;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || mySeq != _opSeq) return;
      safeSetState(() => _isLoading = false);
    }
  }

  // HARD REFRESH: behave like first boot (do not move MapController here)
  Future<void> _onHardRefresh() async {
    final mySeq = ++_opSeq;

    // Close any previous coach overlays to avoid overlay conflicts
    try { _coach?.skip(); } catch (_) {}

    safeSetState(() {
      _isLoading = true;
      _isUpdatingYear = false;

      _heatData = [];
      _years = [];
      _selectedYear = 0;

      _showDetailBottom = false;
      _selectedCountryIsoA3 = '';
      _hitNotifier.value = null;

      // Clean rebuild (force subtree recreation)
      _pageInstanceKey = UniqueKey();
    });

    try {
      final countryResponse = await _repository.fetchCountries();
      if (!mounted || mySeq != _opSeq) return;
      final yearsList = await _repository.fetchYears();
      if (!mounted || mySeq != _opSeq) return;

      safeSetState(() {
        _selectedYear = countryResponse['currentYear'] ?? 2023;
        _heatData = countryResponse['data'];
        _years = yearsList;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || mySeq != _opSeq) return;
      safeSetState(() => _isLoading = false);
    }

    // Re-create coach flow after refresh
    if (!mounted || mySeq != _opSeq) return;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _createCoach(); });
  }

  // My Location
  Future<void> _goToUserLocation() async {
    final status = await Permission.location.request();
    if (!mounted) return;
    if (status.isGranted) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        );
        if (!mounted) return;
        final userLatLng = LatLng(position.latitude, position.longitude);
        if (bounds.contains(userLatLng)) {
          _mapController.move(userLatLng, 5.0);
        } else {
          _mapController.move(mapCenter, 4.0);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your location is outside the map extent!')),
          );
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location.')),
        );
      }
    }
  }

  // Year change
  Future<void> _onYearSelected(int year) async {
    final mySeq = ++_opSeq;
    safeSetState(() => _isUpdatingYear = true);
    try {
      final countryResponse = await _repository.fetchCountries(year: year);
      if (!mounted || mySeq != _opSeq) return;
      safeSetState(() {
        _selectedYear = year;
        _heatData = countryResponse['data'];
        _isUpdatingYear = false;
      });
    } catch (_) {
      if (!mounted || mySeq != _opSeq) return;
      safeSetState(() => _isUpdatingYear = false);
    }
  }

  // Detail banner
  void _showOrUpdateDetailButton(String isoA3) {
    safeSetState(() {
      _selectedCountryIsoA3 = isoA3;
      _showDetailBottom = true;
    });
    _detailButtonKey.currentState?.resetTimer();
  }

  void _hideDetailButton() {
    safeSetState(() => _showDetailBottom = false);
  }

  // Coach
  void _createCoach() {
    _coach = TutorialCoachMark(
      targets: _targets(),            // Order: Help → Refresh → My Location → Year → Legend → Stats
      colorShadow: Colors.black,
      opacityShadow: 0.6,
      paddingFocus: 10,
      textSkip: '',
      skipWidget: const SizedBox.shrink(),
      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      onFinish: () {},
      onSkip: () => true,
      pulseEnable: true,
      pulseAnimationDuration: const Duration(milliseconds: 600),
    );
  }

  void _showCoach() => _coach?.show(context: context);

  // Steps (Help → Refresh → My Location → Year → Legend → Stats)
  List<TargetFocus> _targets() {
    return [
      TargetFocus(
        identify: 'help',
        keyTarget: _keyHelp,
        shape: ShapeLightFocus.Circle,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Help',
              text:
                  'Tap this icon to start a short tutorial of this page. In this tour you will learn what each control does and how to read the map.\n\n'
                  'This is the Global Temperature Change (Heat Map). Historical data (1950–2023/2024) from ERA5 and future projections (2025–2100) from CMIP6 (SSP2-4.5) are visualized as anomalies relative to a baseline.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.help_outline,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'refresh',
        keyTarget: _keyRefresh,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Refresh',
              text:
                  'Hard reload this page from a clean state.\n\n'
                  'If something looks out of sync, tap here to rebuild the page and re-fetch visible data—without leaving this screen.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.refresh,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'my_location',
        keyTarget: _keyMyLocation,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'My Location',
              text:
                  'Center the map on your current position. If outside the global extent, a default area is used.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.my_location,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'year_selector',
        keyTarget: _keyYearSelector,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Year',
              text:
                  'Use this bar to select the year. The map and legend refresh instantly.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.date_range,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'legend',
        keyTarget: _keyLegend,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Legend',
              text:
                  'Colors encode anomaly relative to baseline: blue = cooler, yellow/orange = warmer, red/maroon = much warmer.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.color_lens_outlined,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'stats',
        keyTarget: _keyStats,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (ctx, controller) => _CoachTip(
              title: 'Statistics',
              text:
                  'Open the Statistics page to see top countries by anomaly and trends.',
              primary: 'Finish',
              onPrimary: controller.skip,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.analytics_outlined,
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const double statsButtonSize = 60;
    final bool _overlay = _isLoading || _isUpdatingYear;

    return KeyedSubtree(
      key: _pageInstanceKey,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Heat Map',
          centerTitle: true,
          showDrawer: false,
          leading: [
            IconButton(
              key: _keyHelp,
              icon: const Icon(Icons.help_outline),
              tooltip: 'Help',
              onPressed: _showCoach,
            ),
          ],
          actions: [
            IconButton(
              key: _keyMyLocation,
              icon: const Icon(Icons.my_location),
              tooltip: 'My location',
              onPressed: _goToUserLocation,
            ),
            IconButton(
              key: _keyRefresh, // coach step #2
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _onHardRefresh,
            ),
          ],
        ),

        body: Stack(
          children: [
            // Only build map and related widgets when overlay is off → avoids double loading
            if (!_overlay)
              HeatMapWidget(
                heatData: _heatData,
                hitNotifier: _hitNotifier,
                mapController: _mapController,
                bounds: bounds,
                mapCenter: mapCenter,
                colors: colors,
              ),

            if (_years.isNotEmpty)
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyedSubtree(
                      key: _keyYearSelector,
                      child: HorizontalYearSelector(
                        selectedYear: _selectedYear,
                        years: _years,
                        onYearSelected: _onYearSelected,
                      ),
                    ),
                    const SizedBox(height: 10),
                    KeyedSubtree(
                      key: _keyLegend,
                      child: ColorLegend(colors: colors, values: anomalyValues),
                    ),
                  ],
                ),
              ),

            if (!_overlay)
              Positioned(
                top: 90,
                left: 16,
                right: 16,
                child: _showDetailBottom
                    ? DetailBottomMapWidget(
                        key: ValueKey('${_selectedCountryIsoA3}_$_selectedYear'),
                        countryName: _selectedCountryIsoA3,
                        year: _selectedYear,
                        onClose: _hideDetailButton,
                        onTap: () {
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CountryDetailPage(
                                isoA3: _selectedCountryIsoA3,
                                year: _selectedYear,
                              ),
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(),
              ),

            if (!_overlay)
              KeyedSubtree(
                key: _keyStats,
                child: StatsSquareButton(
                  size: statsButtonSize,
                  onTap: () {
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StatisticsPage(year: _selectedYear),
                      ),
                    );
                  },
                ),
              ),

            // Single, centered overlay + touch blocker
            if (_overlay)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: Container(
                    color: Colors.black.withOpacity(0.08),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.0,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),

            // Hit notifier
            ValueListenableBuilder<LayerHitResult<Object>?>(
              valueListenable: _hitNotifier,
              builder: (context, hit, _) {
                if (hit != null && hit.hitValues.isNotEmpty) {
                  final isoA3 = hit.hitValues.first as String;
                  _hitNotifier.value = null;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _showOrUpdateDetailButton(isoA3);
                  });
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Coach tip (stable & lightweight) — with scrollbar and height cap
// ------------------------------------------------------------
class _CoachTip extends StatefulWidget {
  final String title;
  final String text;
  final String primary;
  final VoidCallback onPrimary;
  final String secondary;
  final VoidCallback onSecondary;
  final IconData icon;

  const _CoachTip({
    required this.title,
    required this.text,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.icon,
  });

  @override
  State<_CoachTip> createState() => _CoachTipState();
}

class _CoachTipState extends State<_CoachTip> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxW = size.width - 64;
    final maxH = size.height * 0.70; // Cap at 70% height to prevent ANR-like stalls

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // light glass effect
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Scrollable body with shared scrollbar controller
              Flexible(
                child: RawScrollbar(
                  controller: _scrollCtrl,
                  thumbVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(8),
                  thumbColor: Colors.white.withOpacity(0.3),
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      widget.text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: widget.onSecondary,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: widget.onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(widget.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
