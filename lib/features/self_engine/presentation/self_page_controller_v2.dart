import 'package:flutter/foundation.dart';

import '../application/ports/self_engine_availability_v2.dart';
import '../domain/entities/self_read_model_v2.dart';
import '../domain/repositories/self_read_repository_v2.dart';

class SelfPageControllerV2 extends ChangeNotifier {
  SelfPageControllerV2({
    required SelfReadRepositoryV2 repository,
    required Future<SelfEngineAvailabilityStatusV2> Function() loadAvailability,
    this.pageSize = 50,
  }) : _repository = repository,
       _loadAvailability = loadAvailability;

  final SelfReadRepositoryV2 _repository;
  final Future<SelfEngineAvailabilityStatusV2> Function() _loadAvailability;
  final int pageSize;

  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _disposed = false;
  bool _hasError = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  SelfEngineAvailabilityStatusV2 _availability =
      SelfEngineAvailabilityStatusV2.disabled;
  List<SelfThreadSummaryV2> _threads = const [];
  SelfEngineReadStateV2 _engineState = const SelfEngineReadStateV2(
    hasLiveWork: false,
    hasFailedWork: false,
  );

  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  SelfEngineAvailabilityStatusV2 get availability => _availability;
  bool get hasError => _hasError;
  List<SelfThreadSummaryV2> get threads => _threads;
  SelfEngineReadStateV2 get engineState => _engineState;

  Future<SelfEngineAvailabilityStatusV2?> refresh() async {
    if (_refreshing || _loadingMore) return _availability;
    _refreshing = true;
    try {
      final results = await Future.wait<Object>([
        _loadAvailability(),
        _repository.getActiveThreads(limit: pageSize),
        _repository.getSelfEngineState(),
      ]);
      _availability = results[0] as SelfEngineAvailabilityStatusV2;
      final firstPage = results[1] as List<SelfThreadSummaryV2>;
      _threads = List.unmodifiable(firstPage);
      _nextOffset = firstPage.length;
      _hasMore = firstPage.length == pageSize;
      _engineState = results[2] as SelfEngineReadStateV2;
      _hasError = false;
      return _availability;
    } catch (_) {
      _hasError = true;
      return null;
    } finally {
      _loading = false;
      _refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _refreshing || !_hasMore || _hasError) return;
    _loadingMore = true;
    if (!_disposed) notifyListeners();
    try {
      final page = await _repository.getActiveThreads(
        limit: pageSize,
        offset: _nextOffset,
      );
      _nextOffset += page.length;
      final existingIds = _threads.map((thread) => thread.id).toSet();
      _threads = List.unmodifiable([
        ..._threads,
        ...page.where((thread) => existingIds.add(thread.id)),
      ]);
      _hasMore = page.length == pageSize;
    } catch (_) {
      // Keep the existing page and the load-more affordance available to retry.
    } finally {
      _loadingMore = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
