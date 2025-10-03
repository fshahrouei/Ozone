// Repository: GasMapRepository
// Purpose: Fetch ozone-related country lists, yearly ranges, country statistics,
// and aggregated statistics for charts via the backend API.
// NOTE: This file only adds English documentation/comments without changing logic.

import '../../../core/services/api_service.dart';
import '../models/gas_data.dart';
import '../models/country_gas_models.dart';
import '../models/chart_models.dart';

/// Provides read-only access to ozone/“gas” datasets for the Gas Map module.
/// All methods call the Laravel API through [ApiService] and transform
/// responses into strongly-typed model objects used by the UI.
class GasMapRepository {
  /// Low-level HTTP client used for all requests.
  /// `ignoreSSLError: true` is intentional for environments with custom certs.
  final ApiService api = ApiService(ignoreSSLError: true);

  /// Resolves an API endpoint path for a given [action].
  ///
  /// Supported actions:
  /// - `'index'`  → list of countries (optionally filtered by `year` via query)
  /// - `'show'`   → single country stats for a specific `id` (iso_a3) and `year`
  /// - `'years'`  → available years
  ///
  /// Throws:
  /// - [ArgumentError] if `id` or `year` is missing for `'show'`.
  /// - [UnimplementedError] for unknown actions.
  String getEndpoint(String action, [dynamic id, int? year]) {
    switch (action) {
      case 'index':
        return "frontend/ozones/countries";
      case 'show':
        if (id == null || year == null) {
          throw ArgumentError('id and year are required');
        }
        return "frontend/ozones/country/$id/$year";
      case 'years':
        return "frontend/ozones/years";
      default:
        throw UnimplementedError('Unknown endpoint: $action');
    }
  }

  /// Internal cache of the last fetched country list.
  List<GasData> _gasData = [];

  /// Returns the last fetched list of countries (from [fetchCountries]).
  List<GasData> get gasData => _gasData;

  /// Fetches the list of countries, optionally filtered by [year].
  ///
  /// Query:
  /// - GET `frontend/ozones/countries?year={year?}`
  ///
  /// Returns a map with:
  /// - `currentYear` → `int` current year inferred from server or the request
  /// - `data`        → `List<GasData>` parsed countries
  ///
  /// Side effects:
  /// - Updates the internal [_gasData] cache.
  Future<Map<String, dynamic>> fetchCountries({int? year}) async {
    String endpoint = getEndpoint('index');
    if (year != null) {
      endpoint += "?year=$year";
    }
    final response = await api.get(endpoint);

    final dataList = response['data'] as List;
    final fetched = dataList.map((e) => GasData.fromJson(e)).toList();
    _gasData = fetched;

    final currentYear = response['current_year'] ?? year ?? 0;

    return {'currentYear': currentYear, 'data': fetched};
  }

  /// Fetches the list of available years for the dataset.
  ///
  /// Query:
  /// - GET `frontend/ozones/years`
  ///
  /// Returns:
  /// - `List<int>` of years, or empty list if the response is not successful.
  Future<List<int>> fetchYears() async {
    final response = await api.get(getEndpoint('years'));
    if (response['succeed'] == true && response['data'] != null) {
      return List<int>.from(response['data']);
    }
    return [];
  }

  /// Fetches per-country statistics for a given [isoA3] and [year].
  ///
  /// Query:
  /// - GET `frontend/ozones/country/{isoA3}/{year}`
  ///
  /// Successful response is transformed into:
  /// - `country`       → [CountryGasData]? Current country meta/values
  /// - `top_countries` → `List<CountryStatData>` top contributors
  /// - `others`        → `double` value of the “Other” segment (non-top)
  /// - `total`         → `double` total aggregated value
  /// - `history`       → `List<CountryYearlyGasData>` time series for country
  ///
  /// Throws:
  /// - [Exception] if the request fails (`succeed != true`).
  Future<Map<String, dynamic>> fetchCountryStatistics({
    required String isoA3,
    required int year,
  }) async {
    final endpoint = getEndpoint('show', isoA3, year);
    final response = await api.get(endpoint);

    if (response['succeed'] == true) {
      // 1) Country
      final countryJson = response['country'];
      CountryGasData? country;
      if (countryJson != null) {
        country = CountryGasData.fromJson(countryJson as Map<String, dynamic>);
      }

      // 2) Top Countries
      final topCountriesJson =
          response['top_countries'] as List<dynamic>? ?? [];
      final topCountries = topCountriesJson
          .map((e) => CountryStatData.fromJson(e as Map<String, dynamic>))
          .toList();

      // 3) Others
      final othersValue = (response['others']?['value'] ?? 0).toDouble();

      // 4) Total
      final total = (response['total'] ?? 0).toDouble();

      // 5) History
      final historyJson = response['history'] as List<dynamic>? ?? [];
      final history = historyJson
          .map((e) => CountryYearlyGasData.fromJson(e as Map<String, dynamic>))
          .toList();

      return {
        'country': country,
        'top_countries': topCountries,
        'others': othersValue,
        'total': total,
        'history': history,
      };
    } else {
      throw Exception('Failed to fetch country data');
    }
  }

  /// Retrieves aggregated statistics used by charts (bar/pie and line).
  ///
  /// Query:
  /// - GET `frontend/ozones/statistics?year={year?}`
  ///
  /// Returns a map with:
  /// - `barPieData`  → `List<GasStatData>` top countries + synthesized “Other”
  /// - `lineData`    → `List<GasHistoryData>` historical time series
  /// - `total`       → `double` overall total
  /// - `currentYear` → `int` year used by the server (or the requested year)
  ///
  /// Notes:
  /// - “Other” segment is appended locally by combining non-top countries into
  ///   a single [GasStatData] with `iso_a3 = 'OTH'`.
  Future<Map<String, dynamic>> fetchStatistics({int? year}) async {
    String endpoint = "frontend/ozones/statistics";
    if (year != null) {
      endpoint += "?year=$year";
    }
    final response = await api.get(endpoint);

    // Bar/Pie chart: top countries + synthesized "Other"
    final barPieData = <GasStatData>[
      ...((response['top_countries'] ?? []) as List)
          .map((e) => GasStatData.fromJson(e)),
      GasStatData.fromJson({
        'iso_a3': 'OTH',
        'name': 'Other',
        'value': response['others']?['value'] ?? 0,
      }),
    ];

    // Line chart: history over time
    final lineData = <GasHistoryData>[
      ...(response['history'] as List<dynamic>)
          .map((e) => GasHistoryData.fromJson(e)),
    ];

    final double total = (response['total'] ?? 0).toDouble();
    final int currentYear = response['year'] ?? year ?? 0;

    return {
      'barPieData': barPieData,
      'lineData': lineData,
      'total': total,
      'currentYear': currentYear,
    };
  }
}
