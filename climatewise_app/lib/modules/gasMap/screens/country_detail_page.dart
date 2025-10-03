import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../data/gas_map_repository.dart';
import '../models/country_gas_models.dart';

/// Country detail screen: shows country meta, comparison charts, trend, and gas mix.
class CountryDetailPage extends StatefulWidget {
  final String isoA3;
  final int year;

  const CountryDetailPage({
    super.key,
    required this.isoA3,
    required this.year,
  });

  @override
  State<CountryDetailPage> createState() => _CountryDetailPageState();
}

class _CountryDetailPageState extends State<CountryDetailPage> {
  final GasMapRepository _repository = GasMapRepository();

  bool _isLoading = true;
  String? _errorMessage;
  CountryGasData? _countryData;
  List<CountryStatData> _topCountries = [];
  double _othersValue = 0;
  double _total = 0;
  List<CountryYearlyGasData> _history = [];

  /// Palette for pie segments when comparing countries.
  final List<Color> pieColors = const [
    Colors.orange,
    Colors.teal,
    Colors.purple,
    Colors.blue,
    Colors.green,
    Colors.deepPurple,
    Colors.brown,
    Colors.pink,
    Colors.indigo,
    Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _fetchCountryDetail();
  }

  /// Loads country statistics (meta, top countries, history, totals).
  Future<void> _fetchCountryDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repository.fetchCountryStatistics(
        isoA3: widget.isoA3,
        year: widget.year,
      );
      setState(() {
        _countryData = res['country'] as CountryGasData?;
        _topCountries = res['top_countries'] as List<CountryStatData>;
        _othersValue = res['others'] as double;
        _total = res['total'] as double;
        _history = res['history'] as List<CountryYearlyGasData>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// Human-friendly number formatting with unit suffix (tonnes).
  String _formatNumber(num value) {
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(2)}B t';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(2)}M t';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(2)}K t';
    return '${value.toStringAsFixed(0)} t';
  }

  /// Table row background color by key semantics.
  Color _getRowColor(String key) {
    if (key.toLowerCase() == 'total') return Colors.red.shade200;
    if (key.toLowerCase().contains('score')) return Colors.blue.shade100;
    return Colors.green.shade100;
  }

