// lib/modules/aqMap/controllers/aq_map_controller.dart
//
// Release notes (this version):
// - Full `_disposed` guard + `safeNotify()` across all code paths
// - Cancel all Timer/debouncers in `dispose()`
// - Post-await checks to avoid notifying after `dispose`
// - Single-flight + latest-wins sequencing for status/grids (via `seq`)
// - Lightweight retry for transient errors
// - `hardReset()` to cleanly reset internal state (optional for hard refresh)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/aq_map_repository.dart';
import '../models/app_status.dart';
import '../models/overlay_slot.dart';
import '../models/legend.dart';
import '../models/overlay_grid.dart';
import '../models/forecast_grid.dart';
import '../models/point_assess.dart';
import '../models/stations_model.dart';

class CameraMoveRequest {
  final LatLng center;
  final double zoom;
  const CameraMoveRequest(this.center, this.zoom);
}

class AqMapController with ChangeNotifier {
  final AqMapRepository repository;
  AqMapController({required this.repository});

  // ---------------- Disposed guard ----------------
  bool _disposed = false;
  void safeNotify() {
    if (_disposed) return;
    try {
      notifyListeners();
    } catch (_) {}
  }

  // ---------------- NA bounds / fallback ----------------
  static const double _naSouth = 15.0;
  static const double _naNorth = 75.0;
  static const double _naWest  = -170.0;
  static const double _naEast  = -50.0;
  static const LatLng _fallbackManhattan = LatLng(40.7580, -73.9855);

  // ---------------- One-shot camera move ----------------
  LatLng? _pendingCenter;
  double? _pendingZoom;
  void setCenterZoom(double lat, double lon, double zoom) {
    if (_disposed) return;
    _pendingCenter = LatLng(lat, lon);
    _pendingZoom = zoom;
    safeNotify();
  }
  CameraMoveRequest? takePendingCameraMove() {
    if (_disposed) return null;
    if (_pendingCenter == null || _pendingZoom == null) return null;
    final req = CameraMoveRequest(_pendingCenter!, _pendingZoom!);
    _pendingCenter = null;
    _pendingZoom = null;
    return req;
  }
  bool isInNorthAmerica(double lat, double lon) =>
      lat >= _naSouth && lat <= _naNorth && lon >= _naWest && lon <= _naEast;
  void jumpToManhattan({double zoom = 11.0}) {
    if (_disposed) return;
    setCenterZoom(_fallbackManhattan.latitude, _fallbackManhattan.longitude, zoom);
  }

  // ---------------- Map state ----------------
  LatLng _center = const LatLng(39.0, -98.0);
  double _zoom = 3.5;
  int _zoomBucket = 3;
  LatLng get center => _center;
  double get zoom => _zoom;
  int get zoomBucket => _zoomBucket;

  // ---------------- App-status ----------------
  AppStatus? _status;
  bool _loading = false;
  Timer? _autoTimer;
  Timer? _statusDebounce;
  AppStatus? get status => _status;
  bool get loading => _loading;
  bool get showPillInThisZoom => true;
  String? get serverMessage => _status?.message;
  bool get isTempoLive => _status?.tempoLive ?? false;
  int get latestAgeMinutes => _status?.tempoAgeMin ?? -1;
  String? get tempoGid => _status?.tempoGid;

  // ---------------- Legend ----------------
  Legend? _legend;
  Legend? get legend => _legend;

  // ---------------- Overlay/product ----------------
  bool _overlayOn = true;
  bool get overlayOn => _overlayOn;

  String _product = 'no2';
  String get product => _product;
  static const List<String> supportedProducts = ['no2', 'hcho', 'o3tot', 'cldo4'];
  bool get stationsSupported => _product == 'no2' || _product == 'o3' || _product == 'o3tot';

  // ---------------- Timeline/slots ----------------
  final Map<String, List<OverlaySlot>> _slotsCacheByProduct = {};
  List<OverlaySlot> _slots = [];
  List<OverlaySlot> get slots => _slots;

