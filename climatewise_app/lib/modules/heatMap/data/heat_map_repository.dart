import '../../../core/services/api_service.dart';
import '../models/heat_data.dart';
import '../models/country_heat_models.dart';
import '../models/chart_models.dart';

/// Repository for fetching heat map related data from the API.
class HeatMapRepository {
  final ApiService api = ApiService(ignoreSSLError: true);

  /// Build API endpoint string based on action type.
  /// 
  /// [action] can be: 'index', 'show', 'years', 'statistics'
  /// [id] is optional and used for country ISO codes.
  /// [year] is optional for year-specific data.
  String getEndpoint(String action, [dynamic id, int? year]) {
    switch (action) {
      case 'index':
        return "frontend/heats/countries/${year ?? ''}";
      case 'show':
        if (id == null || year == null) {
          throw ArgumentError('id and year are required');
        }
        return "frontend/heats/country/$id/$year";
      case 'years':
        return "frontend/heats/years";
      case 'statistics':
        return "frontend/heats/statistics/$year";
      default:
        throw UnimplementedError('Unknown endpoint: $action');
    }
  }

  List<HeatData> _heatData = [];
  List<HeatData> get heatData => _heatData;

  /// Fetch list of countries for a specific year.
  /// Returns a map containing currentYear and the data list.
  Future<Map<String, dynamic>> fetchCountries({int? year}) async {
    String endpoint = getEndpoint('index', null, year);
    final response = await api.get(endpoint);

    final dataList = response['data'] as List;
    final fetched = dataList.map((e) => HeatData.fromJson(e)).toList();
    _heatData = fetched;

    final currentYear = response['current_year'] ?? year ?? 0;
    return {'currentYear': currentYear, 'data': fetched};
  }

  /// Fetch available years for heat map data.
  Future<List<int>> fetchYears() async {
    final response = await api.get(getEndpoint('years'));
    if (response['succeed'] == true && response['data'] != null) {
      return List<int>.from(response['data']);
    }
    return [];
  }

  /// Fetch detailed information for a specific country and year.
  /// Includes country metadata, bar chart comparisons, yearly history, and extra meta info.
  Future<Map<String, dynamic>> fetchCountryDetail({
    required String isoA3,
    required int year,
  }) async {
    final endpoint = getEndpoint('show', isoA3, year);
    final response = await api.get(endpoint);

    if (response['succeed'] == true) {
      // Main country information
      final country = CountryHeatData.fromJson(response['country']);

      // Comparative bar chart (this country, global, and top anomaly countries)
      final barCompare = (response['bar_compare'] as List)
          .map((e) => CompareCountryData.fromJson(e))
          .toList();

      // Yearly history for line chart
      final history = (response['history'] as List)
          .map((e) => CountryYearlyHeatData.fromJson(e))
          .toList();

      // Meta information (baseline, scenario, units, etc.)
      final meta = response['meta'] as Map<String, dynamic>? ?? {};

      return {
        'country': country,
        'barCompare': barCompare,
        'history': history,
        'meta': meta,
        'year': response['year'],
      };
    } else {
      throw Exception(response['message'] ?? 'Failed to fetch country detail');
    }
  }

  /// Fetch global statistics and charts for the statistics page.
  Future<Map<String, dynamic>> fetchStatistics({required int year}) async {
    String endpoint = getEndpoint('statistics', null, year);
    final response = await api.get(endpoint);

    if (response['succeed'] == true) {
      final topCountries = (response['top_countries'] as List)
          .map((e) => HeatCountryStat.fromJson(e))
          .toList();

      final globalAverage = GlobalAverage.fromJson(response['global_average']);

      final trend = (response['trend'] as List)
          .map((e) => HeatTrendYear.fromJson(e))
          .toList();

      final lastRealYear = response['last_real_year'] is int
          ? response['last_real_year']
          : int.tryParse(response['last_real_year'].toString()) ?? year;

      return {
        'topCountries': topCountries,
        'globalAverage': globalAverage,
        'trend': trend,
        'lastRealYear': lastRealYear,
      };
    } else {
      throw Exception('Failed to fetch statistics');
    }
  }
}
