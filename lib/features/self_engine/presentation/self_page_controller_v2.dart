import 'package:flutter/foundation.dart';

import '../domain/entities/self_read_model_v2.dart';
import '../domain/repositories/self_read_repository_v2.dart';

class SelfPageControllerV2 extends ChangeNotifier {
  SelfPageControllerV2({
    required SelfReadRepositoryV2 repository,
    required Future<bool> Function() loadEnabled,
  }) : _repository = repository,
       _loadEnabled = loadEnabled;

  final SelfReadRepositoryV2 _repository;
  final Future<bool> Function() _loadEnabled;

  bool _loading = true;
  bool _refreshing = false;
  bool _disposed = false;
  bool _enabled = false;
  bool _hasError = false;
  List<SelfThreadSummaryV2> _threads = const [];
  SelfEngineReadStateV2 _engineState = const SelfEngineReadStateV2(
    hasLiveWork: false,
    hasFailedWork: false,
  );

  bool get loading => _loading;
  bool get enabled => _enabled;
  bool get hasError => _hasError;
  List<SelfThreadSummaryV2> get threads => _threads;
  SelfEngineReadStateV2 get engineState => _engineState;

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final results = await Future.wait<Object>([
        _loadEnabled(),
        _repository.getActiveThreads(),
        _repository.getSelfEngineState(),
      ]);
      _enabled = results[0] as bool;
      _threads = results[1] as List<SelfThreadSummaryV2>;
      _engineState = results[2] as SelfEngineReadStateV2;
      _hasError = false;
    } catch (_) {
      _hasError = true;
    } finally {
      _loading = false;
      _refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