  // ---------------- Selection ----------------
  String? _selectedGid;        // past
  int? _selectedForecastHour;  // future (+H)
  String? get selectedGid => _selectedGid;
  int? get selectedForecastHour => _selectedForecastHour;
  bool get isForecast => _selectedForecastHour != null;

  // ---------------- PNG overlay (z 3..7) ----------------
  String? _overlayUrl;
  String? get overlayUrl => _overlayUrl;
  bool _overlayLoading = false;
  bool get overlayLoading => _overlayLoading;
  String? _lastOverlayKey;
  bool get overlayVisibleForZoom {
    final okZoom = _zoomBucket >= 3 && _zoomBucket <= 7;
    return _overlayOn && _overlayUrl != null && okZoom;
  }

  // ---------------- JSON grids ----------------
  OverlayGridResponse? _overlayGridResp;   // past
  bool _overlayGridLoading = false;
  OverlayGridResponse? get overlayGridResponse => _overlayGridResp;
  bool get overlayGridLoading => _overlayGridLoading;

  ForecastGridResponse? _forecastGridResp; // future
  bool _forecastGridLoading = false;
  ForecastGridResponse? get forecastGridResponse => _forecastGridResp;
  bool get forecastGridLoading => _forecastGridLoading;

  // ---------------- Viewport bbox ----------------
  List<double>? _viewportBbox; // [w, s, e, n]
  List<double>? get viewportBbox => _viewportBbox;
  bool get isJsonGridMode => _overlayOn && _zoomBucket >= 8;

  // ---------------- PointAssess ----------------
  PointAssessResponse? _pointAssess;
  bool _pointAssessLoading = false;
  String? _pointAssessError;
  LatLng? _pointAssessAt;
  int _pointAssessTHours = 0;
  Map<String, double>? _pointAssessWeights;
  PointAssessResponse? get pointAssess => _pointAssess;
  bool get pointAssessLoading => _pointAssessLoading;
  String? get pointAssessError => _pointAssessError;
  LatLng? get pointAssessAt => _pointAssessAt;
  int get pointAssessTHours => _pointAssessTHours;
  Map<String, double>? get pointAssessWeights => _pointAssessWeights;

  // ---------------- Stations (Pins) ----------------
  bool _pinsOn = true;
  bool get pinsOn => _pinsOn;
  StationsResponse? _stationsResp;
  bool _stationsLoading = false;
  String? _stationsError;
  StationsResponse? get stationsResponse => _stationsResp;
  bool get stationsLoading => _stationsLoading;
  String? get stationsError => _stationsError;
  String? _stationsProvider;
  double? _stationsMaxAgeH;
  int? _stationsLimit;
  String? get stationsProvider => _stationsProvider;
  double? get stationsMaxAgeH => _stationsMaxAgeH;
  int? get stationsLimit => _stationsLimit;
  Timer? _stationsDebounce;
  bool get _canShowPinsInThisZoom => _zoomBucket >= 9;

  // ---------------- Concurrency (single-flight) ----------------
  int _statusSeq = 0;
  bool _statusBusy = false;
  int _gridSeq = 0;
  bool _gridBusy = false;
  Timer? _gridDebounce;

  // ---------------- Retry helper (transient only) ----------------
  Future<T?> _retryTransient<T>(Future<T?> Function() job,
      {int retries = 2, int backoffMs = 300}) async {
    int attempt = 0;
    while (true) {
      if (_disposed) return null;
      try {
        final out = await job();
        return out;
      } catch (e) {
        final s = e.toString();
        final isHtml = s.contains('<!DOCTYPE html>') || s.contains('text/html');
        final transient = isHtml ||
            s.contains('502') || s.contains('503') || s.contains('504') ||
            s.contains('Timeout') || s.contains('FormatException');
        if (!transient || attempt >= retries) {
          if (kDebugMode) debugPrint('[aqMap][RETRY] giving up after $attempt: $e');
          rethrow;
        }
        final delay = Duration(milliseconds: backoffMs * (attempt + 1));
        if (kDebugMode) debugPrint('[aqMap][RETRY] transient ($s) → wait ${delay.inMilliseconds}ms');
        await Future.delayed(delay);
        attempt++;
      }
    }
  }

