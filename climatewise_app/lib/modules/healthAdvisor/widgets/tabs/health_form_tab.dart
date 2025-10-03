// lib/modules/healthAdvisor/widgets/tabs/health_form_tab.dart
// Attach coach key to the DISEASES SECTION HEADER (not the long list).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/health_form.dart';
import '../../controllers/health_advisor_controller.dart';

import '../map_picker.dart';
import '../speedometer.dart';
import '../disease_widgets.dart';
import '../alerts_widgets.dart';
import '../form_controls.dart';

class HealthFormTab extends StatefulWidget {
  const HealthFormTab({
    super.key,
    this.onSubmitSuccess,

    // Coach-mark keys (all optional)
    this.coachMapKey,
    this.coachNameKey,
    this.coachSensitivityKey,
    this.coachGaugeKey,
    this.coachDiseasesKey, // <- will be placed on the header
    this.coachAlertsKey,
    this.coachSubmitKey,
  });

  final VoidCallback? onSubmitSuccess;

  // Coach-mark attachment points
  final Key? coachMapKey;
  final Key? coachNameKey;
  final Key? coachSensitivityKey;
  final Key? coachGaugeKey;
  final Key? coachDiseasesKey; // header anchor
  final Key? coachAlertsKey;
  final Key? coachSubmitKey;

  @override
  State<HealthFormTab> createState() => _HealthFormTabState();
}

enum Sensitivity { sensitive, normal, relaxed }

const LatLng kDefaultCenter = LatLng(40.7128, -74.0060);

