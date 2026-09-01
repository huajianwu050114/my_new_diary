import 'dart:async';

import 'package:flutter/material.dart';

import '../application/daily_encouragement_coordinator_v2.dart';
import '../application/diary_ai_service_v2.dart';
import '../data/ai_configuration_store_v2.dart';
import '../data/daily_encouragement_store_v2.dart';
import '../data/gemini_rest_client_v2.dart';
import '../domain/daily_encouragement_v2.dart';

class DailyEncouragementCardV2 extends StatefulWidget {
  const DailyEncouragementCardV2({super.key});

  @override
  State<DailyEncouragementCardV2> createState() =>
      _DailyEncouragementCardV2State();
}

class _DailyEncouragementCardV2State extends State<DailyEncouragementCardV2>
    with WidgetsBindingObserver {
  late final DailyEncouragementCoordinatorV2 _coordinator;
  DailyEncouragementV2? _value;
  bool _loading = true;
  Timer? _midnightTimer;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final configurationStore = AiConfigurationStoreV2();
    final service = DiaryAiServiceV2(
      GeminiRestClientV2(configurationStore: configurationStore),
    );
    _coordinator = DailyEncouragementCoordinatorV2(
      store: SharedPreferencesDailyEncouragementStoreV2(),
      generate: ({required dateKey, required recentTexts}) async =>
          (await service.dailyEncouragement(
            dateKey: dateKey,
            recentTexts: recentTexts,
          )).text,
    );
    _load();
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isCurrent(_value)) {
      _load();
      _scheduleMidnightRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (value == null) {
      return _loading
          ? const SizedBox(
              height: 72,
              child: Center(child: Icon(Icons.more_horiz_rounded, size: 22)),
            )
          : const SizedBox.shrink();
    }
    final current = _isCurrent(value);
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, color: colors.primary, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current ? '今日小笺' : '昨日余温',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value.text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
          if (!current || _loading)
            IconButton(
              tooltip: '刷新今日小笺',
              visualDensity: VisualDensity.compact,
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const Icon(Icons.more_horiz_rounded, size: 20)
                  : const Icon(Icons.refresh_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    if (_loading && _value != null) return;
    if (mounted) setState(() => _loading = true);
    final value = await _coordinator.loadToday();
    if (mounted) {
      setState(() {
        _value = value;
        _loading = false;
      });
      if (_isCurrent(value)) {
        _retryTimer?.cancel();
      } else {
        _scheduleRetry();
      }
    }
  }

  bool _isCurrent(DailyEncouragementV2? value) {
    return value?.dateKey ==
        DailyEncouragementCoordinatorV2.keyFor(DateTime.now());
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextDay.difference(now) + const Duration(seconds: 1),
      () {
        _load();
        _scheduleMidnightRefresh();
      },
    );
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    _retryTimer = Timer(const Duration(minutes: 15), _load);
  }
}