  // ===========================================================
  // Public API
  // ===========================================================
  void updateView({LatLng? center, double? zoom}) {
    if (_disposed) return;
    bool changed = false;

    if (center != null &&
        (center.latitude != _center.latitude || center.longitude != _center.longitude)) {
      _center = center;
      changed = true;
    }

    int? prevBucket;
    if (zoom != null && zoom != _zoom) {
      _zoom = zoom;
      prevBucket = _zoomBucket;
      _zoomBucket = _zoom.floor();
      changed = true;
    }

    if (prevBucket != null && prevBucket != _zoomBucket) {
      _handleZoomBucketChange();
      _refreshAppStatusDebounced();
      changed = true;
    }

    if (changed) {
      safeNotify();
    }
  }

  Future<AppStatus?> refreshAppStatus({String? productOverride, bool noCache = false}) async {
    if (_disposed) return _status;
    if (_statusBusy) return _status;
    _statusBusy = true;
    final mySeq = ++_statusSeq;

    final p = (productOverride ?? _product);
    _loading = true;
    safeNotify();

    try {
      final String? gid = (!isForecast) ? _selectedGid : null;
      final bool tNow = isForecast ? (_selectedForecastHour ?? 0) == 0 : false;
      final int? tHours = isForecast ? (_selectedForecastHour ?? 0) : null;
      final int z = _zoomBucket.clamp(3, 12);
      final List<double>? bbox = _viewportBbox;

      final res = await _retryTransient<AppStatus?>(() => repository.fetchAppStatus(
        product: p,
        gid: gid,
        tNow: tNow,
        tHours: tHours,
        z: z,
        bbox: bbox,
        lat: _center.latitude,
        lon: _center.longitude,
        noCache: noCache,
      ));

      if (_disposed) return _status;
      if (mySeq != _statusSeq) return _status;

      if (res != null) _status = res;
      return res;
    } catch (e) {
      if (kDebugMode) debugPrint('[aqMap][ERR] refreshAppStatus: $e');
      return _status;
    } finally {
      _loading = false;
      _statusBusy = false;
      safeNotify();
    }
  }

