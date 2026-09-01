import 'package:flutter/material.dart';

import '../application/app_lock_controller_v2.dart';

class AppLockGateV2 extends StatefulWidget {
  const AppLockGateV2({
    required this.controller,
    required this.child,
    super.key,
  });

  final AppLockControllerV2 controller;
  final Widget child;

  @override
  State<AppLockGateV2> createState() => _AppLockGateV2State();
}

class _AppLockGateV2State extends State<AppLockGateV2>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.controller.unlocked) {
        widget.controller.unlock();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.controller.lock();
    } else if (state == AppLifecycleState.resumed &&
        !widget.controller.unlocked) {
      widget.controller.unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        if (widget.controller.unlocked) {
          return child!;
        }
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 64),
                const SizedBox(height: 16),
                const Text('日记已锁定'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.controller.authenticating
                      ? null
                      : widget.controller.unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(
                    widget.controller.authenticating ? '正在验证…' : '解锁',
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
