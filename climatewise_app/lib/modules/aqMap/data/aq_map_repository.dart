// lib/modules/aqMap/data/aq_map_repository.dart
//
// AqMapRepository:
// - app-status, overlay-times, legend
// - build URL for PNG overlays (z=3..8) and forecast PNG
// - fetch JSON forecast (format=json)
// - fetch overlay-grids JSON for Zoom >= 9 (past)
// - fetch forecast-grids JSON for Zoom >= 8 (future)
// - fetch point-assess JSON (future, t=+H)
// - fetch stations by bbox / near
//
// Debug policy:
//   * Print FULL URLs (relative + absolute) for every request
//   * DO NOT print response bodies in debug

import 'package:flutter/foundation.dart';
import 'dart:convert';

import '../../../core/constants/app_constants.dart'; // BASE_API_URL
import '../../../core/services/api_service.dart';
import '../models/app_status.dart';         // <-- uses AppStatus.fromJson
import '../models/overlay_slot.dart';
import '../models/legend.dart';
import '../models/overlay_grid.dart';      // past grid
import '../models/forecast_grid.dart';     // future grid
import '../models/point_assess.dart';
import '../models/stations_model.dart';

class OverlayTimesResult {
  final List<OverlaySlot> items;
  final String? latestGid;
  final String? latestT1Iso;

  const OverlayTimesResult({
    required this.items,
    required this.latestGid,
    required this.latestT1Iso,
  });

  bool get isEmpty => items.isEmpty;
}

class AqMapRepository {
  final ApiService api = ApiService(ignoreSSLError: true);

  // lightweight cache for legend by product
  final Map<String, Legend> _legendCacheByProduct = {};

  /// Build relative endpoint for ApiService
  String getEndpoint(String action, {Map<String, String>? query}) {
    late final String base;
    switch (action) {
      case 'app_status':
        base = 'frontend/air-quality/app-status';
        break;
      case 'overlay_times':
        base = 'frontend/air-quality/overlay-times';
        break;
      case 'overlays': // image (PNG/WEBP) - we only build URL
        base = 'frontend/air-quality/overlays';
        break;
      case 'legend':
        base = 'frontend/air-quality/legend';
        break;
      case 'forecast': // PNG or JSON based on format
        base = 'frontend/air-quality/forecast';
        break;
      case 'overlay_grids': // JSON grid for past in Zoom >= 9
        base = 'frontend/air-quality/overlay-grids';
        break;
      case 'forecast_grids': // JSON grid for future in Zoom >= 8
        base = 'frontend/air-quality/forecast-grids';
        break;
      case 'point_assess':
        base = 'frontend/air-quality/point-assess';
        break;
      case 'stations':
        base = 'frontend/air-quality/stations';
        break;
      case 'stations_near':
        base = 'frontend/air-quality/stations/near';
        break;
      default:
        throw ArgumentError('Unknown action: $action');
    }

    if (query == null || query.isEmpty) return base;
    final qs = query.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$base?$qs';
  }

  // optional: bucket helper already used by app-status location
  double? _bucket(double? v) =>
      v == null ? null : (v / 0.25).roundToDouble() * 0.25;

  // -------------------- app-status (UPDATED) --------------------

