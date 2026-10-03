import 'dart:async';

import 'package:flutter/material.dart';

import '../application/diary_sync_controller_v2.dart';

class DiarySyncLifecycleV2 extends StatefulWidget {
  const DiarySyncLifecycleV2({
    required this.controller,
    required this.child,
    super.key,
  });

  final DiarySyncControllerV2 controller;
  final Widget child;

  @override
  State<DiarySyncLifecycleV2> createState() => _DiarySyncLifecycleV2State();
}

class _DiarySyncLifecycleV2State extends State<DiarySyncLifecycleV2>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_sync());
  }

  Future<void> _sync() async {
    try {
      await widget.controller.synchronize();
    } catch (_) {
      // The controller exposes the error to Settings. Sync never blocks app use.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
