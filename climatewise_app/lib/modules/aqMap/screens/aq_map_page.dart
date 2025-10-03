// AQ Map Page with Coach Marks (tutorial_coach_mark)
// Order: Help → Refresh → My Location → Product Selector → Timeline → Legend → AppStatus → Zoom → PointAssess
// AppBar: Help (left), centered title, Refresh + MyLocation (right)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/widgets/custom_app_bar.dart';
import '../controllers/aq_map_controller.dart';
import '../data/aq_map_repository.dart';
import '../widgets/aq_map_widget.dart';

class AqMapPage extends StatefulWidget {
  const AqMapPage({super.key});

  @override
  State<AqMapPage> createState() => _AqMapPageState();
}

class _AqMapPageState extends State<AqMapPage> {
  // --- Coach targets keys ---
  final GlobalKey _keyHelp = GlobalKey();
  final GlobalKey _keyRefresh = GlobalKey();
  final GlobalKey _keyMyLocation = GlobalKey();
  final GlobalKey _keyProduct = GlobalKey();
  final GlobalKey _keyTimeline = GlobalKey();
  final GlobalKey _keyLegend = GlobalKey();
  final GlobalKey _keyAppStatus = GlobalKey();
  final GlobalKey _keyZoom = GlobalKey();
  final GlobalKey _keyPointAssess = GlobalKey();

  // NA bounds
  static const double _naSouth = 15.0,
      _naNorth = 75.0,
      _naWest = -170.0,
      _naEast = -50.0;
  bool _isInNA(double lat, double lon) =>
      lat >= _naSouth && lat <= _naNorth && lon >= _naWest && lon <= _naEast;

  late TutorialCoachMark _coach;