  void startAutoRefresh() {
    _autoTimer?.cancel();
    if (_disposed) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_disposed) return;
      refreshAppStatus();
    });
  }

  Future<void> hardReset({String product = 'no2'}) async {
    // Full internal state reset (use for a hard screen refresh)
    if (_disposed) return;
    _autoTimer?.cancel();
    _statusDebounce?.cancel();
    _stationsDebounce?.cancel();
    _gridDebounce?.cancel();

    _status = null;
    _legend = null;
    _overlayOn = true;
    _product = product;
    _slots.clear();
    _selectedGid = null;
    _selectedForecastHour = 0;
    _overlayUrl = null;
    _overlayLoading = false;
    _lastOverlayKey = null;
    _overlayGridResp = null;
    _overlayGridLoading = false;
    _forecastGridResp = null;
    _forecastGridLoading = false;
    _viewportBbox = null;
    _pointAssess = null;
    _pointAssessLoading = false;
    _pointAssessError = null;
    _pointAssessAt = null;
    _pointAssessTHours = 0;
    _pointAssessWeights = null;
    _pinsOn = true;
    _stationsResp = null;
    _stationsLoading = false;
    _stationsError = null;
    _stationsProvider = null;
    _stationsMaxAgeH = null;
    _stationsLimit = null;

    _statusSeq = 0;
    _statusBusy = false;
    _gridSeq = 0;
    _gridBusy = false;

    safeNotify();

    await setProduct(product); // This loads legend and timeline
    refreshAppStatus();
    startAutoRefresh();
  }

  void setOverlayOn(bool value) {
    if (_disposed) return;
    if (_overlayOn == value) return;
    _overlayOn = value;

    if (!_overlayOn) {
      _setOverlayUrl(null, loading: false);
      _clearAllGrids();
    } else {
      if (isJsonGridMode) {
        _setOverlayUrl(null, loading: false);
        _requestGridDebounced();
      } else {
        _rebuildOverlayUrlIfNeeded(force: true);
      }
    }

    _maybeFetchStationsDebounced();
    _refreshAppStatusDebounced();
    safeNotify();
  }

  Future<void> setProduct(String newProduct) async {
    if (_disposed) return;
    final p = newProduct.trim().toLowerCase();
    if (p.isEmpty || p == _product) return;
    if (!supportedProducts.contains(p)) {
      if (kDebugMode) debugPrint('[aqMap][WARN] unsupported product: $p');
      return;
    }

    _product = p;

    _selectedGid = null;
    _selectedForecastHour = 0; // start at NOW
    _setOverlayUrl(null, loading: false);
    _clearAllGrids();
    _lastOverlayKey = null;

    _clearPointAssess();

    _clearStations(silent: true);
    if (stationsSupported) _maybeFetchStationsDebounced();

    await loadLegend(product: p, force: false);

    final cached = _slotsCacheByProduct[p];
    if (cached != null && cached.isNotEmpty) {
      _slots = List<OverlaySlot>.from(cached);
      _selectedGid = null;
      _selectedForecastHour = 0;
      if (isJsonGridMode) {
        _requestGridDebounced();
      } else {
        _rebuildOverlayUrlIfNeeded(force: true);
      }
      _refreshAppStatusDebounced();
      safeNotify();
    } else {
      await loadOverlayTimes(product: p, force: false, startAtNow: true);
      _refreshAppStatusDebounced();
    }
  }

  Future<void> loadOverlayTimes({
    String? product,
    bool force = false,
    bool startAtNow = true,
  }) async {
    if (_disposed) return;
    final p = (product ?? _product).trim().toLowerCase();

    if (!force && _slotsCacheByProduct[p]?.isNotEmpty == true) {
      _slots = List<OverlaySlot>.from(_slotsCacheByProduct[p]!);

      if (startAtNow) {
        _selectedGid = null;
        _selectedForecastHour = 0;
        if (isJsonGridMode) {
          _requestGridDebounced();
        } else {
          _rebuildOverlayUrlIfNeeded(force: true);
        }
        _refreshAppStatusDebounced();
        safeNotify();
        return;
      }

      _selectInitialGidFromSlots(notify: true);
      if (isJsonGridMode) _requestGridDebounced();
      else _rebuildOverlayUrlIfNeeded(force: true);
      _refreshAppStatusDebounced();
      return;
    }

    final res = await repository.fetchOverlayTimes(product: p, days: 3, order: 'asc');
    if (_disposed) return;

    if (res == null || res.items.isEmpty) {
      _slots = [];
      _slotsCacheByProduct[p] = const [];
      _selectedGid = null;
      _selectedForecastHour = null;
      _setOverlayUrl(null, loading: false);
      _clearAllGrids();
      _refreshAppStatusDebounced();
      safeNotify();
      return;
    }

    _slotsCacheByProduct[p] = List<OverlaySlot>.from(res.items);
    _slots = List<OverlaySlot>.from(res.items);

    if (startAtNow) {
      _selectedGid = null;
      _selectedForecastHour = 0;
      if (isJsonGridMode) _requestGridDebounced();
      else _rebuildOverlayUrlIfNeeded(force: true);
      _refreshAppStatusDebounced();
      safeNotify();
      return;
    }

    _selectedGid = null;
    _selectedForecastHour = null;

    final latestGid = res.latestGid;
    _setSelectedGid(
      (latestGid != null && _slots.any((s) => s.gid == latestGid))
          ? latestGid
          : _slots.last.gid,
      notify: false,
    );

    if (isJsonGridMode) _requestGridDebounced();
    else _rebuildOverlayUrlIfNeeded(force: true);
    _refreshAppStatusDebounced();
    safeNotify();
  }

  Future<void> loadLegend({String? product, bool force = false}) async {
    if (_disposed) return;
    final p = (product ?? _product).trim().toLowerCase();
    try {
      final lg = await repository.fetchLegend(product: p, force: force);
      if (_disposed) return;
      if (lg != null) {
        _legend = lg;
        safeNotify();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[aqMap][ERR] loadLegend failed: $e');
    }
  }

  void selectOverlayByGid(String gid) {
    if (_disposed) return;
    if (_selectedGid == gid && !isForecast) return;
    final exists = _slots.any((s) => s.gid == gid);
    if (!exists) return;

    _selectedForecastHour = null;
    _setSelectedGid(gid, notify: true);

    if (isJsonGridMode) {
      _setOverlayUrl(null, loading: false);
      _requestGridDebounced();
    } else {
      _rebuildOverlayUrlIfNeeded(force: true);
    }
    _refreshAppStatusDebounced();
  }

  void selectOverlayByIndex(int index) {
    if (_disposed) return;
    if (index < 0 || index >= _slots.length) return;
    selectOverlayByGid(_slots[index].gid);
  }

  void selectForecastHour(int h, {bool noCache = false}) {
    if (_disposed) return;
    if (h < 0 || h > 12) return;
    if (_selectedForecastHour == h && _overlayUrl != null && !isJsonGridMode) return;

    _selectedGid = null;
    _selectedForecastHour = h;

    // Invalidate point-assess tied to previous hour
    if (_pointAssessAt != null) {
      _pointAssess = null;
      _pointAssessError = null;
      _pointAssessTHours = h;
    }

    if (isJsonGridMode) {
      _setOverlayUrl(null, loading: false);
      _requestGridDebounced(); // future grid
    } else {
      _rebuildOverlayUrlIfNeeded(force: true, noCache: noCache);
    }

    _refreshAppStatusDebounced();
    safeNotify();
  }

  void clearForecast({bool rebuild = true}) {
    if (_disposed) return;
    if (!isForecast) return;
    _selectedForecastHour = null;
    _forecastGridResp = null;
    _forecastGridLoading = false;

    if (_slots.isNotEmpty) {
      _setSelectedGid(_slots.last.gid, notify: false);
      if (isJsonGridMode) {
        if (rebuild) _fetchOverlayGridsPast();
      } else {
        if (rebuild) _rebuildOverlayUrlIfNeeded(force: true);
      }
    } else {
      _setOverlayUrl(null, loading: false);
      _overlayGridResp = null;
    }

    _clearPointAssess();
    _refreshAppStatusDebounced();
    safeNotify();
  }

  // ---------------- Viewport / BBOX ----------------
  void setViewportBbox(List<double> bbox) {
    if (_disposed) return;
    if (bbox.length != 4) return;

    const double pad = 0.4;
    final w = bbox[0] - pad;
    final s = bbox[1] - pad;
    final e = bbox[2] + pad;
    final n = bbox[3] + pad;

    _viewportBbox = [w, s, e, n];

    if (isJsonGridMode) _requestGridDebounced();
    _maybeFetchStationsDebounced();
    _refreshAppStatusDebounced();
  }

  // ---------------- Grids fetchers ----------------
  Future<void> _fetchOverlayGridsPast() async {
    if (_disposed) return;
    if (_viewportBbox == null) return;
    if (_selectedGid == null) return;

    if (_gridBusy) return;
    _gridBusy = true;
    final mySeq = ++_gridSeq;

    _overlayGridLoading = true;
    safeNotify();

    try {
      final int zEff = _clampZEff(_zoomBucket);
      final resp = await _retryTransient<OverlayGridResponse?>(() => repository.fetchOverlayGrids(
        product: _product,
        z: zEff,
        t: _selectedGid!, // gid
        bbox: _viewportBbox!,
      ));

      if (_disposed) return;
      if (mySeq != _gridSeq) return;
      _overlayGridResp = resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[aqMap][ERR] _fetchOverlayGridsPast: $e');
      if (mySeq == _gridSeq) _overlayGridResp = null;
    } finally {
      _overlayGridLoading = false;
      _gridBusy = false;
      safeNotify();
    }
  }

  Future<void> _fetchForecastGridsFuture() async {
    if (_disposed) return;
    if (_viewportBbox == null) return;
    if (_selectedForecastHour == null) return;

    if (_gridBusy) return;
    _gridBusy = true;
    final mySeq = ++_gridSeq;

    _forecastGridLoading = true;
    safeNotify();

    try {
      final int zEff = _clampZEff(_zoomBucket);
      final resp = await _retryTransient<ForecastGridResponse?>(() => repository.fetchForecastGrids(
        product: _product,
        z: zEff,
        tHours: _selectedForecastHour!,
        bbox: _viewportBbox!,
      ));

      if (_disposed) return;
      if (mySeq != _gridSeq) return;
      _forecastGridResp = resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[aqMap][ERR] _fetchForecastGridsFuture: $e');
      if (mySeq == _gridSeq) _forecastGridResp = null;
    } finally {
      _forecastGridLoading = false;
      _gridBusy = false;
      safeNotify();
    }
  }

  void _requestGridAccordingToMode() {
    if (_disposed) return;
    if (!isJsonGridMode) return;
    if (_viewportBbox == null) return;

    if (isForecast) {
      _overlayGridResp = null;
      _fetchForecastGridsFuture();
    } else {
      _forecastGridResp = null;
      _fetchOverlayGridsPast();
    }
  }

  void _requestGridDebounced() {
    _gridDebounce?.cancel();
    if (_disposed) return;
    _gridDebounce = Timer(const Duration(milliseconds: 220), () {
      if (_disposed) return;
      _requestGridAccordingToMode();
    });
  }

  // ---------------- Overlay image hooks ----------------
  void onOverlayImageLoadStarted() {
    if (_disposed) return;
    if (!_overlayLoading) {
      _overlayLoading = true;
      safeNotify();
    }
  }
  void onOverlayImageLoadSucceeded() {
    if (_disposed) return;
    if (_overlayLoading) {
      _overlayLoading = false;
      safeNotify();
    }
  }
  void onOverlayImageLoadFailed() {
    if (_disposed) return;
    if (_overlayLoading) {
      _overlayLoading = false;
      safeNotify();
    }
  }

  // ---------------- PointAssess ----------------
  Future<void> fetchPointAssessAt(
    LatLng point, {
    int? tHours,
    double? radiusKm,
    Map<String, double>? weights,
    bool debug = false,
    bool noCache = false,
  }) async {
    if (_disposed) return;
    final int h = (tHours ?? _selectedForecastHour ?? 0).clamp(0, 12);
    final int zEff = _clampZEff(_zoomBucket);

    final Set<String> prods = {'no2', 'hcho', 'o3tot'};
    if (_product == 'cldo4') prods.add('cldo4');

    _pointAssessLoading = true;
    _pointAssessError = null;
    _pointAssessAt = point;
    _pointAssessTHours = h;
    _pointAssessWeights = weights;
    safeNotify();

    try {
      final resp = await repository.fetchPointAssess(
        lat: point.latitude,
        lon: point.longitude,
        products: prods.toList(),
        z: zEff,
        tHours: h,
        radiusKm: radiusKm,
        weights: weights,
        debug: debug,
        noCache: noCache,
      );

      if (_disposed) return;
      if (resp != null && resp.succeed) {
        _pointAssess = resp;
        _pointAssessError = null;
      } else {
        _pointAssess = null;
        _pointAssessError = 'point-assess failed';
      }
    } catch (e) {
      _pointAssess = null;
      _pointAssessError = e.toString();
      if (kDebugMode) debugPrint('[aqMap][ERR] fetchPointAssessAt: $e');
    } finally {
      _pointAssessLoading = false;
      safeNotify();
    }
  }

  Future<void> fetchPointAssessForCenter({
    int? tHours,
    double? radiusKm,
    Map<String, double>? weights,
    bool debug = false,
    bool noCache = false,
  }) =>
      fetchPointAssessAt(
        _center,
        tHours: tHours,
        radiusKm: radiusKm,
        weights: weights,
        debug: debug,
        noCache: noCache,
      );

  void _clearPointAssess() {
    _pointAssess = null;
    _pointAssessLoading = false;
    _pointAssessError = null;
    _pointAssessAt = null;
    _pointAssessTHours = 0;
    _pointAssessWeights = null;
  }

  // ---------------- Stations (Pins) ----------------
  void setPinsOn(bool on) {
    if (_disposed) return;
    if (_pinsOn == on) return;
    _pinsOn = on;
    if (!on) _clearStations();
    else _maybeFetchStationsDebounced();
    safeNotify();
  }

  void setStationsProvider(String? provider) {
    if (_disposed) return;
    _stationsProvider = (provider != null && provider.isNotEmpty) ? provider : null;
    _maybeFetchStationsDebounced();
  }

  void setStationsMaxAgeH(double? h) {
    if (_disposed) return;
    _stationsMaxAgeH = (h != null && h >= 0) ? h : null;
    _maybeFetchStationsDebounced();
  }

  void setStationsLimit(int? limit) {
    if (_disposed) return;
    _stationsLimit = (limit != null && limit > 0) ? limit : null;
    _maybeFetchStationsDebounced();
  }

  void _maybeFetchStationsDebounced() {
    _stationsDebounce?.cancel();
    if (_disposed) return;

    if (!_pinsOn || !_canShowPinsInThisZoom || !stationsSupported || _viewportBbox == null) {
      _clearStations();
      return;
    }

    _stationsDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _fetchStationsForViewport();
    });
  }

  Future<void> _fetchStationsForViewport() async {
    if (_disposed) return;
    if (!_pinsOn) return;
    if (!_canShowPinsInThisZoom || !stationsSupported) {
      _clearStations();
      return;
    }
    final bbox = _viewportBbox;
    if (bbox == null) return;

    _stationsLoading = true;
    _stationsError = null;
    safeNotify();

    try {
      final res = await repository.fetchStationsByBBox(
        product: _product == 'o3tot' ? 'o3' : _product, // map o3tot→o3
        bbox: bbox,
        limit: _stationsLimit ?? 2000,
        points: true,
        maxAgeH: _stationsMaxAgeH ?? 12,
        provider: _stationsProvider,
        noCache: false,
      );
      if (_disposed) return;
      _stationsResp = res;
      _stationsError = null;
    } catch (e) {
      _stationsResp = null;
      _stationsError = e.toString();
      if (kDebugMode) debugPrint('[aqMap][WARN] stations skipped: $e');
    } finally {
      _stationsLoading = false;
      safeNotify();
    }
  }

  void _clearStations({bool silent = false}) {
    _stationsDebounce?.cancel();
    _stationsResp = null;
    _stationsLoading = false;
    _stationsError = null;
    if (!silent) safeNotify();
  }

  // ---------------- Internals ----------------
  void _handleZoomBucketChange() {
    if (_disposed) return;

    if (!_overlayOn) {
      _setOverlayUrl(null, loading: false);
      _clearAllGrids();
      if (!_canShowPinsInThisZoom || !stationsSupported) _clearStations();
      return;
    }

    // z 3..7 → PNG
    if (_zoomBucket >= 3 && _zoomBucket <= 7) {
      _overlayGridResp = null;
      _forecastGridResp = null;

      if (isForecast) {
        _rebuildOverlayUrlIfNeeded(force: true);
      } else if (_selectedGid != null) {
        _rebuildOverlayUrlIfNeeded(force: true);
      } else {
        _setOverlayUrl(null, loading: false);
      }

      if (!_canShowPinsInThisZoom || !stationsSupported) _clearStations();
      return;
    }

    // z ≥ 8 → JSON grids; pins available from z ≥ 9
    if (_zoomBucket >= 8) {
      _setOverlayUrl(null, loading: false); // PNG off
      _requestGridDebounced();

      if (_canShowPinsInThisZoom && stationsSupported) {
        _maybeFetchStationsDebounced();
      } else {
        _clearStations();
      }
      return;
    }

    _setOverlayUrl(null, loading: false);
    _clearAllGrids();
    if (!_canShowPinsInThisZoom || !stationsSupported) _clearStations();
  }

  void _selectInitialGidFromSlots({bool notify = true}) {
    if (_slots.isEmpty) {
      _selectedGid = null;
      _selectedForecastHour = null;
      _setOverlayUrl(null, loading: false);
      _clearAllGrids();
      if (notify) safeNotify();
      return;
    }
    _setSelectedGid(_slots.last.gid, notify: notify);
  }

  void _setSelectedGid(String gid, {bool notify = true}) {
    _selectedGid = gid;
    if (notify) safeNotify();
  }

  void _rebuildOverlayUrlIfNeeded({bool force = false, bool noCache = false}) {
    if (_disposed) return;

    if (!_overlayOn) {
      _setOverlayUrl(null, loading: false);
      return;
    }
    if (_zoomBucket >= 8) {
      _setOverlayUrl(null, loading: false);
      return;
    }
    if (!(_zoomBucket >= 3 && _zoomBucket <= 7)) {
      _setOverlayUrl(null, loading: false);
      return;
    }

    String? url;
    String key;

    if (isForecast) {
      final h = _selectedForecastHour!;
      key = 'F|$_product|+$h' 'h|z=$_zoomBucket';
      if (!force && _lastOverlayKey == key) return;
      url = repository.buildForecastUrl(
        product: _product,
        z: _zoomBucket,
        tHours: h,
        noCache: noCache,
      );
    } else {
      if (_selectedGid == null) {
        _setOverlayUrl(null, loading: false);
        return;
      }
      key = 'P|$_product|$_selectedGid|z=$_zoomBucket';
      if (!force && _lastOverlayKey == key) return;
      url = repository.buildOverlayUrl(
        product: _product,
        gid: _selectedGid!,
        z: _zoomBucket,
        noCache: noCache,
      );
    }

    _lastOverlayKey = key;
    _setOverlayUrl(url, loading: true);
  }

  int _clampZEff(int zBucket) {
    if (zBucket < 9) return 9;   // 8→9
    if (zBucket > 11) return 11; // 12+→11
    return zBucket;              // 9..11
  }

  void _setOverlayUrl(String? url, {required bool loading}) {
    _overlayUrl = url;
    _overlayLoading = loading && (url != null);
    // `safeNotify` is invoked by the call site
  }

  void _clearAllGrids() {
    _overlayGridResp = null;
    _overlayGridLoading = false;
    _forecastGridResp = null;
    _forecastGridLoading = false;
  }

  void _refreshAppStatusDebounced() {
    _statusDebounce?.cancel();
    if (_disposed) return;
    _statusDebounce = Timer(const Duration(milliseconds: 220), () {
      if (_disposed) return;
      refreshAppStatus(noCache: true);
    });
  }

  // ---------------- Lifecycle ----------------
  @override
  void dispose() {
    _disposed = true;
    _autoTimer?.cancel();
    _statusDebounce?.cancel();
    _stationsDebounce?.cancel();
    _gridDebounce?.cancel();
    super.dispose();
  }
}
