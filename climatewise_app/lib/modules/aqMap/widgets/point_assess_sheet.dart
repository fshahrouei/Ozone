// lib/modules/aqMap/widgets/point_assess_sheet.dart
import 'dart:math' as math;
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/aq_map_controller.dart';
import '../models/point_assess.dart';
import '../../../core/tts/tts_service.dart'; // <-- TTS for reading overall advisory

class PointAssessSheet extends StatefulWidget {
  final AqMapController controller;
  final LatLng? point; // optional: if null, use map center
  final int? tHours;   // optional: if null, use controller or 0
  final Map<String, double>? weights;

  const PointAssessSheet({
    super.key,
    required this.controller,
    this.point,
    this.tHours,
    this.weights,
  });

  @override
  State<PointAssessSheet> createState() => _PointAssessSheetState();
}

class _PointAssessSheetState extends State<PointAssessSheet> {
  @override
  void initState() {
    super.initState();
    // Kick off the fetch right after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.fetchPointAssessAt(
        widget.point ?? widget.controller.center,
        tHours: widget.tHours ?? widget.controller.selectedForecastHour ?? 0,
        weights: widget.weights,
        debug: false,
        noCache: false,
      );
    });
  }

  void _closeSheet() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.42,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final loading = widget.controller.pointAssessLoading;
            final resp = widget.controller.pointAssess;
            final err  = widget.controller.pointAssessError;
            final at   = widget.controller.pointAssessAt;

            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [BoxShadow(blurRadius: 12, spreadRadius: 0, color: Colors.black26)],
              ),
              child: Stack(
                children: [
                  // Main body
                  Positioned.fill(
                    child: loading
                        ? _buildLoading(theme, at)
                        : (err != null
                            ? _buildError(theme, err, at)
                            : (resp == null
                                ? _buildEmpty(theme)
                                : _buildContent(theme, scrollController, resp))),
                  ),

                  // Global Close (upper-right)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'Close',
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                      ),
                      onPressed: _closeSheet,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ========= Enhanced loading with non-looping step sequence =========
  Widget _buildLoading(ThemeData theme, LatLng? at) {
    final String pointText = (at != null)
        ? '${at.latitude.toStringAsFixed(2)}, ${at.longitude.toStringAsFixed(2)}'
        : '—';

    // Title depends on forecast horizon
    final int h = widget.controller.selectedForecastHour ?? 0;
    final bool isFuture = widget.controller.isForecast && h > 0;
    final String dynamicTitle = isFuture
        ? 'Assessing point +${h}h on server'
        : 'Assessing point (now) on server';

    // EN steps (non-looping). Last step slows down.
    final steps = <String>[
      'Computing TEMPO for last 3 days…',
      'Processing stations for last 3 days…',
      'Reading weather data…',
      'Merging datasets and calculating…',
      'Preparing final response…',
    ];

    return _LoadingSequenceCard(
      title: dynamicTitle,
      subtitle: pointText == '—' ? 'Preparing coordinates…' : 'Point: $pointText',
      steps: steps,
      stepDuration: const Duration(seconds: 4),
      lastStepExtra: const Duration(seconds: 9),
    );
  }

  Widget _buildError(ThemeData theme, String err, LatLng? at) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to fetch point assessment', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(err, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                widget.controller.fetchPointAssessAt(
                  at ?? widget.controller.center,
                  tHours: widget.controller.pointAssessTHours,
                  weights: widget.controller.pointAssessWeights,
                );
              },
              child: const Text('Retry'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Text('No data to display', style: theme.textTheme.bodyMedium),
    );
  }

  Widget _buildContent(ThemeData theme, ScrollController sc, PointAssessResponse data) {
    final overall  = data.overall;
    final products = data.products;
    final health   = data.health;

    // Sort products by score_10 DESC safely.
    final sortedProductKeys = products.keys.toList()
      ..sort((a, b) {
        final av = _finiteOr(products[a]?.score?.score10, 0);
        final bv = _finiteOr(products[b]?.score?.score10, 0);
        return bv.compareTo(av);
      });

    // Sort risks by risk0to100 DESC safely (show ALL, no hiding).
    final risks = List<DiseaseRisk>.from(health?.risks ?? const [])
      ..sort((a, b) => _finiteOr(b.risk0to100, 0).compareTo(_finiteOr(a.risk0to100, 0)));

    final at = widget.controller.pointAssessAt;
    final h  = widget.controller.pointAssessTHours;

    return ListView(
      controller: sc,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SheetHandle(),
        const SizedBox(height: 6),

        // Header: point + horizon
        Row(
          children: [
            Icon(Icons.location_on, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              at != null
                ? 'Point: ${at.latitude.toStringAsFixed(2)}, ${at.longitude.toStringAsFixed(2)}'
                : 'Selected point',
              style: theme.textTheme.labelLarge,
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 50),
              child: _horizonChip(h, theme),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (data.meta?.partial == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Some products had no data (partial).', style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),

        // SECTION 1: Overall
        _SectionCard(
          title: 'Overall',
          subtitle: overall?.recommendedActions?.level,
          child: _OverallDonut(
            score100: _finiteOr(overall?.score100?.toDouble(), 0).clamp(0, 100).toDouble(),
            advice: overall?.recommendedActions?.advice,
            // Only the explanatory text under the chart will be spoken automatically (once)
            speakAdviceOnAppear: true,
            interruptSpeech: true,
          ),
        ),

        // SECTION 2: Products (scores 1..10)
        _SectionCard(
          title: 'Products (score 1..10)',
          child: Column(
            children: [
              for (final key in sortedProductKeys)
                _ProductRow(
                  label: key.toUpperCase(),
                  units: products[key]?.units ?? products[key]?.value?.units,
                  raw: _finiteOrNull(products[key]?.value?.raw),
                  score10: _finiteOr(products[key]?.score?.score10, 0).clamp(0, 10).toDouble(),
                ),
            ],
          ),
        ),

        // SECTION 3: Health risks (0..100) — show ALL risks (no hiding)
        _SectionCard(
          title: 'Health risks (sensitive groups)',
          child: Column(
            children: [
              for (final r in risks)
                _RiskRow(
                  name: (r.name ?? r.id ?? '—'),
                  risk: _finiteOr(r.risk0to100, 0).clamp(0, 100).toDouble(),
                  level: r.level,
                  note: r.note,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _horizonChip(int h, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('+${h}h', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

// --------------------- Loading Card Widgets ---------------------

class _LoadingSequenceCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<String> steps;
  final Duration stepDuration;
  final Duration lastStepExtra;

  const _LoadingSequenceCard({
    required this.title,
    this.subtitle,
    required this.steps,
    this.stepDuration = const Duration(seconds: 4),
    this.lastStepExtra = Duration.zero,
  });

  @override
  State<_LoadingSequenceCard> createState() => _LoadingSequenceCardState();
}

class _LoadingSequenceCardState extends State<_LoadingSequenceCard>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  Timer? _timer;
  late AnimationController _barCtrl;

  Duration _durationForStep(int index) {
    if (index == widget.steps.length - 1) {
      return widget.stepDuration + widget.lastStepExtra;
    }
    return widget.stepDuration;
  }

  void _startTimerForStep(int index) {
    _timer?.cancel();
    final d = _durationForStep(index);
    _barCtrl
      ..duration = d
      ..forward(from: 0);

    if (index < widget.steps.length - 1) {
      _timer = Timer(d, () {
        if (!mounted) return;
        setState(() {
          _current = index + 1;
        });
        _startTimerForStep(_current);
      });
    } else {
      _timer = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(vsync: this, duration: widget.stepDuration);
    _startTimerForStep(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _barCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Spinner + title + (optional) subtitle
              Row(
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(widget.subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              )),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Animated current step text
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  widget.steps[_current],
                  key: ValueKey(_current),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: 12),

              // Subtle animated progress bar (per-step)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AnimatedBuilder(
                  animation: _barCtrl,
                  builder: (context, _) {
                    return LinearProgressIndicator(
                      value: _barCtrl.value.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: theme.dividerColor.withValues(alpha: 0.25),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Steps list with states
              Column(
                children: [
                  for (int i = 0; i < widget.steps.length; i++)
                    _StepRow(
                      text: widget.steps[i],
                      state: i < _current
                          ? _StepState.done
                          : (i == _current ? _StepState.current : _StepState.todo),
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

enum _StepState { done, current, todo }

class _StepRow extends StatelessWidget {
  final String text;
  final _StepState state;

  const _StepRow({required this.text, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    Color color;

    switch (state) {
      case _StepState.done:
        icon = Icons.check_circle;
        color = Colors.green.shade600;
        break;
      case _StepState.current:
        icon = Icons.radio_button_checked;
        color = theme.colorScheme.primary;
        break;
      case _StepState.todo:
        icon = Icons.radio_button_unchecked;
        color = theme.colorScheme.onSurface.withValues(alpha: 0.45);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: state == _StepState.todo
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------- Existing widgets & charts ---------------------

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).dividerColor,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: theme.textTheme.titleMedium),
            const Spacer(),
            if (subtitle != null) Text(subtitle!, style: theme.textTheme.labelLarge),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Overall donut: shows score_100 (0..100) and (TTS) reads only the advisory text below the chart.
class _OverallDonut extends StatefulWidget {
  final double score100; // already clamped 0..100
  final String? advice;

  /// Speak the advisory text automatically when this widget appears (once).
  final bool speakAdviceOnAppear;

  /// Stop any ongoing speech before speaking the advisory text.
  final bool interruptSpeech;

  const _OverallDonut({
    required this.score100,
    this.advice,
    this.speakAdviceOnAppear = true,
    this.interruptSpeech = true,
  });

  @override
  State<_OverallDonut> createState() => _OverallDonutState();
}

class _OverallDonutState extends State<_OverallDonut> {
  bool _isSpeaking = false;
  bool _spokenOnce = false;

  @override
  void initState() {
    super.initState();
    // Speak advisory once after first frame (if enabled and available)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_spokenOnce && widget.speakAdviceOnAppear && (widget.advice?.trim().isNotEmpty == true)) {
        _spokenOnce = true;
        _speakAdvice();
      }
    });
  }

  Future<void> _speakAdvice() async {
    final text = widget.advice?.trim();
    if (text == null || text.isEmpty) return;
    setState(() => _isSpeaking = true);
    try {
      await TtsService.instance.speak(text, interrupt: widget.interruptSpeech);
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await TtsService.instance.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    // Stop TTS when this section unmounts (sheet closed or navigated away)
    TtsService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = widget.score100;
    final color = _scoreColor(v, theme);

    final bg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.98);

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PieChart(
            PieChartData(
              sectionsSpace: 0,
              centerSpaceRadius: 48,
              startDegreeOffset: -90,
              sections: [
                // Foreground slice (v out of 100)
                PieChartSectionData(
                  value: v <= 0 ? 0.0001 : v,
                  color: color,
                  radius: 20,
                  showTitle: false,
                ),
                // Background slice (rest to 100)
                PieChartSectionData(
                  value: (100 - v) <= 0 ? 0.0001 : (100 - v),
                  color: bg,
                  radius: 20,
                  showTitle: false,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${v.toStringAsFixed(0)}%',
          style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),

        // Advisory text (only this part is read via TTS)
        if (widget.advice != null && widget.advice!.trim().isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.advice!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: _isSpeaking ? 'Stop voice' : 'Play voice',
                onPressed: () {
                  if (_isSpeaking) {
                    _stopSpeaking();
                  } else {
                    _speakAdvice();
                  }
                },
                icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
              ),
            ],
          ),
      ],
    );
  }
}

/// Product row: label + bar chart (1..10) + raw value & units
class _ProductRow extends StatelessWidget {
  final String label;
  final String? units;
  final double? raw;     // may be null
  final double score10;  // safe & clamped 0..10

  const _ProductRow({
    required this.label,
    this.units,
    this.raw,
    required this.score10,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Map 0..10 -> 0..100 for color gradient
    final color = _scoreColor(score10 * 10, theme);

    final safeToY = math.max(score10, 0.0001);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text(label, style: theme.textTheme.labelLarge)),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 28,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.center,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barsSpace: 0,
                      barRods: [
                        BarChartRodData(
                          toY: safeToY,
                          width: 18,
                          color: color,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 10,
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
                          ),
                        ),
                      ],
                    ),
                  ],
                  maxY: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${score10.toStringAsFixed(1)} / 10', style: theme.textTheme.labelMedium?.copyWith(color: color)),
                if (raw != null)
                  Text(
                    '${_formatNumber(raw!)}${units != null ? ' ${units!}' : ''}',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.end,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Health risk row: custom progress bar (0..100) + level & notes
class _RiskRow extends StatelessWidget {
  final String name;
  final double risk; // safe & clamped 0..100
  final String? level;
  final String? note;

  const _RiskRow({
    required this.name,
    required this.risk,
    this.level,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _scoreColor(risk, theme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: theme.textTheme.labelLarge)),
              if (level != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(level!, style: theme.textTheme.labelSmall?.copyWith(color: color)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, cns) {
              final w = cns.maxWidth.isFinite ? cns.maxWidth : 0.0;
              final pct = (risk / 100.0).clamp(0.0, 1.0);
              final filledW = (w * pct).isFinite ? w * pct : 0.0;

              return Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Container(
                    height: 10,
                    width: math.max(filledW, 0.0),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${risk.toStringAsFixed(0)}%', style: theme.textTheme.labelMedium?.copyWith(color: color)),
              const Spacer(),
              if (note != null)
                Flexible(child: Text(note!, style: theme.textTheme.bodySmall, textAlign: TextAlign.end)),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------- Utils ---------------------

double _finiteOr(num? v, double fallback) {
  if (v == null) return fallback;
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite) return fallback;
  return d;
}

double? _finiteOrNull(num? v) {
  if (v == null) return null;
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite) return null;
  return d;
}

Color _scoreColor(double score0to100, ThemeData theme) {
  // 0..100 → green -> yellow -> orange -> red
  final t = (score0to100 / 100.0).clamp(0.0, 1.0);
  final stops = <double>[0.0, 0.4, 0.7, 1.0];
  final colors = <Color>[
    Colors.green.shade600,
    Colors.yellow.shade700,
    Colors.orange.shade700,
    Colors.red.shade700,
  ];
  for (int i = 0; i < stops.length - 1; i++) {
    final a = stops[i], b = stops[i + 1];
    if (t >= a && t <= b) {
      final localT = (t - a) / (b - a);
      return Color.lerp(colors[i], colors[i + 1], localT) ?? colors[i + 1];
    }
  }
  return colors.last;
}

String _formatNumber(double v) {
  final d = v.isFinite ? v : 0.0;
  if (d.abs() >= 1e9) return '${(d / 1e9).toStringAsFixed(2)}B';
  if (d.abs() >= 1e6) return '${(d / 1e6).toStringAsFixed(2)}M';
  if (d.abs() >= 1e3) return '${(d / 1e3).toStringAsFixed(2)}K';
  if (d.abs() < 1e-2 || d.abs() >= 1e5) {
    return d.toStringAsExponential(2);
  }
  return d.toStringAsFixed(2);
}
