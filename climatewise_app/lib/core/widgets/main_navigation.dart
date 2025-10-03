// lib/core/widgets/main_navigation.dart
import 'package:flutter/material.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';
import 'dart:async';

// Pages
import '../../modules/aqMap/screens/aq_map_page.dart';
import '../../modules/gasMap/screens/gas_map_page.dart';
import '../../modules/heatMap/screens/heat_map_page.dart';
import '../../modules/articles/screens/articles_page.dart';
import '../../modules/about/screens/about_page.dart';
import '../../modules/healthAdvisor/screens/health_advisor_page.dart';

// Push tap -> dialog wiring
import '../services/push_navigation_service.dart';
import 'notification_dialog.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  /// Number of tabs (keep in sync with bottom items).
  static const int _tabsCount = 6;

  /// Keep only visited tabs alive.
  final Set<int> _loadedTabs = {0};

  /// Cache for built pages.
  final List<Widget?> _pages = List<Widget?>.filled(
    _tabsCount,
    null,
    growable: false,
  );

  /// Subscription to push tap stream.
  late final StreamSubscription _pushSub;

  @override
  void initState() {
    super.initState();

    // 1) Listen for future push taps (when app is already running)
    _pushSub = PushNavigationService.I.stream.listen((_) {
      _handlePushIfAny();
    });

    // 2) Handle an initial pending push (e.g., app launched from terminated)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePushIfAny();
    });
  }

  @override
  void dispose() {
    _pushSub.cancel();
    super.dispose();
  }

  /// Reads and consumes the pending push message, then shows a dialog once.
  Future<void> _handlePushIfAny() async {
    if (!mounted) return;
    final pending = PushNavigationService.I.takePending();
    if (pending == null) return;

    // Optionally: switch to a specific tab before showing dialog.
    // For example, if your message indicates a tab by type/route, handle here.

    if (!mounted) return;
    await showNotificationDialog(context, pending);
  }

  /// Build page lazily when a tab is first visited.
  Widget _createPage(int index) {
    switch (index) {
      case 0:
        return const AqMapPage();
      case 1:
        return const HealthAdvisorPage();
      case 2:
        return const HeatMapPage();
      case 3:
        return const GasMapPage();
      case 4:
        return const ArticlesPage();
      case 5:
        return const AboutPage();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Returns cached page if loaded; otherwise a lightweight placeholder.
  Widget _childForIndex(int i) {
    if (_loadedTabs.contains(i)) {
      _pages[i] ??= _createPage(i);
      return _pages[i]!;
    }
    return const SizedBox.shrink();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
  }

  static const _kPages = <String, IconData>{
    'aq': Icons.cloud,
    'health': Icons.speed,
    'heat': Icons.thermostat,
    'ghg': Icons.factory,
    'blog': Icons.article,
    'about': Icons.info_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List<Widget>.generate(_tabsCount, _childForIndex),
      ),
      bottomNavigationBar: ConvexAppBar(
        initialActiveIndex: _currentIndex,
        style: TabStyle.reactCircle,
        backgroundColor: theme.primaryColor,
        items: [
          for (final entry in _kPages.entries)
            TabItem(icon: entry.value, title: entry.key),
        ],
        onTap: _onTabTapped,
      ),
    );
  }
}