class _HealthFormTabState extends State<HealthFormTab> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final _nameFieldKey = GlobalKey();
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();

  final _mapController = MapController();
  LatLng _selectedLatLng = kDefaultCenter;
  bool _hasSelection = false;

  Sensitivity _sensitivity = Sensitivity.normal;

  bool _pollutionNotifOn = false;
  final Set<int> _selectedHours2h = {};
  bool _soundOn = true;

  bool _isSubmitting = false;

  final List<DiseaseSpec> _diseaseCatalog = const [
    DiseaseSpec(id: 'asthma', name: 'Asthma', weights: {'no2': 0.50, 'hcho': 0.35, 'o3tot': 0.15}),
    DiseaseSpec(id: 'copd', name: 'COPD', weights: {'no2': 0.45, 'hcho': 0.25, 'o3tot': 0.30}),
    DiseaseSpec(id: 'cvd', name: 'Cardiovascular disease', weights: {'no2': 0.55, 'hcho': 0.20, 'o3tot': 0.25}),
    DiseaseSpec(id: 'children', name: 'Children', weights: {'no2': 0.45, 'hcho': 0.35, 'o3tot': 0.20}),
    DiseaseSpec(id: 'pregnancy', name: 'Pregnancy', weights: {'no2': 0.40, 'hcho': 0.30, 'o3tot': 0.30}),
    DiseaseSpec(id: 'elderly', name: 'Elderly', weights: {'no2': 0.40, 'hcho': 0.25, 'o3tot': 0.35}),
    DiseaseSpec(id: 'allergies', name: 'Allergic rhinitis', weights: {'no2': 0.30, 'hcho': 0.45, 'o3tot': 0.25}),
    DiseaseSpec(id: 'lung_cancer_longterm', name: 'Long-term lung risk', weights: {'no2': 0.35, 'hcho': 0.45, 'o3tot': 0.20}),
    DiseaseSpec(id: 'athletes', name: 'Outdoor athletes', weights: {'no2': 0.35, 'hcho': 0.25, 'o3tot': 0.40}),
    DiseaseSpec(id: 'general', name: 'General population', weights: {'no2': 0.40, 'hcho': 0.30, 'o3tot': 0.30}),
  ];
  final Map<String, bool> _diseaseSelected = {};

  @override
  void initState() {
    super.initState();
    _diseaseSelected['asthma'] = true;
    _diseaseSelected['allergies'] = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, double> _scoresForSensitivity(Sensitivity s) {
    final double v = switch (s) {
      Sensitivity.sensitive => 2.0,
      Sensitivity.normal => 6.0,
      Sensitivity.relaxed => 8.5,
    };
    return {'no2': v, 'hcho': v, 'o3tot': v};
  }

  double get _no2Score10 => _scoresForSensitivity(_sensitivity)['no2']!;
  double get _hchoScore10 => _scoresForSensitivity(_sensitivity)['hcho']!;
  double get _o3Score10 => _scoresForSensitivity(_sensitivity)['o3tot']!;

  Color _colorForScore(double s10) {
    switch (_sensitivity) {
      case Sensitivity.sensitive:
        return s10 <= 3 ? Colors.green : s10 <= 5 ? Colors.orange : Colors.red;
      case Sensitivity.normal:
        return s10 <= 4 ? Colors.green : s10 <= 7 ? Colors.orange : Colors.red;
      case Sensitivity.relaxed:
        return s10 <= 5 ? Colors.green : s10 <= 8 ? Colors.orange : Colors.red;
    }
  }

  Color _colorForRisk100(int r) => _colorForScore(r / 10.0);

  double get _overallHealthScore100 {
    final s10 = (_no2Score10 * 0.5 + _hchoScore10 * 0.25 + _o3Score10 * 0.25);
    return (s10 * 10.0).clamp(0.0, 100.0);
  }

  String get _overallAdvice {
    final v = _overallHealthScore100;
    if (v < 34) return 'Low • Enjoy normal outdoor activities.';
    if (v < 67) return 'Moderate • Consider reducing long outdoor activity.';
    return 'High • Limit outdoor exposure.';
  }

  bool _diseaseEnabled(DiseaseSpec d) => d.weights.values.where((w) => w > 0).isNotEmpty;

  int _diseaseRisk100(DiseaseSpec d) {
    double acc = 0.0, wacc = 0.0;
    void add(String p, double s10, double w) {
      if (w > 0) {
        acc += w * (s10 * 10.0);
        wacc += w;
      }
    }

    add('no2', _no2Score10, d.weights['no2'] ?? 0);
    add('hcho', _hchoScore10, d.weights['hcho'] ?? 0);
    add('o3tot', _o3Score10, d.weights['o3tot'] ?? 0);
    if (wacc <= 0) return 0;
    return (acc / wacc).round().clamp(0, 100);
  }

  static String _formatHour12(int hour24) {
    final h = hour24 % 24;
    final am = h < 12;
    final base = h % 12 == 0 ? 12 : h % 12;
    return '$base ${am ? 'AM' : 'PM'}';
  }

  void _scrollToNameField() {
    final ctx = _nameFieldKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: .2, duration: const Duration(milliseconds: 400));
    }
    _nameFocus.requestFocus();
  }

  void _resetFormToDefaults() {
    _formKey.currentState?.reset();
    _nameCtrl.clear();
    _nameFocus.unfocus();

    _selectedLatLng = kDefaultCenter;
    _hasSelection = false;
    _mapController.move(kDefaultCenter, 3);

    _sensitivity = Sensitivity.normal;
    _pollutionNotifOn = false;
    _soundOn = true;
    _selectedHours2h.clear();

    _diseaseSelected
      ..clear()
      ..addAll({'asthma': true, 'allergies': true});

    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _scrollToNameField();
      return;
    }

    final selectedDiseases = _diseaseSelected.entries.where((e) => e.value).map((e) => e.key).toList();
    final alerts = Alerts(
      pollution: _pollutionNotifOn,
      sound: _soundOn,
      hours2h: _selectedHours2h.toList()..sort(),
    );

    final form = HealthForm(
      name: _nameCtrl.text.trim(),
      location: LatLng(
        double.parse(_selectedLatLng.latitude.toStringAsFixed(4)),
        double.parse(_selectedLatLng.longitude.toStringAsFixed(4)),
      ),
      sensitivity: _sensitivity.name,
      diseases: selectedDiseases,
      overallScore: _overallHealthScore100.round(),
      alerts: alerts,
    );

    final ctrl = context.read<HealthAdvisorController>();
    setState(() => _isSubmitting = true);
    final ok = await ctrl.submitHealthForm(form);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();

    if (ok) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Form submitted successfully ✅'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(12, 12, 12, 0),
        dismissDirection: DismissDirection.up,
      ));

      setState(_resetFormToDefaults);
      widget.onSubmitSuccess?.call();
    } else {
      if (ctrl.lastStatus == 422 && ctrl.hasError('name')) _scrollToNameField();
      messenger.showSnackBar(SnackBar(
        content: Text('Error: ${ctrl.errorMessage ?? 'Unknown error'}'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        dismissDirection: DismissDirection.up,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLL = _selectedLatLng;
    final serverNameError = context.watch<HealthAdvisorController>().firstError('name');

    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26, width: .8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionTitle('Map & Coordinates'),
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: widget.coachMapKey,
                      child: MapLatLonPicker(
                        controller: _mapController,
                        current: currentLL,
                        hasSelection: _hasSelection,
                        defaultCenter: kDefaultCenter,
                        onOpenFullscreen: () async {
                          final picked = await Navigator.push<LatLng?>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullscreenMapPicker(initial: currentLL),
                              fullscreenDialog: true,
                            ),
                          );
                          if (picked != null) {
                            final clamped = clampToNorthAmerica(picked);
                            setState(() {
                              _hasSelection = true;
                              _selectedLatLng = clamped;
                            });
                            _mapController.move(clamped, 10);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    LatLonRow(latLng: currentLL),

                    const SizedBox(height: 24),
                    sectionTitle('Name'),
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: widget.coachNameKey,
                      child: NameField(
                        key: _nameFieldKey,
                        controller: _nameCtrl,
                        focusNode: _nameFocus,
                        serverErrorText: serverNameError,
                      ),
                    ),

                    const SizedBox(height: 24),
                    sectionTitle('Health'),
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: widget.coachSensitivityKey,
                      child: SensitivitySegment(
                        value: _sensitivity,
                        onChanged: (s) => setState(() => _sensitivity = s),
                      ),
                    ),
                    const SizedBox(height: 12),
                    KeyedSubtree(
                      key: widget.coachGaugeKey,
                      child: SpeedometerGauge(
                        value0to100: _overallHealthScore100,
                        label: _overallAdvice,
                        color: _colorForRisk100(_overallHealthScore100.round()),
                        maxHeight: 220,
                        duration: const Duration(milliseconds: 500),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // >>> Attach coach key to the header (short anchor)
                    KeyedSubtree(
                      key: widget.coachDiseasesKey,
                      child: sectionTitle('Disease risks'),
                    ),
                    const SizedBox(height: 8),

                    // Long list WITHOUT the coach key
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _diseaseCatalog.map((d) {
                        final enabled = _diseaseEnabled(d);
                        final risk = _diseaseRisk100(d);
                        final sel = _diseaseSelected[d.id] ?? false;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: RiskChipCard(
                            title: d.name,
                            risk0to100: risk,
                            selected: sel && enabled,
                            onChanged: enabled
                                ? (v) => setState(() => _diseaseSelected[d.id] = v ?? false)
                                : null,
                            color: _colorForRisk100(risk),
                            enabled: enabled,
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),
                    sectionTitle('Alerts'),
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: widget.coachAlertsKey,
                      child: Column(
                        children: [
                          AlertSwitchRow(
                            title: 'Air pollution notifications',
                            value: _pollutionNotifOn,
                            onChanged: (v) => setState(() => _pollutionNotifOn = v),
                          ),
                          const SizedBox(height: 8),
                          AlertsTwoHourGroup(
                            selected: _selectedHours2h,
                            maxSelections: 5,
                            formatHourLabel: _formatHour12,
                            onToggle: (h) {
                              setState(() {
                                const limit = 5;
                                if (_selectedHours2h.contains(h)) {
                                  _selectedHours2h.remove(h);
                                } else if (_selectedHours2h.length < limit) {
                                  _selectedHours2h.add(h);
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          AlertSwitchRow(
                            title: 'Sound alarm',
                            value: _soundOn,
                            onChanged: (v) => setState(() => _soundOn = v),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: KeyedSubtree(
        key: widget.coachSubmitKey,
        child: FloatingActionButton.extended(
          heroTag: 'health_form_submit',
          onPressed: _isSubmitting ? null : _submit,
          tooltip: 'Submit health form',
          icon: _isSubmitting ? null : const Icon(Icons.check_rounded),
          label: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Submit'),
          backgroundColor: const Color(0xFF0EA5A5),
          foregroundColor: Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white24, width: 1),
          ),
        ),
      ),
    );
  }
}
