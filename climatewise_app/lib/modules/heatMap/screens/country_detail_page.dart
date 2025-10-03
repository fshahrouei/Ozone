import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../data/heat_map_repository.dart';
import '../models/country_heat_models.dart';

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
  final HeatMapRepository _repository = HeatMapRepository();

  bool _isLoading = true;
  String? _errorMessage;
  CountryHeatData? _countryData;
  List<CompareCountryData> _barCompare = [];
  List<CountryYearlyHeatData> _history = [];
  Map<String, dynamic>? _meta;

  List<CountryYearlyHeatData> _globalHistory = [];
  double? _globalAnomaly;
  double? _globalTas;

  static const int lastRealYear = 2024;

  final List<Color> chartColors = [
    Colors.deepOrange,
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

  Future<void> _fetchCountryDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repository.fetchCountryDetail(
        isoA3: widget.isoA3,
        year: widget.year,
      );
      setState(() {
        _countryData = res['country'] as CountryHeatData?;
        _barCompare = res['barCompare'] as List<CompareCountryData>;
        _history = res['history'] as List<CountryYearlyHeatData>;
        _meta = res['meta'] as Map<String, dynamic>;

        final globalItem = _barCompare.firstWhere(
          (e) => e.isoA3 == "GLOBAL",
          orElse: () => CompareCountryData(
            isoA3: 'GLOBAL',
            country: 'Global',
            tas: 0,
            anomaly: 0,
            flag: null,
          ),
        );
        _globalAnomaly = globalItem.anomaly;
        _globalTas = globalItem.tas;
        _globalHistory = _buildGlobalHistory();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  List<CountryYearlyHeatData> _buildGlobalHistory() {
    if (_globalAnomaly == null || _globalTas == null || _history.isEmpty) {
      return [];
    }
    return _history
        .map((e) => CountryYearlyHeatData(
              year: e.year,
              tas: _globalTas ?? 0,
              anomaly: _globalAnomaly ?? 0,
            ))
        .toList();
  }

  String _formatTemp(num value) => value.toStringAsFixed(2);

  // Returns the scientific summary text for the selected year and country
  String buildHeadline(CountryHeatData? d) {
    if (d == null) return '';
    String diff = "";
    if (_globalAnomaly != null) {
      double delta = d.anomaly - _globalAnomaly!;
      if (delta.abs() < 0.01) {
        diff = "This is almost equal to the global average.";
      } else if (delta > 0) {
        diff = "That's ${(delta).toStringAsFixed(2)}°C higher than the global average.";
      } else {
        diff = "That's ${(delta.abs()).toStringAsFixed(2)}°C lower than the global average.";
      }
    }
    String proj = widget.year > lastRealYear
        ? " Note: The data for ${widget.year} is a projection (not real observation)."
        : "";
    return 'In ${widget.year}, the temperature anomaly in ${d.entity} was ${_formatTemp(d.anomaly)}°C (TAS: ${_formatTemp(d.tas)}°C). $diff$proj';
  }

  // Returns a list of FlSpot for a given selector
  List<FlSpot> _spots(List<CountryYearlyHeatData> data, double Function(CountryYearlyHeatData) selector) {
    return data.map((e) => FlSpot(e.year.toDouble(), selector(e))).toList();
  }

  // Returns observed FlSpots (<= lastRealYear)
  List<FlSpot> _observedSpots(List<CountryYearlyHeatData> data, double Function(CountryYearlyHeatData) selector) {
    return data.where((e) => e.year <= lastRealYear).map((e) => FlSpot(e.year.toDouble(), selector(e))).toList();
  }

  // Returns projected FlSpots (> lastRealYear)
  List<FlSpot> _projectedSpots(List<CountryYearlyHeatData> data, double Function(CountryYearlyHeatData) selector) {
    return data.where((e) => e.year > lastRealYear).map((e) => FlSpot(e.year.toDouble(), selector(e))).toList();
  }

  // Returns the mean of observed data
  double? _meanObserved(List<CountryYearlyHeatData> data, double Function(CountryYearlyHeatData) selector) {
    final obs = data.where((e) => e.year <= lastRealYear).toList();
    if (obs.isEmpty) return null;
    final s = obs.fold<double>(0, (p, c) => p + selector(c));
    return s / obs.length;
  }

  // X axis years for the charts
  List<int> _getXAxisYears() {
    if (_history.isEmpty) return [];
    int first = _history.first.year;
    int last = _history.last.year;
    int mid = ((first + last) / 2).round();
    return [first, mid, last];
  }

  // Flag widget: SVG and raster support
  Widget _buildCountryFlag(String? flagUrl) {
    if (flagUrl == null) return const SizedBox.shrink();
    if (flagUrl.toLowerCase().endsWith('.svg')) {
      // For SVG
      return SvgPicture.network(
        flagUrl,
        width: 110,
        height: 110,
        fit: BoxFit.cover,
        placeholderBuilder: (context) => Container(
          width: 110, height: 110,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    } else {
      // For PNG/JPG
      return Image.network(
        flagUrl,
        width: 110,
        height: 110,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => Container(
          color: Colors.grey[300],
          child: const Center(child: Icon(Icons.image_not_supported, size: 44, color: Colors.grey)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isForecast = widget.year > lastRealYear;
    final String pageTitle = "${widget.isoA3} - ${widget.year}";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: pageTitle,
        showDrawer: false,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : _countryData == null
                  ? const Center(child: Text('No data available'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Country flag at the top (supports SVG)
                          Center(
                            child: Container(
                              width: 110,
                              height: 110,
                              margin: const EdgeInsets.only(bottom: 10, top: 0),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade200, width: 1.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 12,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: _buildCountryFlag(_countryData?.flag),
                              ),
                            ),
                          ),

                          // Title in English with dark color
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12, top: 6),
                            child: Text(
                              'Warming of ${_countryData?.entity ?? ''} in ${widget.year}',
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),

                          // Scientific summary below the title
                          Padding(
                            padding: const EdgeInsets.only(top: 0, bottom: 12),
                            child: Text(
                              buildHeadline(_countryData),
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                                height: 1.45,
                              ),
                            ),
                          ),

                          // Info table below the summary
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            child: Table(
                              border: TableBorder.all(color: Colors.grey.shade300, width: 1.0),
                              columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2)},
                              children: [
                                _buildTableRow('Country', _countryData!.entity),
                                _buildTableRow('Year', widget.year.toString()),
                                _buildTableRow('Anomaly (ΔT)', "${_formatTemp(_countryData!.anomaly)}°C"),
                                _buildTableRow('Temperature (TAS)', "${_formatTemp(_countryData!.tas)}°C"),
                                _buildTableRow('Data Type', widget.year > lastRealYear ? 'Projection' : 'Observed'),
                                _buildTableRow('Scenario', (_meta?['scenario'] ?? '-').toString()),
                                _buildTableRow('Baseline', (_meta?['baseline'] ?? '-').toString()),
                                _buildTableRow('Ensemble', (_meta?['ensemble'] ?? '-').toString()),
                                _buildTableRow('Units', "TAS: °C, Anomaly: °C (relative)"),
                              ],
                            ),
                          ),

                          // Pie Chart section
                          _ChartSection(
                            title: 'Share of Country Anomaly vs Global Average',
                            description:
                                'The share of ${_countryData!.entity} anomaly from the sum of country and global anomalies in ${widget.year}.',
                            child: (_globalAnomaly == null || _countryData == null)
                                ? const Text('No data')
                                : SizedBox(
                                    height: 180,
                                    child: PieChart(
                                      PieChartData(
                                        sections: [
                                          PieChartSectionData(
                                            value: _countryData!.anomaly,
                                            title: '${_formatTemp(_countryData!.anomaly)}°C',
                                            color: Colors.deepOrange,
                                            radius: 50,
                                            titleStyle: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          PieChartSectionData(
                                            value: _globalAnomaly!,
                                            title: 'Global\n${_formatTemp(_globalAnomaly!)}°C',
                                            color: Colors.teal,
                                            radius: 44,
                                            titleStyle: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        sectionsSpace: 4,
                                        centerSpaceRadius: 30,
                                      ),
                                    ),
                                  ),
                          ),

                          // Bar Chart section
                          _ChartSection(
                            title: 'Anomaly Comparison (${widget.year}) – ${widget.isoA3}',
                            description: 'Comparison between this country, global average, and selected countries.',
                            child: _barCompare.isEmpty
                                ? const Text('No data available')
                                : SizedBox(
                                    height: 320,
                                    child: BarChart(
                                      BarChartData(
                                        alignment: BarChartAlignment.spaceAround,
                                        maxY: _barCompare.map((e) => e.anomaly).reduce(max) * 1.14,
                                        titlesData: FlTitlesData(
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (double value, TitleMeta meta) {
                                                final i = value.toInt();
                                                if (i < 0 || i >= _barCompare.length) {
                                                  return const SizedBox.shrink();
                                                }
                                                return SideTitleWidget(
                                                  meta: meta,
                                                  child: RotatedBox(
                                                    quarterTurns: 1,
                                                    child: Text(
                                                      _barCompare[i].country,
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
                                              reservedSize: 72,
                                            ),
                                          ),
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (value, _) =>
                                                  Text(_formatTemp(value), style: const TextStyle(fontSize: 10)),
                                              reservedSize: 42,
                                            ),
                                          ),
                                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        ),
                                        barGroups: List.generate(
                                          _barCompare.length,
                                          (i) => BarChartGroupData(
                                            x: i,
                                            barRods: [
                                              BarChartRodData(
                                                toY: _barCompare[i].anomaly,
                                                color: _barCompare[i].isoA3 == widget.isoA3
                                                    ? Colors.deepOrange
                                                    : (_barCompare[i].isoA3 == "GLOBAL"
                                                        ? Colors.teal
                                                        : chartColors[(i - 2) % chartColors.length]),
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

                          // Multi-Line Chart (Anomaly trend + Global)
                          _ChartSection(
                            title: 'Anomaly Trend vs Global – ${widget.isoA3}',
                            description:
                                'Annual anomaly trend for ${_countryData!.entity}. Solid = observed (≤ $lastRealYear), faded = projection (> $lastRealYear). Includes observed mean line.',
                            child: _history.isEmpty
                                ? const Text('No trend data')
                                : SizedBox(
                                    height: 260,
                                    child: LineChart(
                                      LineChartData(
                                        minY: _history.map((e) => e.anomaly).reduce(min) * 0.98,
                                        maxY: _history.map((e) => e.anomaly).reduce(max) * 1.06,
                                        lineBarsData: [
                                          // Country observed anomalies
                                          LineChartBarData(
                                            spots: _observedSpots(_history, (e) => e.anomaly),
                                            isCurved: true,
                                            color: Colors.deepOrange,
                                            barWidth: 3.2,
                                            isStrokeCapRound: true,
                                            dotData: FlDotData(show: false),
                                            belowBarData: BarAreaData(show: false),
                                          ),
                                          // Country projected anomalies
                                          LineChartBarData(
                                            spots: _projectedSpots(_history, (e) => e.anomaly),
                                            isCurved: true,
                                            color: Colors.deepOrange.withOpacity(0.4),
                                            barWidth: 3.0,
                                            isStrokeCapRound: true,
                                            dotData: FlDotData(show: false),
                                            belowBarData: BarAreaData(show: false),
                                          ),
                                          // Global (flat per API) — observed coloring
                                          if (_globalHistory.isNotEmpty)
                                            LineChartBarData(
                                              spots: _observedSpots(_globalHistory, (e) => e.anomaly),
                                              isCurved: false,
                                              color: Colors.teal.withOpacity(0.9),
                                              barWidth: 2.5,
                                              isStrokeCapRound: true,
                                              dotData: FlDotData(show: false),
                                              belowBarData: BarAreaData(show: false),
                                            ),
                                          if (_globalHistory.isNotEmpty)
                                            LineChartBarData(
                                              spots: _projectedSpots(_globalHistory, (e) => e.anomaly),
                                              isCurved: false,
                                              color: Colors.teal.withOpacity(0.35),
                                              barWidth: 2.0,
                                              isStrokeCapRound: true,
                                              dotData: FlDotData(show: false),
                                              belowBarData: BarAreaData(show: false),
                                            ),
                                        ],
                                        extraLinesData: ExtraLinesData(horizontalLines: [
                                          if (_meanObserved(_history, (e) => e.anomaly) != null)
                                            HorizontalLine(
                                              y: _meanObserved(_history, (e) => e.anomaly)!,
                                              color: Colors.grey.shade600,
                                              strokeWidth: 1.4,
                                              dashArray: [6, 6],
                                              label: HorizontalLineLabel(
                                                show: true,
                                                alignment: Alignment.topRight,
                                                padding: const EdgeInsets.only(right: 8, bottom: 4),
                                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                                                labelResolver: (_) =>
                                                    'Mean (≤ $lastRealYear): ${_formatTemp(_meanObserved(_history, (e) => e.anomaly)!)}°C',
                                              ),
                                            ),
                                        ]),
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
                                                  Text(_formatTemp(value), style: const TextStyle(fontSize: 10)),
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
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                                    ),
                                                  );
                                                }
                                                return const SizedBox.shrink();
                                              },
                                              reservedSize: 38,
                                            ),
                                          ),
                                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        ),
                                        gridData: FlGridData(show: false),
                                        borderData: FlBorderData(show: false),
                                      ),
                                    ),
                                  ),
                          ),
                          if (isForecast)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 16),
                              child: Text(
                                "Solid ≤ $lastRealYear: observed. Faded > $lastRealYear: projections (SSP2-4.5).",
                                style: const TextStyle(fontSize: 12, color: Colors.indigo),
                              ),
                            ),
                          // TAS Trend (absolute temperature)
                          _ChartSection(
                            title: 'Absolute Temperature (TAS) Trend – ${widget.isoA3}',
                            description:
                                'Mean surface air temperature over years. Solid = observed (≤ $lastRealYear), faded = projection (> $lastRealYear). Includes observed mean line.',
                            child: _history.isEmpty
                                ? const Text('No data')
                                : SizedBox(
                                    height: 240,
                                    child: LineChart(
                                      LineChartData(
                                        minY: _history.map((e) => e.tas).reduce(min) * 0.98,
                                        maxY: _history.map((e) => e.tas).reduce(max) * 1.04,
                                        lineBarsData: [
                                          // Observed TAS
                                          LineChartBarData(
                                            spots: _observedSpots(_history, (e) => e.tas),
                                            isCurved: true,
                                            color: Colors.blue,
                                            barWidth: 3.0,
                                            belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.20)),
                                            dotData: FlDotData(show: false),
                                          ),
                                          // Projected TAS
                                          LineChartBarData(
                                            spots: _projectedSpots(_history, (e) => e.tas),
                                            isCurved: true,
                                            color: Colors.blueGrey.withOpacity(0.6),
                                            barWidth: 2.8,
                                            belowBarData:
                                                BarAreaData(show: true, color: Colors.blueGrey.withOpacity(0.18)),
                                            dotData: FlDotData(show: false),
                                          ),
                                        ],
                                        extraLinesData: ExtraLinesData(horizontalLines: [
                                          if (_meanObserved(_history, (e) => e.tas) != null)
                                            HorizontalLine(
                                              y: _meanObserved(_history, (e) => e.tas)!,
                                              color: Colors.grey.shade700,
                                              strokeWidth: 1.4,
                                              dashArray: [6, 6],
                                              label: HorizontalLineLabel(
                                                show: true,
                                                alignment: Alignment.bottomRight,
                                                padding: const EdgeInsets.only(right: 8, top: 4),
                                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                                                labelResolver: (_) =>
                                                    'Mean (≤ $lastRealYear): ${_formatTemp(_meanObserved(_history, (e) => e.tas)!)}°C',
                                              ),
                                            ),
                                        ]),
                                        lineTouchData: LineTouchData(
                                          touchTooltipData: LineTouchTooltipData(
                                            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                                              return LineTooltipItem(
                                                'Year: ${spot.x.toInt()}\nTAS: ${_formatTemp(spot.y)}°C',
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
                                                  Text(_formatTemp(value), style: const TextStyle(fontSize: 10)),
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
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                                    ),
                                                  );
                                                }
                                                return const SizedBox.shrink();
                                              },
                                              reservedSize: 38,
                                            ),
                                          ),
                                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        ),
                                        gridData: FlGridData(show: false),
                                        borderData: FlBorderData(show: false),
                                      ),
                                    ),
                                  ),
                          ),
                          if (isForecast)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 16),
                              child: Text(
                                "Blue-grey area after $lastRealYear represents projected temperatures (SSP2-4.5).",
                                style: const TextStyle(fontSize: 12, color: Colors.indigo),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  TableRow _buildTableRow(String key, String value) {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey.shade100),
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(value, style: const TextStyle(fontFamily: 'RobotoMono')),
        ),
      ],
    );
  }
}

// Chart section card used for all charts
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
            Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