  /// Dynamic one-line summary for the country table.
  String _dynamicTableSummary(CountryGasData? d) {
    if (d == null) return '';
    return 'In ${d.year}, ${d.entity} emitted ${_formatNumber(d.total)} of greenhouse gases (CO₂-equivalent). Most emissions were from CO₂ (${_formatNumber(d.co2)}), followed by CH₄ (${_formatNumber(d.ch4)}) and N₂O (${_formatNumber(d.n2o)}).';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          top: true,
          bottom: false,
          child: CustomAppBar(
            title: _countryData != null
                ? '${_countryData!.entity} – ${_countryData!.year}'
                : 'Country Details',
            showDrawer: false,
            onBackPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : _countryData == null
                  ? const Center(child: Text('No data available'))
                  : SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildTopImage(_countryData?.image),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header and brief summary
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Text(
                                      '${_countryData!.entity} GHG Emissions in ${_countryData!.year}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                        letterSpacing: 0.2,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                  // Dynamic summary text
                                  Text(
                                    _dynamicTableSummary(_countryData),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Table(
                                        border: TableBorder.all(
                                          color: Colors.grey.shade300,
                                          width: 1.0,
                                        ),
                                        columnWidths: const {
                                          0: FlexColumnWidth(2),
                                          1: FlexColumnWidth(2),
                                        },
                                        children: [
                                          _buildTableRow('Entity', _countryData!.entity),
                                          _buildTableRow('N₂O', _formatNumber(_countryData!.n2o)),
                                          _buildTableRow('CH₄', _formatNumber(_countryData!.ch4)),
                                          _buildTableRow('CO₂', _formatNumber(_countryData!.co2)),
                                          _buildTableRow('Total', _formatNumber(_countryData!.total)),
                                          _buildTableRow('Score', _countryData!.score.toString()),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10, bottom: 20),
                                    child: Text(
                                      'All greenhouse gas values are presented as CO₂-equivalents (tonnes).',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey[700],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                  // Top emitters bar chart
                                  if (_topCountries.isNotEmpty)
                                    _ChartSection(
                                      title: 'Top Emitting Countries (${_countryData!.year})',
                                      description:
                                          'Bar chart comparing the top 10 emitters (including ${_countryData!.entity}) in ${_countryData!.year}.',
                                      child: SizedBox(
                                        height: 340,
                                        child: BarChart(
                                          BarChartData(
                                            alignment: BarChartAlignment.spaceAround,
                                            maxY: _topCountries
                                                    .map((e) => e.value)
                                                    .reduce(max) *
                                                1.12,
                                            titlesData: FlTitlesData(
                                              bottomTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  getTitlesWidget:
                                                      (double value, TitleMeta meta) {
                                                    int i = value.toInt();
                                                    if (i < 0 ||
                                                        i >= _topCountries.length) {
                                                      return const SizedBox.shrink();
                                                    }
                                                    return SideTitleWidget(
                                                      meta: meta,
                                                      child: RotatedBox(
                                                        quarterTurns: 1,
                                                        child: Text(
                                                          _topCountries[i].name,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: _topCountries[i]
                                                                        .isoA3 ==
                                                                    _countryData!.isoA3
                                                                ? FontWeight.bold
                                                                : FontWeight.w600,
                                                            color: _topCountries[i]
                                                                        .isoA3 ==
                                                                    _countryData!.isoA3
                                                                ? Colors.red
                                                                : Colors.black87,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
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
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  reservedSize: 46,
                                                ),
                                              ),
                                              topTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: false,
                                                ),
                                              ),
                                              rightTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: false,
                                                ),
                                              ),
                                            ),
                                            barGroups: List.generate(
                                              _topCountries.length,
                                              (i) => BarChartGroupData(
                                                x: i,
                                                barRods: [
                                                  BarChartRodData(
                                                    toY: _topCountries[i].value,
                                                    color: _topCountries[i]
                                                                .isoA3 ==
                                                            _countryData!.isoA3
                                                        ? Colors.red
                                                        : Colors.blue,
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
                                  if (_topCountries.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4,
                                          left: 4,
                                          right: 4,
                                          bottom: 18),
                                      child: Text(
                                        '${_countryData!.entity} emitted ${_formatNumber(_countryData!.total)} greenhouse gases in ${_countryData!.year} and is among the top emitters.',
                                        style: const TextStyle(
                                            fontSize: 13, color: Colors.indigo),
                                      ),
                                    ),
                                  // Emission share pie chart (country vs others)
                                  if (_topCountries.isNotEmpty && _total > 0)
                                    _ChartSection(
                                      title: 'Emission Share (${_countryData!.year})',
                                      description:
                                          'Pie chart showing the share of ${_countryData!.entity} and other major countries in total emissions.',
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            height: 220,
                                            child: PieChart(
                                              PieChartData(
                                                sections: List.generate(
                                                    _topCountries.length, (i) {
                                                  final e = _topCountries[i];
                                                  final isCurrent =
                                                      e.isoA3 ==
                                                          _countryData!.isoA3;
                                                  final color = isCurrent
                                                      ? Colors.red
                                                      : pieColors[i %
                                                          pieColors.length];
                                                  return PieChartSectionData(
                                                    value: e.value,
                                                    title: '',
                                                    color: color,
                                                    radius:
                                                        isCurrent ? 52 : 40,
                                                  );
                                                })
                                                  ..add(
                                                    PieChartSectionData(
                                                      value: _othersValue,
                                                      title: '',
                                                      color: Colors.grey[400]!,
                                                      radius: 32,
                                                    ),
                                                  ),
                                                sectionsSpace: 2,
                                                centerSpaceRadius: 30,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 18,
                                            runSpacing: 8,
                                            children: List.generate(
                                              _topCountries.length,
                                              (i) {
                                                final e = _topCountries[i];
                                                final isCurrent = e.isoA3 ==
                                                    _countryData!.isoA3;
                                                final color = isCurrent
                                                    ? Colors.red
                                                    : pieColors[i %
                                                        pieColors.length];
                                                final percent = (_total > 0)
                                                    ? (e.value / _total) * 100
                                                    : 0.0;
                                                return Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 16,
                                                      height: 16,
                                                      margin:
                                                          const EdgeInsets.only(
                                                              right: 4),
                                                      decoration: BoxDecoration(
                                                        color: color,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                        border: Border.all(
                                                          color:
                                                              Colors.black12,
                                                          width: 0.7,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      '${e.name} (${percent.toStringAsFixed(1)}%)',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: isCurrent
                                                            ? FontWeight.bold
                                                            : FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            )
                                              ..add(
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 16,
                                                      height: 16,
                                                      margin:
                                                          const EdgeInsets.only(
                                                              right: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey[400],
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                        border: Border.all(
                                                          color:
                                                              Colors.black12,
                                                          width: 0.7,
                                                        ),
                                                      ),
                                                    ),
                                                    const Text(
                                                      'Other',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_topCountries.isNotEmpty && _total > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4,
                                          left: 4,
                                          right: 4,
                                          bottom: 18),
                                      child: Text(
                                        '${_countryData!.entity} accounts for ${(100 * _countryData!.total / _total).toStringAsFixed(2)}% of global greenhouse gas emissions in ${_countryData!.year}.',
                                        style: const TextStyle(
                                            fontSize: 13, color: Colors.indigo),
                                      ),
                                    ),
                                  // Emission trend line chart
                                  if (_history.isNotEmpty)
                                    _ChartSection(
                                      title: 'Emission Trend (Past 25 Years)',
                                      description:
                                          'Annual greenhouse gas emissions of ${_countryData!.entity} (total gases) in the last 25 years. Highest and lowest values are highlighted.',
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: max(
                                            _history.length * 44.0,
                                            MediaQuery.of(context).size.width,
                                          ),
                                          height: 280,
                                          child: LineChart(
                                            LineChartData(
                                              minY: 0,
                                              lineBarsData: [
                                                LineChartBarData(
                                                  spots: _history
                                                      .map(
                                                        (e) => FlSpot(
                                                          e.year.toDouble(),
                                                          e.total,
                                                        ),
                                                      )
                                                      .toList(),
                                                  isCurved: true,
                                                  color: Colors.teal,
                                                  barWidth: 3,
                                                  dotData: FlDotData(
                                                    show: true,
                                                    checkToShowDot:
                                                        (spot, barData) {
                                                      final values = barData
                                                          .spots
                                                          .map((e) => e.y);
                                                      return spot.y ==
                                                              values.reduce(
                                                                  max) ||
                                                          spot.y ==
                                                              values.reduce(
                                                                  min);
                                                    },
                                                    getDotPainter: (spot,
                                                        percent, bar, index) {
                                                      final values = bar.spots
                                                          .map((e) => e.y);
                                                      final isMax = spot.y ==
                                                          values.reduce(max);
                                                      final isMin = spot.y ==
                                                          values.reduce(min);
                                                      return FlDotCirclePainter(
                                                        radius: 6,
                                                        color: isMax
                                                            ? Colors.red
                                                            : (isMin
                                                                ? Colors.green
                                                                : Colors.teal),
                                                        strokeWidth: 1.4,
                                                        strokeColor:
                                                            Colors.white,
                                                      );
                                                    },
                                                  ),
                                                  belowBarData: BarAreaData(
                                                    show: true,
                                                    color: Colors.teal
                                                        .withOpacity(0.10),
                                                  ),
                                                ),
                                              ],
                                              lineTouchData: LineTouchData(
                                                touchTooltipData:
                                                    LineTouchTooltipData(
                                                  tooltipPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                  tooltipBorderRadius:
                                                      BorderRadius.circular(12),
                                                  getTooltipItems:
                                                      (touchedSpots) =>
                                                          touchedSpots.map(
                                                    (spot) {
                                                      return LineTooltipItem(
                                                        '${_countryData!.entity}\nYear: ${spot.x.toInt()}\nTotal: ${_formatNumber(spot.y)}',
                                                        const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      );
                                                    },
                                                  ).toList(),
                                                ),
                                              ),
                                              titlesData: FlTitlesData(
                                                leftTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    getTitlesWidget:
                                                        (value, _) => Text(
                                                      _formatNumber(value),
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                    reservedSize: 40,
                                                  ),
                                                ),
                                                bottomTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    getTitlesWidget:
                                                        (value, meta) {
                                                      int year = value.toInt();
                                                      if (_history.isNotEmpty &&
                                                          (year ==
                                                                  _history
                                                                      .first
                                                                      .year ||
                                                              year ==
                                                                  _history.last
                                                                      .year ||
                                                              year % 5 == 0)) {
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(top: 4),
                                                          child: Text(
                                                            year.toString(),
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      return const SizedBox
                                                          .shrink();
                                                    },
                                                    reservedSize: 36,
                                                  ),
                                                ),
                                                topTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: false,
                                                  ),
                                                ),
                                                rightTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: false,
                                                  ),
                                                ),
                                              ),
                                              gridData: FlGridData(show: false),
                                              borderData:
                                                  FlBorderData(show: false),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_history.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        left: 4,
                                        right: 4,
                                        bottom: 18,
                                      ),
                                      child: Text(
                                        'Highest emission: ${_formatNumber(_history.map((e) => e.total).reduce(max))} (${_history.last.year})\nLowest emission: ${_formatNumber(_history.map((e) => e.total).reduce(min))} (${_history.first.year})',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                  // Gas composition (N₂O, CH₄, CO₂)
                                  if (_countryData != null &&
                                      _countryData!.total > 0)
                                    _ChartSection(
                                      title:
                                          'Gas Composition (${_countryData!.year})',
                                      description:
                                          'Relative share of N₂O, CH₄, and CO₂ in total emissions for ${_countryData!.entity}.',
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            height: 168,
                                            child: PieChart(
                                              PieChartData(
                                                sections: [
                                                  PieChartSectionData(
                                                    value: _countryData!.n2o,
                                                    title: '',
                                                    color:
                                                        Colors.amber[600]!,
                                                    radius: 38,
                                                  ),
                                                  PieChartSectionData(
                                                    value: _countryData!.ch4,
                                                    title: '',
                                                    color: Colors
                                                        .lightBlue[400]!,
                                                    radius: 38,
                                                  ),
                                                  PieChartSectionData(
                                                    value: _countryData!.co2,
                                                    title: '',
                                                    color:
                                                        Colors.green[400]!,
                                                    radius: 38,
                                                  ),
                                                ],
                                                sectionsSpace: 3,
                                                centerSpaceRadius: 22,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              _legendItem(
                                                color: Colors.amber[600]!,
                                                label:
                                                    'N₂O (${(_countryData!.n2o * 100 / _countryData!.total).toStringAsFixed(1)}%)',
                                              ),
                                              const SizedBox(width: 16),
                                              _legendItem(
                                                color: Colors.lightBlue[400]!,
                                                label:
                                                    'CH₄ (${(_countryData!.ch4 * 100 / _countryData!.total).toStringAsFixed(1)}%)',
                                              ),
                                              const SizedBox(width: 16),
                                              _legendItem(
                                                color: Colors.green[400]!,
                                                label:
                                                    'CO₂ (${(_countryData!.co2 * 100 / _countryData!.total).toStringAsFixed(1)}%)',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_countryData != null &&
                                      _countryData!.total > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        left: 4,
                                        right: 4,
                                        bottom: 18,
                                      ),
                                      child: Text(
                                        _gasCompositionSummary(_countryData!),
                                        style: const TextStyle(
                                          fontSize: 12,
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
                    ),
    );
  }

  /// Builds a centered circular 200x200 image with SVG support and loading states.
  Widget buildTopImage(String? imageUrl) {
    if (imageUrl == null) return const SizedBox.shrink();

    final bool isSvg = imageUrl.toLowerCase().endsWith('.svg');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28.0),
      child: Center(
        child: Container(
          width: 200,
          height: 200,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: isSvg
                ? SvgPicture.network(
                    imageUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    placeholderBuilder: (context) => Container(
                      color: Colors.grey[200],
                      child:
                          const Center(child: CircularProgressIndicator()),
                    ),
                  )
                : Image.network(
                    imageUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported,
                          size: 54,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey[200],
                        child:
                            const Center(child: CircularProgressIndicator()),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  /// Single table row with colored background and monospaced value.
  TableRow _buildTableRow(String key, String value) {
    return TableRow(
      decoration: BoxDecoration(color: _getRowColor(key)),
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            key,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            value,
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
        ),
      ],
    );
  }

  /// Legend item used below pie charts and similar components.
  Widget _legendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.black12, width: 0.7),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  /// Produces a short narrative about the dominant gas in the total.
  String _gasCompositionSummary(CountryGasData data) {
    List<Map<String, dynamic>> parts = [
      {'name': 'N₂O', 'value': data.n2o, 'percent': (data.n2o * 100 / data.total)},
      {'name': 'CH₄', 'value': data.ch4, 'percent': (data.ch4 * 100 / data.total)},
      {'name': 'CO₂', 'value': data.co2, 'percent': (data.co2 * 100 / data.total)},
    ];
    parts.sort((a, b) => b['percent'].compareTo(a['percent']));
    final main = parts.first;
    return 'In ${data.entity}, most greenhouse gas emissions in ${data.year} were due to ${main['name']} (${main['percent'].toStringAsFixed(1)}% of total emissions).';
  }
}

/// Reusable section wrapper for chart blocks (title, description, content).
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
