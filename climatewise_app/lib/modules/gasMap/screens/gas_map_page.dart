// lib/modules/gasMap/screens/gas_map_page.dart
// Single overlay loading + safe refresh + coach (Help → Refresh → My Location → Year → Legend → Stats)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/custom_app_bar.dart';
import '../data/gas_map_repository.dart';
import '../models/gas_data.dart';
import '../widgets/horizontal_year_selector.dart';
import '../widgets/color_legend.dart';
import '../widgets/gas_map_widget.dart';
import '../widgets/detail_buttom_map_widget.dart';
import '../widgets/stats_square_button.dart';
import 'country_detail_page.dart';
import 'statistics_page.dart';

class GasMapPage extends StatefulWidget {
  const GasMapPage({super.key});

  @override
  State<GasMapPage> createState() => _GasMapPageState();
}

class _GasMapPageState extends State<GasMapPage> {
  // ---------------------------
  // Map & data state
  // ---------------------------
  late MapController _mapController;
  final GasMapRepository _repository = GasMapRepository();

  List<GasData> _gasData = [];
  List<int> _years = [];
  int _selectedYear = 0;
  bool _isLoading = true;        // initial/page loading
  bool _isUpdatingYear = false;  // year change overlay

  // Country detail banner state
  bool _showDetailBottom = false;
  String _selectedCountryIsoA3 = '';
  final GlobalKey<DetailBottomMapWidgetState> _detailButtonKey = GlobalKey();

  // Polygon tap hit test
  final ValueNotifier<LayerHitResult<Object>?> _hitNotifier =
      ValueNotifier<LayerHitResult<Object>?>(null);

  // Legend palette
  final List<Color> colors = const [
    Color(0xFFFFFFFF),
    Color(0xFFE6F7E1),
    Color(0xFFD3F1A8),
    Color(0xFFB6D54A),
    Color(0xFF98C91A),
    Color(0xFF77B113),
    Color(0xFFEC7014),
    Color(0xFFEF6C1F),
    Color(0xFFBF360C),
    Color(0xFF9B1D1D),
  ];

  final List<String> gasValues = const [
    '0t', '10Mt', '30Mt', '100Mt', '300Mt',
    '1Bt', '3Bt', '10Bt', '30Bt', '50Bt',
  ];

  // World bounds & default center
  final LatLngBounds bounds = LatLngBounds(
    const LatLng(-85.0, -180.0),
    const LatLng(85.0, 180.0),
  );
  final LatLng mapCenter = const LatLng(40.7128, -74.0060);

  // ---------------------------
  // Coach marks
  // ---------------------------
  final GlobalKey _keyHelp = GlobalKey();
  final GlobalKey _keyRefresh = GlobalKey(); // step #2
  final GlobalKey _keyMyLocation = GlobalKey();
  final GlobalKey _keyYearSelector = GlobalKey();
  final GlobalKey _keyLegend = GlobalKey();
  final GlobalKey _keyStats = GlobalKey();

  TutorialCoachMark? _coach;

