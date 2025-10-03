// lib/modules/healthAdvisor/screens/health_advisor_page.dart
// Health Advisor Page with Coach Marks (tutorial_coach_mark)
// Order: Help → Form Tab → Saved Tab → Map → Name → Sensitivity → Gauge → Diseases → Alerts → Submit

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../controllers/health_advisor_controller.dart';
import '../widgets/tabs/health_form_tab.dart';
import '../widgets/tabs/health_saved_tab.dart';

class HealthAdvisorPage extends StatefulWidget {
  const HealthAdvisorPage({super.key});

  @override
  State<HealthAdvisorPage> createState() => _HealthAdvisorPageState();
}

class _HealthAdvisorPageState extends State<HealthAdvisorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- Coach targets keys (AppBar + Tabs) ---
  final GlobalKey _keyHelp = GlobalKey();
  final GlobalKey _keyTabForm = GlobalKey();
  final GlobalKey _keyTabSaved = GlobalKey();

  // --- Coach targets keys (inside Form tab) ---
  final GlobalKey _keyMap = GlobalKey(debugLabel: 'map');
  final GlobalKey _keyName = GlobalKey(debugLabel: 'name');
  final GlobalKey _keySensitivity = GlobalKey(debugLabel: 'sensitivity');
  final GlobalKey _keyGauge = GlobalKey(debugLabel: 'gauge');
  final GlobalKey _keyDiseases = GlobalKey(debugLabel: 'diseases_header'); // <- header anchor
  final GlobalKey _keyAlerts = GlobalKey(debugLabel: 'alerts');
  final GlobalKey _keySubmit = GlobalKey(debugLabel: 'submit');

  late TutorialCoachMark _coach;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _createCoach());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Smoothly ensure a keyed widget is visible before moving to next step.
  Future<void> _ensureOnScreen(GlobalKey key, {double alignment = .1}) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await Scrollable.ensureVisible(
      ctx,
      alignment: alignment,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
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
                  'Welcome to Health Advisor. This short tour explains the form, how risks are calculated, and where to view your saved results.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.help_outline,
            ),
          ),
        ],
      ),

      // 2) Form Tab
      TargetFocus(
        identify: 'tab_form',
        keyTarget: _keyTabForm,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Form',
              text:
                  'Start here: pick a location, set your sensitivity, and select relevant conditions. Then submit to get a tailored health assessment.',
              primary: 'Next',
              onPrimary: controller.next,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.assignment_outlined,
            ),
          ),
        ],
      ),

      // 3) Saved Tab
      TargetFocus(
        identify: 'tab_saved',
        keyTarget: _keyTabSaved,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Saved',
              text:
                  'Your submitted assessments appear here. You can search, sort, and revisit past entries anytime.',
              primary: 'Next',
              onPrimary: () async {
                _tabController.animateTo(0);
                await Future<void>.delayed(const Duration(milliseconds: 180));
                await _ensureOnScreen(_keyMap);
                controller.next();
              },
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.bookmark_border,
            ),
          ),
        ],
      ),

      // 4) Map
      TargetFocus(
        identify: 'map',
        keyTarget: _keyMap,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Map & Coordinates',
              text:
                  'Choose your point of interest. Use fullscreen to refine your selection; coordinates are clamped to North America.',
              primary: 'Next',
              onPrimary: () async {
                await _ensureOnScreen(_keyName);
                controller.next();
              },
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.map_outlined,
            ),
          ),
        ],
      ),

      // 5) Name
      TargetFocus(
        identify: 'name',
        keyTarget: _keyName,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Name',
              text:
                  'Optional label for this assessment (e.g., “Home”, “Office”, or a person’s name).',
              primary: 'Next',
              onPrimary: () async {
                await _ensureOnScreen(_keySensitivity);
                controller.next();
              },
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.badge_outlined,
            ),
          ),
        ],
      ),

      // 6) Sensitivity
      TargetFocus(
        identify: 'sensitivity',
        keyTarget: _keySensitivity,
        shape: ShapeLightFocus.RRect,
        radius: 10,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Sensitivity',
              text:
                  'Pick how sensitive you are to pollution. This shifts thresholds used to color risks (green/orange/red).',
              primary: 'Next',
              onPrimary: () async {
                await _ensureOnScreen(_keyGauge);
                controller.next();
              },
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.tune,
            ),
          ),
        ],
      ),

      // 7) Gauge
      TargetFocus(
        identify: 'gauge',
        keyTarget: _keyGauge,
        shape: ShapeLightFocus.RRect,
        radius: 14,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Overall Score',
              text:
                  'A combined 0–100 score (weighted NO₂/HCHO/O₃) with practical advice. Higher = more caution.',
              primary: 'Next',
              onPrimary: () async {
                // Put the diseases header near the top so there is room below for the tip
                await _ensureOnScreen(_keyDiseases, alignment: .05);
                controller.next();
              },
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.speed,
            ),
          ),
        ],
      ),

      // 8) Diseases — focus the HEADER anchor, not the long list
      TargetFocus(
        identify: 'diseases',
        keyTarget: _keyDiseases,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (ctx, controller) => _CoachTip(
              title: 'Disease Risks',
              text:
                  'Toggle conditions that apply to you. Each risk is computed from pollutant-specific weights tuned per condition.',
              primary: 'Next',
              onPrimary: () async {
                await _ensureOnScreen(_keyAlerts, alignment: .05);
                controller.next();
              },
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.health_and_safety_outlined,
            ),
          ),
        ],
      ),

      // 9) Alerts
      TargetFocus(
        identify: 'alerts',
        keyTarget: _keyAlerts,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (ctx, controller) => _CoachTip(
              title: 'Alerts',
              text:
                  'Enable pollution notifications and optional sound. Pick up to 5 two-hour windows to be notified.',
              primary: 'Next',
              onPrimary: () async {
                await _ensureOnScreen(_keySubmit, alignment: 1.0);
                controller.next();
              },
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.notifications_active_outlined,
            ),
          ),
        ],
      ),

      // 10) Submit
      TargetFocus(
        identify: 'submit',
        keyTarget: _keySubmit,
        shape: ShapeLightFocus.RRect,
        radius: 16,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (ctx, controller) => _CoachTip(
              title: 'Submit',
              text:
                  'Validate and send your assessment. On success, you’ll be navigated to the Saved tab.',
              primary: 'Finish',
              onPrimary: controller.skip,
              secondary: 'Skip',
              onSecondary: controller.skip,
              icon: Icons.check_circle_outline,
            ),
          ),
        ],
      ),
    ];
  }

  void _goToSavedTab() {
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HealthAdvisorController(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Health Advisor'),
          leading: IconButton(
            key: _keyHelp,
            tooltip: 'Help',
            icon: const Icon(Icons.help_outline),
            onPressed: _showCoach,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: Colors.grey[200],
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.black87,
                unselectedLabelColor: Colors.black54,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: [
                  Tab(key: _keyTabForm, text: 'Form'),
                  Tab(key: _keyTabSaved, text: 'Saved'),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            HealthFormTab(
              onSubmitSuccess: _goToSavedTab,
              coachMapKey: _keyMap,
              coachNameKey: _keyName,
              coachSensitivityKey: _keySensitivity,
              coachGaugeKey: _keyGauge,
              coachDiseasesKey: _keyDiseases, // header anchor
              coachAlertsKey: _keyAlerts,
              coachSubmitKey: _keySubmit,
            ),
            const HealthSavedTab(),
          ],
        ),
      ),
    );
  }
}

/// Minimal "glass" tip with centered actions and scrollable body.
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
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