  /// Unified app-status:
  /// - Past (real): pass `gid` (t is ignored)
  /// - Forecast (now/+H): pass `tNow=true` or `tHours` (0..12)
  /// - Always echo `product`; optionally send `z`
  /// - bbox (w,s,e,n) برای شمارش ایستگاه‌ها در سرور (اگر پیاده‌سازی شده باشد)
  ///
  /// NOTE (contract v2):
  /// - `clock_min` همیشه مثبت است؛ جهت گذشته/آینده را از `mode` بگیر.
  Future<AppStatus?> fetchAppStatus({
    String product = 'no2',
    // time selectors
    String? gid,            // past (real) by gid
    bool tNow = false,      // forecast-now
    int? tHours,            // forecast +H
    // view/state
    int? z,                 // 3..12
    List<double>? bbox,     // [W,S,E,N] -> sent as w,s,e,n
    double? lat,
    double? lon,
    bool noCache = false,
  }) async {
    final q = <String, String>{'product': product};

    // lat/lon (bucketed) for is_day
    final bLat = _bucket(lat);
    final bLon = _bucket(lon);
    if (bLat != null) q['lat'] = bLat.toStringAsFixed(2);
    if (bLon != null) q['lon'] = bLon.toStringAsFixed(2);

    // z (if server uses it for gating)
    if (z != null) q['z'] = z.toString();

    // time selection: prefer gid (past)
    if (gid != null && gid.isNotEmpty) {
      q['gid'] = gid;
    } else {
      // forecast branch: t=now or +H
      final t = _normalizeTParam(tNow: tNow, tHours: tHours);
      q['t'] = t;
    }

    // bbox → split as w,s,e,n (server expects split keys, not single 'bbox')
    if (bbox != null && bbox.length == 4) {
      q['w'] = bbox[0].toString();
      q['s'] = bbox[1].toString();
      q['e'] = bbox[2].toString();
      q['n'] = bbox[3].toString();
    }

    if (noCache) q['nocache'] = '1';

    final endpoint = getEndpoint('app_status', query: q);
    if (kDebugMode) {
      final abs = '$BASE_API_URL$endpoint';
      debugPrint('[aqMap][GET] app_status => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is Map && resp['succeed'] == true) {
      // ✅ IMPORTANT: مدل ما fromJson دارد (نه fromMap)
      return AppStatus.fromJson(resp.cast<String, dynamic>());
    }
    return null;
  }

  String _normalizeTParam({required bool tNow, int? tHours}) {
    if (tNow) return 'now';
    final h = (tHours ?? 0).clamp(0, 12);
    return '+$h';
  }

  // -------------------- overlay-times (JSON) --------------------

  Future<OverlayTimesResult?> fetchOverlayTimes({
    String product = 'no2',
    int days = 3,
    String order = 'desc',
    int? limit,
  }) async {
    final q = <String, String>{
      'product': product,
      'days': days.toString(),
      'order': order,
    };
    if (limit != null && limit > 0) q['limit'] = '$limit';

    final endpoint = getEndpoint('overlay_times', query: q);

    if (kDebugMode) {
      final abs = '$BASE_API_URL$endpoint';
      debugPrint('[aqMap][GET] overlay_times => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is! Map || resp['succeed'] != true) return null;

    // items from resp['times']
    final itemsRaw = resp['times'];
    var items = OverlaySlot.listFromItems(itemsRaw);

    // client-side safety sort
    if (order == 'desc') {
      items.sort((a, b) => b.t1.compareTo(a.t1));
    } else if (order == 'asc') {
      items.sort((a, b) => a.t1.compareTo(b.t1));
    }

    // latest from resp['latest']
    OverlaySlot? latestSlot;
    final latestRaw = resp['latest'];
    if (latestRaw is Map) {
      try {
        latestSlot = OverlaySlot.fromMap(latestRaw.cast<String, dynamic>());
      } catch (_) {
        // ignore parse error
      }
    }

    final latestGid = latestSlot?.gid ??
        (items.isNotEmpty
            ? (order == 'desc' ? items.first.gid : items.last.gid)
            : null);

    final latestT1 = latestSlot?.t1.toUtc().toIso8601String() ??
        (items.isNotEmpty
            ? (order == 'desc'
                ? items.first.t1.toUtc().toIso8601String()
                : items.last.t1.toUtc().toIso8601String())
            : null);

    return OverlayTimesResult(
      items: items,
      latestGid: latestGid,
      latestT1Iso: latestT1,
    );
  }

  // -------------------- legend (JSON) --------------------

  Future<Legend?> fetchLegend({
    String product = 'no2',
    bool force = false,
  }) async {
    if (!force && _legendCacheByProduct.containsKey(product)) {
      return _legendCacheByProduct[product]!;
    }

    final endpoint = getEndpoint('legend', query: {'product': product});

    if (kDebugMode) {
      final abs = '$BASE_API_URL$endpoint';
      debugPrint('[aqMap][GET] legend => $abs');
    }

    final resp = await api.get(endpoint);

    if (resp is Map && resp['succeed'] == true) {
      final legend = Legend.fromMap(resp.cast<String, dynamic>());
      _legendCacheByProduct[product] = legend;
      return legend;
    }
    return null;
  }

  // -------------------- overlay PNG URL --------------------

  String buildOverlayUrl({
    required String product,
    required String gid,
    int z = 3,            // 3..8 (floor(zoom))
    bool noCache = false,
  }) {
    final rel = getEndpoint('overlays', query: {
      'product': product,
      'z': z.toString(),
      'v': gid,
      if (noCache) 'nocache': '1',
    });
    final abs = '$BASE_API_URL$rel';

    if (kDebugMode) {
      debugPrint('[aqMap][IMG] overlays (png) => $abs');
    }
    return abs;
  }

  // -------------------- forecast (PNG URL) --------------------

  String buildForecastUrl({
    String product = 'no2',
    int z = 6,                 // 3..8
    int tHours = 0,            // 0..12
    String? palette,
    String? domain,
    bool noCache = false,
    // Stations
    bool stations = false,
    bool stationsDebug = false,
    double? stationsMaxAgeH,
    double? stationsRadiusKm,
    double? stationsPow,
    double? stationsWMax,
    bool? stationsAutoscale,
    bool? stationsForce,
    // Meteo
    bool meteo = false,
    bool meteoDebug = false,
    double? meteoBetaW,
    double? meteoWs0,
    double? meteoBetaBLH,
    double? meteoBLH0,
    double? meteoFmin,
    double? meteoFmax,
  }) {
    final q = <String, String>{
      'product': product,
      'z': z.toString(),
      't': tHours >= 0 ? '+$tHours' : '0',
      'format': 'png',
    };

    if (palette != null && palette.isNotEmpty) q['palette'] = palette;
    if (domain != null && domain.isNotEmpty) q['domain'] = domain;
    if (noCache) q['nocache'] = '1';

    // Stations
    if (stations) q['stations'] = '1';
    if (stationsDebug) q['stations_debug'] = '1';
    if (stationsMaxAgeH != null) q['stations_max_age_h'] = _numToStr(stationsMaxAgeH);
    if (stationsRadiusKm != null) q['stations_radius_km'] = _numToStr(stationsRadiusKm);
    if (stationsPow != null) q['stations_pow'] = _numToStr(stationsPow);
    if (stationsWMax != null) q['stations_w_max'] = _numToStr(stationsWMax);
    if (stationsAutoscale != null) q['stations_autoscale'] = stationsAutoscale ? '1' : '0';
    if (stationsForce != null) q['stations_force'] = stationsForce ? '1' : '0';

    // Meteo
    if (meteo) q['meteo'] = '1';
    if (meteoDebug) q['meteo_debug'] = '1';
    if (meteoBetaW != null) q['meteo_beta_w'] = _numToStr(meteoBetaW);
    if (meteoWs0 != null) q['meteo_ws0'] = _numToStr(meteoWs0);
    if (meteoBetaBLH != null) q['meteo_beta_blh'] = _numToStr(meteoBetaBLH);
    if (meteoBLH0 != null) q['meteo_blh0'] = _numToStr(meteoBLH0);
    if (meteoFmin != null) q['meteo_fmin'] = _numToStr(meteoFmin);
    if (meteoFmax != null) q['meteo_fmax'] = _numToStr(meteoFmax);

    final rel = getEndpoint('forecast', query: q);
    final abs = '$BASE_API_URL$rel';

    if (kDebugMode) {
      debugPrint('[aqMap][IMG] forecast (png) => $abs');
    }
    return abs;
  }

  // -------------------- forecast (JSON) --------------------

  Future<Map<String, dynamic>?> fetchForecastJson({
    String product = 'no2',
    int z = 6,
    int tHours = 0,
    String? palette,
    String? domain,
    bool noCache = false,
    // Stations
    bool stations = false,
    bool stationsDebug = false,
    double? stationsMaxAgeH,
    double? stationsRadiusKm,
    double? stationsPow,
    double? stationsWMax,
    bool? stationsAutoscale,
    bool? stationsForce,
    // Meteo
    bool meteo = false,
    bool meteoDebug = false,
    double? meteoBetaW,
    double? meteoWs0,
    double? meteoBetaBLH,
    double? meteoBLH0,
    double? meteoFmin,
    double? meteoFmax,
  }) async {
    final q = <String, String>{
      'product': product,
      'z': z.toString(),
      't': tHours >= 0 ? '+$tHours' : '0',
      'format': 'json',
    };

    if (palette != null && palette.isNotEmpty) q['palette'] = palette;
    if (domain != null && domain.isNotEmpty) q['domain'] = domain;
    if (noCache) q['nocache'] = '1';

    // Stations
    if (stations) q['stations'] = '1';
    if (stationsDebug) q['stations_debug'] = '1';
    if (stationsMaxAgeH != null) q['stations_max_age_h'] = _numToStr(stationsMaxAgeH);
    if (stationsRadiusKm != null) q['stations_radius_km'] = _numToStr(stationsRadiusKm);
    if (stationsPow != null) q['stations_pow'] = _numToStr(stationsPow);
    if (stationsWMax != null) q['stations_w_max'] = _numToStr(stationsWMax);
    if (stationsAutoscale != null) q['stations_autoscale'] = stationsAutoscale ? '1' : '0';
    if (stationsForce != null) q['stations_force'] = stationsForce ? '1' : '0';

    // Meteo
    if (meteo) q['meteo'] = '1';
    if (meteoDebug) q['meteo_debug'] = '1';
    if (meteoBetaW != null) q['meteo_beta_w'] = _numToStr(meteoBetaW);
    if (meteoWs0 != null) q['meteo_ws0'] = _numToStr(meteoWs0);
    if (meteoBetaBLH != null) q['meteo_beta_blh'] = _numToStr(meteoBetaBLH);
    if (meteoBLH0 != null) q['meteo_blh0'] = _numToStr(meteoBLH0);
    if (meteoFmin != null) q['meteo_fmin'] = _numToStr(meteoFmin);
    if (meteoFmax != null) q['meteo_fmax'] = _numToStr(meteoFmax);

    final endpoint = getEndpoint('forecast', query: q);
    final abs = '$BASE_API_URL$endpoint';

    if (kDebugMode) {
      debugPrint('[aqMap][GET] forecast (json) => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is Map && resp['succeed'] == true) {
      return resp.cast<String, dynamic>();
    }
    return null;
  }

  // -------------------- overlay-grids (JSON) — PAST --------------------

  Future<OverlayGridResponse?> fetchOverlayGrids({
    required String product,    // no2|hcho|o3tot|cldo4
    required int z,             // 9..11
    required String t,          // gid
    required List<double> bbox, // [W,S,E,N]
    String? domain,
    String? palette,
    bool noCache = false,
  }) async {
    assert(bbox.length == 4, 'bbox must be [W,S,E,N]');

    final q = <String, String>{
      'product': product,
      'z': z.toString(),
      't': t,
      'bbox': _bboxToParam(bbox),
    };
    if (domain != null && domain.isNotEmpty) q['domain'] = domain;
    if (palette != null && palette.isNotEmpty) q['palette'] = palette;
    if (noCache) q['nocache'] = '1';

    final endpoint = getEndpoint('overlay_grids', query: q);
    final abs = '$BASE_API_URL$endpoint';

    if (kDebugMode) {
      debugPrint('[aqMap][GET] overlay-grids (json) => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is Map && resp['succeed'] == true) {
      return OverlayGridResponse.fromJson(resp.cast<String, dynamic>());
    }
    return null;
  }

  // -------------------- forecast-grids (JSON) — FUTURE --------------------

  Future<ForecastGridResponse?> fetchForecastGrids({
    required String product,
    required int z,             // 8..12 (server clamps to 9..11)
    required int tHours,        // +H (0..12)
    required List<double> bbox, // [W,S,E,N]
    String? domain,
    String? palette,
    bool noCache = false,

    // Stations (optional)
    bool stations = false,
    bool stationsDebug = false,
    double? stationsMaxAgeH,
    double? stationsRadiusKm,
    double? stationsPow,
    double? stationsWMax,
    bool? stationsAutoscale,
    bool? stationsForce,

    // Meteo (optional)
    bool meteo = false,
    bool meteoDebug = false,
    double? meteoBetaW,
    double? meteoWs0,
    double? meteoBetaBLH,
    double? meteoBLH0,
    double? meteoFmin,
    double? meteoFmax,
  }) async {
    assert(bbox.length == 4, 'bbox must be [W,S,E,N]');
    assert(tHours >= 0 && tHours <= 12, 'tHours must be in [0..12]');

    final q = <String, String>{
      'product': product,
      'z': z.toString(),
      't': '+$tHours',
      'bbox': _bboxToParam(bbox),
    };

    if (domain != null && domain.isNotEmpty) q['domain'] = domain;
    if (palette != null && palette.isNotEmpty) q['palette'] = palette;
    if (noCache) q['nocache'] = '1';

    // Stations
    if (stations) q['stations'] = '1';
    if (stationsDebug) q['stations_debug'] = '1';
    if (stationsMaxAgeH != null) q['stations_max_age_h'] = _numToStr(stationsMaxAgeH);
    if (stationsRadiusKm != null) q['stations_radius_km'] = _numToStr(stationsRadiusKm);
    if (stationsPow != null) q['stations_pow'] = _numToStr(stationsPow);
    if (stationsWMax != null) q['stations_w_max'] = _numToStr(stationsWMax);
    if (stationsAutoscale != null) q['stations_autoscale'] = stationsAutoscale ? '1' : '0';
    if (stationsForce != null) q['stations_force'] = stationsForce ? '1' : '0';

    // Meteo
    if (meteo) q['meteo'] = '1';
    if (meteoDebug) q['meteo_debug'] = '1';
    if (meteoBetaW != null) q['meteo_beta_w'] = _numToStr(meteoBetaW);
    if (meteoWs0 != null) q['meteo_ws0'] = _numToStr(meteoWs0);
    if (meteoBetaBLH != null) q['meteo_beta_blh'] = _numToStr(meteoBetaBLH);
    if (meteoBLH0 != null) q['meteo_blh0'] = _numToStr(meteoBLH0);
    if (meteoFmin != null) q['meteo_fmin'] = _numToStr(meteoFmin);
    if (meteoFmax != null) q['meteo_fmax'] = _numToStr(meteoFmax);

    final endpoint = getEndpoint('forecast_grids', query: q);
    final abs = '$BASE_API_URL$endpoint';

    if (kDebugMode) {
      debugPrint('[aqMap][GET] forecast-grids (json) => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is Map && resp['succeed'] == true) {
      return ForecastGridResponse.fromJson(resp.cast<String, dynamic>());
    }
    return null;
  }

  // -------------------- point-assess (JSON) — FUTURE ONLY --------------------

  Future<PointAssessResponse?> fetchPointAssess({
    required double lat,
    required double lon,
    List<String> products = const ['no2', 'hcho', 'o3tot'],
    int z = 10,          // server clamps 9..11
    int tHours = 0,      // +H (0..12)
    double? radiusKm,
    Map<String, double>? weights,
    bool debug = false,
    bool noCache = false,
  }) async {
    assert(tHours >= 0 && tHours <= 12, 'tHours must be in [0..12]');

    final q = <String, String>{
      'lat': lat.toString(),
      'lon': lon.toString(),
      'products': products.join(','),
      'z': z.toString(),
      't': '+$tHours',
    };
    if (radiusKm != null) q['radius_km'] = _numToStr(radiusKm);
    if (noCache) q['nocache'] = '1';
    if (debug) q['debug'] = '1';
    if (weights != null && weights.isNotEmpty) {
      _appendWeights(q, weights);
    }

    final endpoint = getEndpoint('point_assess', query: q);
    final abs = '$BASE_API_URL$endpoint';

    if (kDebugMode) {
      debugPrint('[aqMap][GET] point-assess => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is Map && resp['succeed'] == true) {
      return PointAssessResponse.fromJson(resp.cast<String, dynamic>());
    }
    return null;
  }

  // -------------------- stations (JSON) — BBOX --------------------

  Future<StationsResponse?> fetchStationsByBBox({
    String product = 'no2',
    required List<double> bbox, // [W,S,E,N]
    int? limit,
    bool points = true,
    double? maxAgeH,
    String? provider,
    bool noCache = false,
  }) async {
    assert(bbox.length == 4, 'bbox must be [W,S,E,N]');

    final q = <String, String>{
      'product': product,
      'bbox': _bboxToParam(bbox),
      'points': points ? '1' : '0',
    };
    if (limit != null && limit > 0) q['limit'] = '$limit';
    if (maxAgeH != null && maxAgeH >= 0) q['max_age_h'] = _numToStr(maxAgeH);
    if (provider != null && provider.isNotEmpty) q['provider'] = provider;
    if (noCache) q['nocache'] = '1';

    final endpoint = getEndpoint('stations', query: q);
    final abs = '$BASE_API_URL$endpoint';

    if (kDebugMode) {
      debugPrint('[aqMap][GET] stations (bbox) => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is Map && resp['succeed'] == true) {
      return StationsResponse.fromJson(resp.cast<String, dynamic>());
    }
    return null;
  }

  // -------------------- stations (JSON) — NEAR --------------------

  Future<StationsResponse?> fetchStationsNear({
    String product = 'no2',
    required double lat,
    required double lon,
    double? radiusKm,
    int? limit,
    bool points = true,
    double? maxAgeH,
    String? provider,
    bool noCache = false,
  }) async {
    final q = <String, String>{
      'product': product,
      'lat': lat.toString(),
      'lon': lon.toString(),
      'points': points ? '1' : '0',
    };
    if (radiusKm != null && radiusKm > 0) q['radius_km'] = _numToStr(radiusKm);
    if (limit != null && limit > 0) q['limit'] = '$limit';
    if (maxAgeH != null && maxAgeH >= 0) q['max_age_h'] = _numToStr(maxAgeH);
    if (provider != null && provider.isNotEmpty) q['provider'] = provider;
    if (noCache) q['nocache'] = '1';

    final endpoint = getEndpoint('stations_near', query: q);
    final abs = '$BASE_API_URL$endpoint';

    if (kDebugMode) {
      debugPrint('[aqMap][GET] stations (near) => $abs');
    }

    final resp = await api.get(endpoint);
    if (resp is Map && resp['succeed'] == true) {
      return StationsResponse.fromJson(resp.cast<String, dynamic>());
    }
    return null;
  }

  // -------------------- utils --------------------

  String _numToStr(num v) => v.toString();

  String _bboxToParam(List<double> bbox) {
    // Format: "W,S,E,N"
    final w = bbox[0];
    final s = bbox[1];
    final e = bbox[2];
    final n = bbox[3];
    return '$w,$s,$e,$n';
  }

  /// Append nested weight params like weights[no2]=0.5
  void _appendWeights(Map<String, String> q, Map<String, double> weights) {
    weights.forEach((k, v) {
      q['weights[$k]'] = v.toString();
    });
  }
}