  /// Clean refresh key to fully remount subtree (safe hard reload)
  Key _pageInstanceKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initializeMapData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _createCoach());
  }

  @override
  void dispose() {
    _coach = null;
    _hitNotifier.dispose();
    super.dispose();
  }

  // ---------------------------
  // Data initialization
  // ---------------------------
  Future<void> _initializeMapData() async {
    try {
      final countryResponse = await _repository.fetchCountries();
      if (!mounted) return;
      _selectedYear = countryResponse['currentYear'] ?? 2023;
      _gasData = countryResponse['data'];

      final yearsList = await _repository.fetchYears();
      if (!mounted) return;
      setState(() {
        _years = yearsList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error initializing gas map: $e");
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ---------------------------
  // Full reset: like first boot (safe)
  // ---------------------------
  Future<void> _hardReloadLikeFirstBoot() async {
    if (!mounted) return;
    try {
      _coach?.skip();
    } catch (_) {}

    setState(() {
      _isLoading = true;
      _isUpdatingYear = false;

      _gasData = [];
      _years = [];
      _selectedYear = 0;

      _showDetailBottom = false;
      _selectedCountryIsoA3 = '';
      _hitNotifier.value = null;

      _pageInstanceKey = UniqueKey();
      _mapController = MapController();
    });

    await _initializeMapData();
    if (!mounted) return;
    _createCoach();
  }

  // ---------------------------
  // Location handler
  // ---------------------------
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Your location is outside the map extent!')),
            );
          }
        }
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location.')),
        );
      }
    }
  }

  // ---------------------------
  // Year selector callback
  // ---------------------------
  Future<void> _onYearSelected(int year) async {
    if (!mounted) return;
    setState(() => _isUpdatingYear = true);
    try {
      final countryResponse = await _repository.fetchCountries(year: year);
      if (!mounted) return;
      setState(() {
        _selectedYear = year;
        _gasData = countryResponse['data'];
        _isUpdatingYear = false;
      });
    } catch (e) {
      debugPrint('fetchCountries(year=$year) failed: $e');
      if (!mounted) return;
      setState(() => _isUpdatingYear = false);
    }
  }

  // ---------------------------
  // Country detail banner controls
  // ---------------------------
  void _showOrUpdateDetailButton(String isoA3) {
    if (!mounted) return;
    setState(() {
      _selectedCountryIsoA3 = isoA3;
      _showDetailBottom = true;
    });
    _detailButtonKey.currentState?.resetTimer();
  }

  void _hideDetailButton() {
    if (!mounted) return;
    setState(() => _showDetailBottom = false);
  }

  // ---------------------------
  // Coach setup
  // ---------------------------
  void _createCoach() {
    _coach = TutorialCoachMark(
      targets: _targets(), // Help → Refresh → My Location → Year → Legend → Stats
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
                  'Tap this icon to start a short guided tour about Gas Map controls.',
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
                  'Hard reload this page from a clean state. Data and layers are re-fetched like first boot.',
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
                  'Use this horizontal selector to choose the year; the map and legend update instantly.',
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
                  'Colors indicate the volume of emission data for each country. Match the map colors to understand the values.',
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
                  'Open the Statistics page for the selected year (top emitters, shares, etc.).',
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
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    const double statsButtonSize = 60;
    final bool overlay = _isLoading || _isUpdatingYear;

    return KeyedSubtree(
      key: _pageInstanceKey,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'GHG Map',
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
              key: _keyRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _hardReloadLikeFirstBoot,
            ),
          ],
        ),

        body: Stack(
          children: [
            // Render map only when overlay is NOT visible (prevents double spinners)
            if (!overlay)
              GasMapWidget(
                gasData: _gasData,
                hitNotifier: _hitNotifier,
                mapController: _mapController,
                bounds: bounds,
                mapCenter: mapCenter,
                colors: colors,
              ),

            // Year selector + Legend
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
                      child: ColorLegend(colors: colors, values: gasValues),
                    ),
                  ],
                ),
              ),

            // Country detail banner
            if (!overlay)
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

            // Stats button
            if (!overlay)
              KeyedSubtree(
                key: _keyStats,
                child: StatsSquareButton(
                  size: statsButtonSize,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StatisticsPage(year: _selectedYear),
                      ),
                    );
                  },
                ),
              ),

            // Centered loading overlay (initial + year change)
            if (overlay)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: Container(
                    color: Colors.black.withOpacity(0.08),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),

            // OSM attribution badge (required by OSM terms)
            const _OsmAttributionBadge(),

            // Polygon hits → open/update bottom detail banner
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
// Coach tip (glass card with shared ScrollController)
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
    final maxH = size.height * 0.70;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

// ------------------------------------------------------------
// OSM Attribution badge (bottom-left, 30% black background, "@ OSM")
// ------------------------------------------------------------
class _OsmAttributionBadge extends StatelessWidget {
  const _OsmAttributionBadge();

  static final Uri _osmCopyright =
      Uri.parse('https://www.openstreetmap.org/copyright');

  Future<void> _openAttribution() async {
    await launchUrl(_osmCopyright, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      bottom: 12,

child: SafeArea(
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.3), // 30% black background
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      '@ OSM',
      style: TextStyle(
        fontSize: 11.5,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
),

    );
  }
}
