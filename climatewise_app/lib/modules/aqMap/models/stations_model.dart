// lib/modules/aqMap/models/stations_model.dart
class StationsBBox {
  final double w, s, e, n;
  StationsBBox({required this.w, required this.s, required this.e, required this.n});
  factory StationsBBox.fromJson(Map<String, dynamic> j) => StationsBBox(
    w: (j['w'] as num).toDouble(),
    s: (j['s'] as num).toDouble(),
    e: (j['e'] as num).toDouble(),
    n: (j['n'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {'w': w, 's': s, 'e': e, 'n': n};
}

class StationsSource {
  final String path;
  final String ts;
  final String why;
  StationsSource({required this.path, required this.ts, required this.why});
  factory StationsSource.fromJson(Map<String, dynamic> j) => StationsSource(
    path: j['path']?.toString() ?? 'na',
    ts:   j['ts']?.toString()   ?? 'na',
    why:  j['why']?.toString()  ?? 'na',
  );
  Map<String, dynamic> toJson() => {'path': path, 'ts': ts, 'why': why};
}

class ProviderCount {
  final String name;
  final int count;
  ProviderCount({required this.name, required this.count});
  factory ProviderCount.fromJson(Map<String, dynamic> j) => ProviderCount(
    name: j['name']?.toString() ?? 'unknown',
    count: (j['count'] as num?)?.toInt() ?? 0,
  );
  Map<String, dynamic> toJson() => {'name': name, 'count': count};
}

class StationsSummary {
  final int countTotal;
  final int countReturn;
  final List<ProviderCount> providers;
  final double? ageHMean;
  final StationsBBox bounds;

  StationsSummary({
    required this.countTotal,
    required this.countReturn,
    required this.providers,
    required this.ageHMean,
    required this.bounds,
  });

  factory StationsSummary.fromJson(Map<String, dynamic> j) => StationsSummary(
    countTotal: (j['count_total'] as num?)?.toInt() ?? 0,
    countReturn: (j['count_return'] as num?)?.toInt() ?? 0,
    providers: (j['providers'] as List? ?? [])
        .map((e) => ProviderCount.fromJson(e as Map<String, dynamic>)).toList(),
    ageHMean: (j['age_h_mean'] == null) ? null : (j['age_h_mean'] as num).toDouble(),
    bounds: StationsBBox.fromJson(j['bounds'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'count_total': countTotal,
    'count_return': countReturn,
    'providers': providers.map((e) => e.toJson()).toList(),
    'age_h_mean': ageHMean,
    'bounds': bounds.toJson(),
  };
}

class StationPoint {
  final double lat;
  final double lon;
  final double? val;     // ممکنه null باشه
  final double? ageH;    // ساعت
  final String? provider;

  StationPoint({required this.lat, required this.lon, this.val, this.ageH, this.provider});

  factory StationPoint.fromJson(Map<String, dynamic> j) => StationPoint(
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    val: (j['val'] == null) ? null : (j['val'] as num).toDouble(),
    ageH: (j['age_h'] == null) ? null : (j['age_h'] as num).toDouble(),
    provider: j['provider']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'lat': lat, 'lon': lon,
    if (val != null) 'val': val,
    if (ageH != null) 'age_h': ageH,
    if (provider != null) 'provider': provider,
  };
}

class StationsResponse {
  final bool succeed;
  final int status;
  final String product;
  final StationsBBox bbox;
  final StationsSource source;
  final StationsSummary summary;
  final List<StationPoint> points;

  StationsResponse({
    required this.succeed,
    required this.status,
    required this.product,
    required this.bbox,
    required this.source,
    required this.summary,
    required this.points,
  });

  bool get hasPoints => points.isNotEmpty;

  factory StationsResponse.fromJson(Map<String, dynamic> j) => StationsResponse(
    succeed: j['succeed'] == true,
    status: (j['status'] as num?)?.toInt() ?? 200,
    product: j['product']?.toString() ?? '',
    bbox: StationsBBox.fromJson(j['bbox'] as Map<String, dynamic>),
    source: StationsSource.fromJson(j['source'] as Map<String, dynamic>),
    summary: StationsSummary.fromJson(j['summary'] as Map<String, dynamic>),
    points: (j['points'] as List? ?? [])
        .map((e) => StationPoint.fromJson(e as Map<String, dynamic>)).toList(),
  );

  Map<String, dynamic> toJson() => {
    'succeed': succeed,
    'status': status,
    'product': product,
    'bbox': bbox.toJson(),
    'source': source.toJson(),
    'summary': summary.toJson(),
    'points': points.map((e) => e.toJson()).toList(),
  };
}
