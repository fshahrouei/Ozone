import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../data/heat_map_repository.dart';
import '../models/chart_models.dart';

/// Global warming statistics page.
class StatisticsPage extends StatefulWidget {
  final int year;
  const StatisticsPage({super.key, required this.year});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _isLoading = true;
  String? _errorMessage;

  List<HeatCountryStat> _topCountries = [];
  GlobalAverage? _globalAverage;
  List<HeatTrendYear> _trend = [];
  int _lastRealYear = 0;

  List<Color> get chartColors => [
        Colors.blue.shade400,
        Colors.green.shade400,
        Colors.orange.shade400,
        Colors.purple.shade400,
        Colors.teal.shade400,
        Colors.red.shade400,
        Colors.indigo.shade400,
        Colors.brown.shade400,
        Colors.cyan.shade400,
        Colors.amber.shade400,
      ];

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final stats = await HeatMapRepository().fetchStatistics(year: widget.year);
      setState(() {
        _topCountries = stats['topCountries'];
        _globalAverage = stats['globalAverage'];
        _trend = stats['trend'];
        _lastRealYear = stats['lastRealYear'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _formatTemp(num value) => value.toStringAsFixed(2);

  String buildHeadline() {
    if (_topCountries.isEmpty) return '';
    final top = _topCountries.take(3).toList();
    List<String> info = [];
    for (final e in top) {
      info.add("${e.name} (Anomaly: ${_formatTemp(e.anomaly)}°C, TAS: ${_formatTemp(e.tas)}°C)");
    }
    return "Top 3 countries in ${widget.year}: ${info.join(', ')}";
  }

  /// Dynamic scientific blurb about warming trend (e.g., increase since 1950).
  String buildDynamicTrendInfo() {
    if (_trend.isEmpty) return '';
    final anomalyStart = _trend.first.anomaly;
    final anomalyEnd = _trend.last.anomaly;
    final diff = anomalyEnd - anomalyStart;
    if (diff.abs() < 0.01) return '';
    final status = diff > 0 ? "increased by" : "decreased by";
    return "Since ${_trend.first.year}, the global anomaly has $status ${_formatTemp(diff.abs())}°C.";
  }

  /// For the LineChart: show only first, middle, and last years on the X axis.
  List<int> _getXAxisYears() {
    if (_trend.isEmpty) return [];
    int first = _trend.first.year;
    int last = _trend.last.year;
    int mid = ((first + last) / 2).round();
    return [first, mid, last];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: 'Statistics – ${widget.year}',
        showDrawer: false,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Global Warming Statistics (${widget.year})',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (_topCountries.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 8),
                          child: Text(
                            buildHeadline(),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo,
                              height: 1.5,
                            ),
                          ),
                        ),
                      if (_trend.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                          child: Text(
                            buildDynamicTrendInfo(),
                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                        ),
                      const SizedBox(height: 8),

                      // --- Bar Chart ---
                      _ChartSection(
                        title: 'Top 10 Countries (Anomaly)',
                        description:
                            'Each bar shows the temperature anomaly (°C) for the top 10 countries in ${widget.year}.',
                        child: _topCountries.isEmpty
                            ? const Text('No data available')
                            : SizedBox(
                                height: 320,
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: _topCountries
                                            .map((e) => e.anomaly)
                                            .reduce((a, b) => a > b ? a : b) *
                                        1.13,
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget:
                                              (double value, TitleMeta meta) {
                                            final i = value.toInt();
                                            if (i < 0 || i >= _topCountries.length) {
                                              return const SizedBox.shrink();
                                            }
                                            return SideTitleWidget(
                                              meta: meta,
                                              child: RotatedBox(
                                                quarterTurns: 1,
                                                child: Text(
                                                  _topCountries[i].name,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            );
                                          },
                                          reservedSize: 68,
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (value, _) => Text(
                                            _formatTemp(value),
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                          reservedSize: 42,
                                        ),
                                      ),
                                      topTitles: const AxisTitles(
                                        sideTitles: SideTitles(showTitles: false),
                                      ),
                                      rightTitles: const AxisTitles(
                                        sideTitles: SideTitles(showTitles: false),
                                      ),
                                    ),
                                    barGroups: List.generate(
                                      _topCountries.length,
                                      (i) => BarChartGroupData(
                                        x: i,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _topCountries[i].anomaly,
                                            color: i < chartColors.length
                                                ? chartColors[i]
                                                : Colors.orange,
                                            borderRadius: BorderRadius.circular(6),
                                            width: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    gridData: FlGridData(show: false),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 30),

                      // --- Pie Chart + Legend ---
                      _ChartSection(
                        title: 'Anomaly Comparison: Top 10 Countries',
                        description:
                            'Relative anomaly of each country from the top 10 in ${widget.year}. This is a comparative chart and does not indicate global share.',
                        child: _topCountries.isEmpty
                            ? const Text('No data available')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 270,
                                    child: PieChart(
                                      PieChartData(
                                        sections: List.generate(_topCountries.length, (i) {
                                          final e = _topCountries[i];
                                          final color = i < chartColors.length
                                              ? chartColors[i]
                                              : Colors.blue;
                                          return PieChartSectionData(
                                            value: e.anomaly,
                                            title: '',
                                            color: color,
                                            radius: 54,
                                          );
                                        }),
                                        sectionsSpace: 2,
                                        centerSpaceRadius: 32,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  // --- Legend ---
                                  Wrap(
                                    spacing: 14,
                                    runSpacing: 8,
                                    children: List.generate(_topCountries.length, (i) {
                                      final e = _topCountries[i];
                                      final color = i < chartColors.length
                                          ? chartColors[i]
                                          : Colors.blue;
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 16,
                                            height: 16,
                                            margin: const EdgeInsets.only(right: 4),
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.black12, width: 0.7),
                                            ),
                                          ),
                                          Text(
                                            '${e.name} (${_formatTemp(e.anomaly)}°C)',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 30),

                      // --- Line Chart + Legend ---
                      _ChartSection(
                        title: 'Global Anomaly Trend (1950–${widget.year})',
                        description:
                            'Annual global temperature anomaly. Teal line: observed (to $_lastRealYear), orange line: projection (after $_lastRealYear).',
                        child: _trend.isEmpty
                            ? const Text('No trend data')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 260,
                                    child: LineChart(
                                      LineChartData(
                                        minY: 0,
                                        lineBarsData: [
                                          // Observed line up to the last real year
                                          // Observed line up to the last real year
                                          LineChartBarData(
                                            spots: _trend
                                                .where((e) => e.year <= _lastRealYear)
                                                .map((e) => FlSpot(e.year.toDouble(), e.anomaly))
                                                .toList(),
                                            isCurved: true,
                                            color: Colors.teal,
                                            barWidth: 3,
                                            isStrokeCapRound: true,
                                            dotData: FlDotData(show: false),
                                            belowBarData: BarAreaData(show: false),
                                          ),
                                          // Projection line starting from the year after the last real year
                                          if (_trend.any((e) => e.year > _lastRealYear))
                                            LineChartBarData(
                                              spots: _trend
                                                  .where((e) => e.year >= _lastRealYear)
                                                  .map((e) => FlSpot(e.year.toDouble(), e.anomaly))
                                                  .toList(),
                                              isCurved: true,
                                              color: Colors.orange.shade400,
                                              barWidth: 3,
                                              isStrokeCapRound: true,
                                              dotData: FlDotData(show: false),
                                              belowBarData: BarAreaData(show: false),
                                              // dashArray: [8, 8], // Remove this line
                                            ),
                                        ],
                                        lineTouchData: LineTouchData(
                                          touchTooltipData: LineTouchTooltipData(
                                            tooltipBorderRadius: BorderRadius.circular(8),
                                            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                                              return LineTooltipItem(
                                                'Year: ${spot.x.toInt()}\nAnomaly: ${_formatTemp(spot.y)}°C',
                                                const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                        titlesData: FlTitlesData(
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (value, _) =>
                                                  Text(_formatTemp(value),
                                                      style: const TextStyle(fontSize: 10)),
                                              reservedSize: 44,
                                            ),
                                          ),
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (value, meta) {
                                                int year = value.toInt();
                                                final xYears = _getXAxisYears();
                                                if (xYears.contains(year)) {
                                                  return Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text(
                                                      year.toString(),
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  );
                                                }
                                                return const SizedBox.shrink();
                                              },
                                              reservedSize: 38,
                                            ),
                                          ),
                                          topTitles:
                                              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                          rightTitles:
                                              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        ),
                                        gridData: FlGridData(show: false),
                                        borderData: FlBorderData(show: false),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  // Scientific explanation for colors and projections
                                  Text(
                                    'Teal line: observed values (to $_lastRealYear). Orange dashed: projection (after $_lastRealYear).',
                                    style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
                                  ),
                                  if (_globalAverage != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        'Global average anomaly in ${widget.year}: ${_formatTemp(_globalAverage!.anomaly)}°C',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Reusable chart section (title + description + chart widget).
class _ChartSection extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _ChartSection({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2.2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
