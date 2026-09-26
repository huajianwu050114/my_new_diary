import 'dart:async';

import 'package:flutter/widgets.dart';

import '../application/self_engine_job_recovery_v2.dart';
import '../application/self_engine_lifecycle_maintenance_v2.dart';
import '../application/ports/self_engine_runner_v2.dart';

class SelfEngineRecoveryScopeV2 extends StatefulWidget {
  const SelfEngineRecoveryScopeV2({
    required this.recovery,
    required this.child,
    this.runner,
    super.key,
  });

  final SelfEngineJobRecoveryV2 recovery;
  final Widget child;
  final SelfEngineRunnerV2? runner;

  @override
  State<SelfEngineRecoveryScopeV2> createState() =>
      _SelfEngineRecoveryScopeV2State();
}

class _SelfEngineRecoveryScopeV2State extends State<SelfEngineRecoveryScopeV2>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        _resumeMaintenance().catchError((Object error) {
          debugPrint('Self Engine job recovery failed: $error');
          return 0;
        }),
      );
    }
  }

  Future<int> _resumeMaintenance() async {
    return SelfEngineLifecycleMaintenanceV2(
      recovery: widget.recovery,
      runner: widget.runner,
    ).afterResume();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
