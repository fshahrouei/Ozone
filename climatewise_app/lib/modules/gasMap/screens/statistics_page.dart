import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../data/gas_map_repository.dart';
import '../models/chart_models.dart';

class StatisticsPage extends StatefulWidget {
  final int year;
  final List<Color>? chartColors;

  const StatisticsPage({super.key, required this.year, this.chartColors});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _isLoading = true;
  String? _errorMessage;

  List<GasStatData> _barPieData = [];
  List<GasHistoryData> _lineData = [];
  double _total = 0;
  int _currentYear = 0;

  List<Color> get chartColors => widget.chartColors ??
      [
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
      final stats = await GasMapRepository().fetchStatistics(year: widget.year);
      setState(() {
        _barPieData = stats['barPieData'];
        _lineData = stats['lineData'];
        _total = stats['total'];
        _currentYear = stats['currentYear'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String buildStatsHeadline(List<GasStatData> data, double total, int year) {
    if (data.isEmpty || total == 0) return '';
    final top = data.take(3).toList();
    if (top.length < 3) return '';
    final names = top.map((e) => e.name).toList();
    final percents = top.map((e) => (e.value / total * 100)).toList();
    final combined = percents.fold(0.0, (a, b) => a + b);

    return 'In $year, the top 3 greenhouse gas emitters were '
        '${names[0]} (${percents[0].toStringAsFixed(1)}%), '
        '${names[1]} (${percents[1].toStringAsFixed(1)}%), and '
        '${names[2]} (${percents[2].toStringAsFixed(1)}%), together producing ${combined.toStringAsFixed(1)}% of global emissions.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: 'Statistics – $_currentYear', // سال در عنوان صفحه
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
                      // اگر خواستی عنوان و سال هم اینجا تکرار کن:
                      // Text('Statistics ($_currentYear)', style: ...),

                      Text(
                        'Greenhouse Gas Emission Statistics',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      // جمله پویا
                      if (_barPieData.length >= 3 && _total > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4, top: 6),
                          child: Text(
                            buildStatsHeadline(_barPieData, _total, _currentYear),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo,
                              height: 1.55,
                            ),
                            textAlign: TextAlign.start,
                          ),
                        ),
                      const SizedBox(height: 6),

                      // --- Bar Chart ---
                      _ChartSection(
                        title: 'Top 10 Countries Emission ($_currentYear)',
                        description:
                            'Annual emission (t) for the top 10 countries plus "Other" (all remaining countries).',
                        child: _barPieData.isEmpty
                            ? const Text('No data available')
                            : SizedBox(
                                height: 340,
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: _barPieData
                                            .map((e) => e.value)
                                            .reduce((a, b) => a > b ? a : b) *
                                        1.12,
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget:
                                              (double value, TitleMeta meta) {
                                            final i = value.toInt();
                                            if (i < 0 ||
                                                i >= _barPieData.length) {
                                              return const SizedBox.shrink();
                                            }
                                            return SideTitleWidget(
                                              meta: meta,
                                              child: RotatedBox(
                                                quarterTurns: 1, // Vertical label
                                                child: Text(
                                                  _barPieData[i].name,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                            _formatNumber(value),
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                          reservedSize: 42,
                                        ),
                                      ),
                                      topTitles: AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                      rightTitles: AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                    ),
                                    barGroups: List.generate(
                                      _barPieData.length,
                                      (i) => BarChartGroupData(
                                        x: i,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _barPieData[i].value,
                                            color: _barPieData[i].name == 'Other'
                                                ? Colors.grey[400]
                                                : (i < chartColors.length
                                                      ? chartColors[i]
                                                      : Colors.blue),
                                            borderRadius:
                                                BorderRadius.circular(6),
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

                      const SizedBox(height: 40),

                      // --- Pie Chart + Legend ---
                      _ChartSection(
                        title: 'Emission Share ($_currentYear)',
                        description:
                            'Share of each country from the total emission in the selected year (top 10 + Other).',
                        child: _barPieData.isEmpty || _total == 0
                            ? const Text('No data available')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 270,
                                    child: PieChart(
                                      PieChartData(
                                        sections: List.generate(_barPieData.length, (i) {
                                          final e = _barPieData[i];
                                          final isOther = e.name == 'Other';
                                          final color = isOther
                                              ? Colors.grey[400]!
                                              : (i < chartColors.length
                                                    ? chartColors[i]
                                                    : Colors.blue);
                                          return PieChartSectionData(
                                            value: e.value,
                                            title: '', // NO LABEL ON PIE!
                                            color: color,
                                            radius: isOther ? 38 : 54,
                                            titleStyle: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
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
                                    children: List.generate(_barPieData.length, (i) {
                                      final e = _barPieData[i];
                                      final isOther = e.name == 'Other';
                                      final color = isOther
                                          ? Colors.grey[400]!
                                          : (i < chartColors.length
                                                ? chartColors[i]
                                                : Colors.blue);
                                      final percent = _total == 0 ? 0 : (e.value / _total * 100);
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
                                            '${e.name} (${percent.toStringAsFixed(1)}%)',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ],
                              ),
                      ),

                      const SizedBox(height: 40),

                      // --- Line Chart with horizontal scroll + Legend ---
                      _ChartSection(
                        title: 'Emission Trend (Past 25 Years)',
                        description:
                            'Annual emission trend for the top 10 countries and "Other" group. Drag horizontally to see all years.',
                        child: _lineData.isEmpty
                            ? const Text('No data available')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: max(_lineData.isNotEmpty
                                              ? _lineData[0].values.length * 44.0
                                              : 320,
                                          MediaQuery.of(context).size.width),
                                      height: 320,
                                      child: LineChart(
                                        LineChartData(
                                          minY: 0,
                                          lineTouchData: LineTouchData(
                                            touchTooltipData: LineTouchTooltipData(
                                              tooltipPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 18, vertical: 10),
                                              tooltipBorderRadius: BorderRadius.circular(14),
                                              getTooltipItems: (touchedSpots) =>
                                                  touchedSpots.map((spot) {
                                                final c = _lineData[spot.barIndex];
                                                return LineTooltipItem(
                                                  '${c.name}\nYear: ${spot.x.toInt()}\nValue: ${_formatNumber(spot.y)}',
                                                  const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                    height: 1.5,
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                          titlesData: FlTitlesData(
                                            leftTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                getTitlesWidget: (value, _) => Text(
                                                  _formatNumber(value),
                                                  style: const TextStyle(fontSize: 10),
                                                ),
                                                reservedSize: 44,
                                              ),
                                            ),
                                            bottomTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                getTitlesWidget:
                                                    (double value, TitleMeta meta) {
                                                  int year = value.toInt();
                                                  final firstYear =
                                                      _lineData.isNotEmpty &&
                                                              _lineData[0].values.isNotEmpty
                                                          ? _lineData[0].values.first.year
                                                          : year;
                                                  final lastYear =
                                                      _lineData.isNotEmpty &&
                                                              _lineData[0].values.isNotEmpty
                                                          ? _lineData[0].values.last.year
                                                          : year;
                                                  if (year == firstYear ||
                                                      year == lastYear ||
                                                      year % 5 == 0) {
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4),
                                                      child: Text(
                                                        year.toString(),
                                                        style: const TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600),
                                                      ),
                                                    );
                                                  }
                                                  return const SizedBox.shrink();
                                                },
                                                reservedSize: 38,
                                              ),
                                            ),
                                            topTitles: AxisTitles(
                                                sideTitles:
                                                    SideTitles(showTitles: false)),
                                            rightTitles: AxisTitles(
                                                sideTitles:
                                                    SideTitles(showTitles: false)),
                                          ),
                                          lineBarsData: List.generate(
                                              _lineData.length, (i) {
                                            final country = _lineData[i];
                                            final color = i == _lineData.length - 1
                                                ? Colors.grey
                                                : (i < chartColors.length
                                                      ? chartColors[i]
                                                      : Colors.primaries[i %
                                                            Colors.primaries
                                                                .length]);
                                            return LineChartBarData(
                                              spots: country.values
                                                  .map((p) => FlSpot(
                                                      p.year.toDouble(),
                                                      p.value))
                                                  .toList(),
                                              isCurved: true,
                                              color: color,
                                              barWidth:
                                                  i == _lineData.length - 1
                                                      ? 3.2
                                                      : 2.2,
                                              dotData: FlDotData(show: false),
                                              belowBarData:
                                                  BarAreaData(show: false),
                                            );
                                          }),
                                          gridData: FlGridData(show: false),
                                          borderData: FlBorderData(show: false),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  // --- Legend زیر نمودار خطی ---
                                  Wrap(
                                    spacing: 18,
                                    runSpacing: 8,
                                    children: List.generate(_lineData.length, (i) {
                                      final country = _lineData[i];
                                      final color = i == _lineData.length - 1
                                          ? Colors.grey
                                          : (i < chartColors.length
                                                ? chartColors[i]
                                                : Colors.primaries[i % Colors.primaries.length]);
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 22,
                                            height: 5,
                                            margin: const EdgeInsets.only(right: 7),
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                          Text(
                                            country.name,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
    );
  }

  String _formatNumber(num value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

/// Reusable section for each chart (title + description + chart)
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
