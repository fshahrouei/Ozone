// lib/modules/healthAdvisor/controllers/health_advisor_controller.dart
import 'package:flutter/foundation.dart';

import '../../../core/utils/guest_user_manager.dart';
import '../data/health_advisor_repository.dart';
import '../models/health_form.dart';
import '../models/health_result_summary.dart';

class HealthAdvisorController extends ChangeNotifier {
  final HealthAdvisorRepository _repository = HealthAdvisorRepository();

  // ---------------- Submit state ----------------
  bool _isLoading = false;
  String? _errorMessage;
  int? _lastStatus; // e.g., 201, 422, 500
  HealthForm? _lastSubmittedForm;
  Map<String, List<String>> _fieldErrors = {};

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int? get lastStatus => _lastStatus;
  HealthForm? get lastSubmittedForm => _lastSubmittedForm;
  Map<String, List<String>> get fieldErrors => Map.unmodifiable(_fieldErrors);

  /// Returns the first error message for a given field (e.g. "name" or "alerts.hours2h")
  String? firstError(String field) {
    final list = _fieldErrors[field];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  /// Check if a field has any error
  bool hasError(String field) => _fieldErrors[field]?.isNotEmpty == true;

  /// Clear all form-related errors and status
  void clearErrors() {
    _fieldErrors = {};
    _errorMessage = null;
    _lastStatus = null;
    notifyListeners();
  }

  // ---------------- List (Saved points) state ----------------
  bool _isFetchingList = false;
  bool _isDeleting = false;

  List<HealthResultSummary> _items = [];
  int _page = 1;
  int _perPage = 10;
  int _total = 0;
  int _lastPage = 1;
  String _appliedSort = '-received_at';
  String? _lastSearch;
  bool _lastHasLocation = false;

  bool get isFetchingList => _isFetchingList;
  bool get isDeleting => _isDeleting;

  List<HealthResultSummary> get items => List.unmodifiable(_items);
  int get page => _page;
  int get perPage => _perPage;
  int get total => _total;
  int get lastPage => _lastPage;
  String get appliedSort => _appliedSort;
  String? get lastSearch => _lastSearch;
  bool get lastHasLocation => _lastHasLocation;

  /// Fetch saved points for the current client (uuid is taken from GuestUserManager)
  Future<bool> fetchSavedPoints({
    String? search,
    bool hasLocation = false,
    String sort = '-received_at',
    int page = 1,
    int perPage = 10,
  }) async {
    _isFetchingList = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uuid = await GuestUserManager.getOrCreateUserId();

      final result = await _repository.fetchSavedPoints(
        uuid: uuid,
        search: search,
        hasLocation: hasLocation,
        sort: sort,
        page: page,
        perPage: perPage,
      );

      _items = result.items;
      _page = result.page;
      _perPage = result.perPage;
      _total = result.total;
      _lastPage = result.lastPage;
      _appliedSort = result.sort ?? sort;
      _lastSearch = search;
      _lastHasLocation = hasLocation;

      notifyListeners();
      return true;
    } on ValidationException catch (ve) {
      _errorMessage = ve.message;
      if (kDebugMode) {
        debugPrint('ValidationException[${ve.status}]: ${ve.fieldErrors}');
      }
      notifyListeners();
      return false;
    } on ApiException catch (ae) {
      _errorMessage = ae.message;
      if (kDebugMode) {
        debugPrint('ApiException[${ae.status}]: ${ae.message}');
      }
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      if (kDebugMode) {
        debugPrint('Unexpected error (fetchSavedPoints): $e');
      }
      notifyListeners();
      return false;
    } finally {
      _isFetchingList = false;
      notifyListeners();
    }
  }

  /// Optimistic delete by numeric id; removes locally on success.
  Future<bool> deleteSavedPoint(int id) async {
    if (id <= 0) {
      _errorMessage = 'Invalid id';
      notifyListeners();
      return false;
    }

    _isDeleting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.deleteById(id);

      // Optimistic removal from local list
      final idx = _items.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        _items = List.of(_items)..removeAt(idx);
        _total = (_total > 0) ? _total - 1 : 0;
      }

      notifyListeners();
      return true;
    } on ApiException catch (ae) {
      _errorMessage = ae.message;
      if (kDebugMode) {
        debugPrint('ApiException[${ae.status}] (delete): ${ae.message}');
      }
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      if (kDebugMode) {
        debugPrint('Unexpected error (deleteSavedPoint): $e');
      }
      notifyListeners();
      return false;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }

  // ---------------- Submit form ----------------
  Future<bool> submitHealthForm(HealthForm form) async {
    _setLoading(true);

    _fieldErrors = {};
    _errorMessage = null;
    _lastStatus = null;
    notifyListeners();

    try {
      final saved = await _repository.submitForm(form);

      _lastSubmittedForm = saved;
      _lastStatus = 201;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on ValidationException catch (ve) {
      _lastSubmittedForm = null;
      _lastStatus = ve.status;
      _errorMessage = ve.message;
      _fieldErrors = ve.fieldErrors;
      if (kDebugMode) {
        debugPrint("ValidationException[${ve.status}]: ${ve.fieldErrors}");
      }
      notifyListeners();
      return false;
    } on ApiException catch (ae) {
      _lastSubmittedForm = null;
      _lastStatus = ae.status;
      _errorMessage = ae.message;
      _fieldErrors = {};
      if (kDebugMode) {
        debugPrint("ApiException[${ae.status}]: ${ae.message}");
      }
      notifyListeners();
      return false;
    } catch (e) {
      _lastSubmittedForm = null;
      _lastStatus = 500;
      _errorMessage = 'Unexpected error: $e';
      _fieldErrors = {};
      if (kDebugMode) {
        debugPrint("Unexpected error: $e");
      }
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
