import 'dart:async';

import 'package:flutter/material.dart';

import '../application/daily_encouragement_coordinator_v2.dart';
import '../data/daily_encouragement_store_v2.dart';
import '../data/daily_quote_api_client_v2.dart';
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
    final quoteClient = DailyQuoteApiClientV2();
    _coordinator = DailyEncouragementCoordinatorV2(
      store: SharedPreferencesDailyEncouragementStoreV2(),
      generate: quoteClient.fetch,
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
          ? SizedBox(
              height: 82,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '正在翻一页…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          : const SizedBox.shrink();
    }
    final current = _isCurrent(value);
    final colors = Theme.of(context).colorScheme;
    final attribution = [
      if (value.attribution case final attribution?) attribution,
      if (value.provider case final provider?) provider,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          current ? '每日一句' : '昨日一句',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          value.text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.65),
        ),
        if (attribution.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            '— $attribution',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
        if (!current && _loading) ...[
          const SizedBox(height: 6),
          Text('正在寻找今天的句子…', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
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