  /// Key that wraps the whole provider subtree.
  /// Changing this forces a full rebuild (fresh state) without leaving the route.
  Key _pageInstanceKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _createCoach());
  }

  // ---------------------------
  // Hard refresh: rebuild the entire subtree (Provider + Controller)
  // ---------------------------
  void _onHardRefresh() {
    setState(() {
      _pageInstanceKey = UniqueKey(); // dispose old subtree, build a new one
    });
    // Recreate coach after the fresh subtree is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) => _createCoach());
  }

  void _createCoach() {
    _coach = TutorialCoachMark(
      targets: _targets(),
      colorShadow: Colors.black,
      opacityShadow: 0.6,
      paddingFocus: 10,
      textSkip: '',
      skipWidget: const SizedBox.shrink(),
      imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      onFinish: () {},
      onSkip: () => true,
      pulseEnable: true,
      pulseAnimationDuration: const Duration(milliseconds: 600),
    );
  }

  void _showCoach() => _coach.show(context: context);

  // ---------------------------
  // Coach targets (with refresh as step #2)
  // ---------------------------
  List<TargetFocus> _targets() {
    return [
      // 1) Help
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
                  'Tap this icon to start a short tour of the page. You will learn each control and how to read the map effectively.\n\n'
                  'This part of the app is not just a map; it’s a scientific, educational, and practical tool for everyday people across North America. '
                  'It visualizes NASA TEMPO satellite observations, mixes them with ground stations (AirNow, OpenAQ), and uses weather inputs (Meteo) to provide both recent history and short-term forecasts.\n\n'
                  'Mark your location and the app can tailor alerts and guidance. Think of it as an intelligent air-quality assistant in your pocket.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.help_outline,
            ),
          ),
        ],
      ),

      // 2) Refresh (hard reload)
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
                  'Fully reload this page.\n\n'
                  'Use this when things look out of sync. It rebuilds the controller and re-fetches visible data/layers from scratch (clean state) without leaving the current route.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.refresh,
            ),
          ),
        ],
      ),

      // 3) My Location
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
                  'Center the map on your current position. If you’re inside North America, the map zooms to your spot; otherwise it jumps to Manhattan as a safe default.\n\n'
                  'This helps you check air quality for your city, neighborhood, or exact point—comparing satellite and ground data for a personal view.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.my_location,
            ),
          ),
        ],
      ),

      // 4) Product selector
      TargetFocus(
        identify: 'product',
        keyTarget: _keyProduct,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Product',
              text:
                  'Pick which air-quality layer to view:\n\n'
                  '• NO₂ — traffic/industry; lung irritant.\n'
                  '• HCHO — formaldehyde; industry/wildfire chemistry.\n'
                  '• O₃ Total — total ozone.\n'
                  '• CLDO₄ — cloud cover (may affect satellite accuracy).\n\n'
                  'OFF hides overlays for a clean base map.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.layers,
            ),
          ),
        ],
      ),

      // 5) Timeline
      TargetFocus(
        identify: 'timeline',
        keyTarget: _keyTimeline,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Time',
              text:
                  'Explore the last 3 days and short-term forecasts.\n\n'
                  '• Past: hourly TEMPO observations.\n'
                  '• Forecast: blends satellite, ground stations, and weather to estimate upcoming air quality.\n\n'
                  'Tip: low zoom shows a broad PNG overlay; zoom 8+ switches to detailed JSON grids.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.timeline,
            ),
          ),
        ],
      ),

      // 6) Legend
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
                  'Color scale from lower (left) to higher (right). Cooler colors = lower values; warmer colors = higher values.\n\n'
                  'Numeric ticks come from the server legend endpoint and match the current product and units.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.color_lens_outlined,
            ),
          ),
        ],
      ),

      // 7) AppStatus
      TargetFocus(
        identify: 'app_status',
        keyTarget: _keyAppStatus,
        shape: ShapeLightFocus.RRect,
        radius: 16,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (ctx, controller) => _CoachTip(
              title: 'Status',
              text:
                  'Quick summary: day/night, data freshness, current product & units, last update time, and sources (TEMPO, AirNow, OpenAQ, Meteo).',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.info_outline,
            ),
          ),
        ],
      ),

      // 8) Zoom
      TargetFocus(
        identify: 'zoom',
        keyTarget: _keyZoom,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (ctx, controller) => _CoachTip(
              title: 'Zoom',
              text:
                  'Tap to open +/− controls or pinch to zoom. Up to z8 shows a broad overlay; z8+ reveals finer grids; z9+ shows ground stations.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.zoom_in_map,
            ),
          ),
        ],
      ),

      // 9) Point Assess
      TargetFocus(
        identify: 'point_assess',
        keyTarget: _keyPointAssess,
        shape: ShapeLightFocus.RRect,
        radius: 14,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (ctx, controller) => _CoachTip(
              title: 'Point Assess',
              text:
                  'Analyzes the exact center crosshair location and returns a short-term report (now → +12h): overall score, practical advice, and health insights—blending satellite, ground, and weather data.',
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

  // ---------------------------
  // Location logic
  // ---------------------------
  Future<void> _goToUserOrManhattan(BuildContext innerCtx) async {
    final c = innerCtx.read<AqMapController>();
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      c.jumpToManhattan();
      c.refreshAppStatus();
      if (!mounted) return;
      _toast(innerCtx, 'Location permission denied. Jumped to Manhattan.');
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      final lat = pos.latitude, lon = pos.longitude;
      if (_isInNA(lat, lon)) {
        c.setCenterZoom(lat, lon, 9.0);
      } else {
        c.jumpToManhattan();
        if (!mounted) return;
        _toast(innerCtx, 'Outside North America → Manhattan.');
      }
      c.refreshAppStatus();
    } catch (_) {
      c.jumpToManhattan();
      c.refreshAppStatus();
      if (!mounted) return;
      _toast(innerCtx, 'Could not get location → Manhattan.');
    }
  }

  void _toast(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    return KeyedSubtree( // <- hard-reload target
      key: _pageInstanceKey,
      child: ChangeNotifierProvider<AqMapController>(
        create: (_) {
          final c = AqMapController(repository: AqMapRepository());
          c.refreshAppStatus();
          c.startAutoRefresh();
          c.setProduct('no2');
          c.loadOverlayTimes(product: 'no2');
          return c;
        },
        child: Builder(
          builder: (innerCtx) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _createCoach());

            return Scaffold(
              appBar: CustomAppBar(
                title: 'Air Quality Map',
                centerTitle: true,
                showDrawer: false,
                // Left (leading): Help
                leading: [
                  IconButton(
                    key: _keyHelp,
                    tooltip: 'Help',
                    icon: const Icon(Icons.help_outline),
                    onPressed: _showCoach,
                  ),
                ],
                // Right (actions): Refresh, My Location
                actions: [
                  IconButton(
                    key: _keyMyLocation,
                    tooltip: 'My location',
                    icon: const Icon(Icons.my_location),
                    onPressed: () => _goToUserOrManhattan(innerCtx),
                  ),
                  IconButton(
                    key: _keyRefresh,
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: _onHardRefresh,
                  ),
                  
                ],
              ),
              body: AQMapWidget(
                productSelectorKey: _keyProduct,
                timelineKey: _keyTimeline,
                legendKey: _keyLegend,
                appStatusKey: _keyAppStatus,
                zoomIndicatorKey: _keyZoom,
                pointAssessKey: _keyPointAssess,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Minimal "glass" tip with centered bottom actions + scrollable body with visible scrollbar.

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
    final maxH = size.height * 0.70; // سقف ۷۰٪ ارتفاع برای جلوگیری از ANR

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // شیشه‌ای سبک
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

              // Scrollable body with scrollbar
              Flexible(
                child: RawScrollbar(
                  controller: _scrollCtrl,        // 👈 کنترلر مشترک
                  thumbVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(8),
                  thumbColor: Colors.white.withOpacity(0.3),
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,      // 👈 همان کنترلر
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
