import 'package:flutter/material.dart';

import '../application/ports/self_engine_availability_v2.dart';
import '../domain/entities/self_read_model_v2.dart';
import '../domain/repositories/self_read_repository_v2.dart';
import 'self_page_controller_v2.dart';

typedef OpenDiaryFromSelfV2 = Future<void> Function(String diaryId);

class SelfPageV2 extends StatefulWidget {
  const SelfPageV2({
    required this.repository,
    required this.loadAvailability,
    required this.onOpenDiary,
    required this.onOpenSettings,
    this.onSelfEngineBecameAvailable,
    super.key,
  });

  final SelfReadRepositoryV2 repository;
  final Future<SelfEngineAvailabilityStatusV2> Function() loadAvailability;
  final OpenDiaryFromSelfV2 onOpenDiary;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function()? onSelfEngineBecameAvailable;

  @override
  State<SelfPageV2> createState() => _SelfPageV2State();
}

class _SelfPageV2State extends State<SelfPageV2> with WidgetsBindingObserver {
  late SelfPageControllerV2 _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createController();
  }

  @override
  void didUpdateWidget(covariant SelfPageV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.loadAvailability != widget.loadAvailability) {
      _controller.dispose();
      _createController();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refresh();
    }
  }

  void _createController() {
    _controller = SelfPageControllerV2(
      repository: widget.repository,
      loadAvailability: widget.loadAvailability,
    )..addListener(_changed);
    _controller.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.loading) {
      return const SafeArea(
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView(
          key: const PageStorageKey('self-page-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
          children: [
            Text('Self', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text(
              '一些正在反复出现的人生线索',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 30),
            if (_controller.hasError)
              _QuietStatusV2(
                icon: Icons.sync_problem_outlined,
                text: '暂时没能读到这些线索。',
                actionLabel: '重试',
                onAction: _controller.refresh,
              )
            else ...[
              if (_controller.availability ==
                  SelfEngineAvailabilityStatusV2.disabled)
                _QuietStatusV2(
                  icon: Icons.pause_circle_outline,
                  text: _controller.threads.isEmpty
                      ? 'Self Engine 尚未启用'
                      : 'Self Engine 当前已暂停，已有线索仍可查看。',
                  actionLabel: '前往设置',
                  onAction: _openSettings,
                )
              else if (_controller.availability ==
                  SelfEngineAvailabilityStatusV2.unavailable)
                _QuietStatusV2(
                  icon: Icons.pause_circle_outline,
                  text: _controller.threads.isEmpty
                      ? 'Self Engine 当前无法整理新记录'
                      : 'Self Engine 当前无法整理新记录，已有线索仍可查看。',
                  actionLabel: '前往设置',
                  onAction: _openSettings,
                )
              else if (_controller.engineState.hasLiveWork)
                const _QuietStatusV2(icon: Icons.more_horiz, text: '正在整理最近的记录…')
              else if (_controller.engineState.hasFailedWork)
                const _QuietStatusV2(
                  icon: Icons.schedule_outlined,
                  text: '有些记录暂时还没整理完成。',
                ),
              if (_controller.threads.isEmpty)
                _EmptySelfV2(availability: _controller.availability)
              else ...[
                const SizedBox(height: 26),
                Text('正在形成的线索', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (
                  var index = 0;
                  index < _controller.threads.length;
                  index++
                ) ...[
                  _ThreadRowV2(
                    summary: _controller.threads[index],
                    onTap: () => _openThread(_controller.threads[index]),
                  ),
                  if (index != _controller.threads.length - 1) const Divider(),
                ],
                if (_controller.hasMore) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _controller.loadingMore
                          ? null
                          : _controller.loadMore,
                      child: Text(_controller.loadingMore ? '正在加载…' : '查看更多'),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final wasAvailable =
        _controller.availability == SelfEngineAvailabilityStatusV2.available;
    await widget.onOpenSettings();
    if (!mounted) return;
    final current = await _controller.refresh();
    if (wasAvailable ||
        current != SelfEngineAvailabilityStatusV2.available ||
        widget.onSelfEngineBecameAvailable == null) {
      return;
    }
    try {
      await widget.onSelfEngineBecameAvailable!();
    } catch (_) {
      // The durable worker owns retry/error state; the Self page stays quiet.
    }
    if (mounted) await _controller.refresh();
  }

  Future<void> _openThread(SelfThreadSummaryV2 summary) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SelfThreadDetailPageV2(
          threadId: summary.id,
          repository: widget.repository,
          onOpenDiary: widget.onOpenDiary,
        ),
      ),
    );
    if (mounted) await _controller.refresh();
  }
}

class SelfThreadDetailPageV2 extends StatefulWidget {
  const SelfThreadDetailPageV2({
    required this.threadId,
    required this.repository,
    required this.onOpenDiary,
    super.key,
  });

  final String threadId;
  final SelfReadRepositoryV2 repository;
  final OpenDiaryFromSelfV2 onOpenDiary;

  @override
  State<SelfThreadDetailPageV2> createState() => _SelfThreadDetailPageV2State();
}

class _SelfThreadDetailPageV2State extends State<SelfThreadDetailPageV2> {
  late Future<SelfThreadDetailV2?> _detail;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _detail = widget.repository.getThreadDetail(widget.threadId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('线索')),
      body: FutureBuilder<SelfThreadDetailV2?>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError) {
            return const Center(child: Text('暂时没能读到这条线索。'));
          }
          final detail = snapshot.data;
          if (detail == null) {
            return const Center(child: Text('这条线索已经不再活跃。'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 44),
            children: [
              Text(
                detail.summary.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (detail.summary.description.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  detail.summary.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                '${_rangeLabel(detail.summary.firstSeen, detail.summary.lastSeen)}'
                ' · ${detail.summary.distinctDiaryCount} 篇记录',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 24),
              Text('记录中的片段', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var index = 0; index < detail.evidence.length; index++) ...[
                _EvidenceRowV2(
                  evidence: detail.evidence[index],
                  onTap: () => _openEvidence(detail.evidence[index]),
                ),
                if (index != detail.evidence.length - 1)
                  const Divider(indent: 0),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEvidence(SelfThreadEvidenceV2 evidence) async {
    await widget.onOpenDiary(evidence.diaryId);
    if (!mounted) return;
    setState(_refresh);
  }
}

class _ThreadRowV2 extends StatelessWidget {
  const _ThreadRowV2({required this.summary, required this.onTap});

  final SelfThreadSummaryV2 summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看线索：${summary.title}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (summary.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        summary.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      '${_rangeLabel(summary.firstSeen, summary.lastSeen)}'
                      ' · ${summary.distinctDiaryCount} 篇记录',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceRowV2 extends StatelessWidget {
  const _EvidenceRowV2({required this.evidence, required this.onTap});

  final SelfThreadEvidenceV2 evidence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '查看原日记：${evidence.statement}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dayLabel(evidence.occurredAt),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                evidence.statement,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (evidence.sourceQuote.trim().isNotEmpty) ...[
                const SizedBox(height: 11),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: colors.outlineVariant, width: 2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '“${evidence.sourceQuote}”',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '查看原日记',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietStatusV2 extends StatelessWidget {
  const _QuietStatusV2({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _EmptySelfV2 extends StatelessWidget {
  const _EmptySelfV2({required this.availability});

  final SelfEngineAvailabilityStatusV2 availability;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 72, bottom: 60),
      child: Column(
        children: [
          Icon(
            Icons.grain_rounded,
            size: 30,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 18),
          Text(
            availability == SelfEngineAvailabilityStatusV2.available
                ? '还没有形成明显的长期线索。'
                : '这里还没有可以展示的线索。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            switch (availability) {
              SelfEngineAvailabilityStatusV2.available =>
                '继续记录就好。随着不同日子的经历相互照应，\n这里会慢慢出现一些主题。',
              SelfEngineAvailabilityStatusV2.disabled =>
                '启用后，来自不同日子的经历会在这里慢慢相互照应。',
              SelfEngineAvailabilityStatusV2.unavailable =>
                'AI 设置可用后，新的记录会继续在这里慢慢相互照应。',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _rangeLabel(DateTime first, DateTime last) {
  final start = first.toLocal();
  final end = last.toLocal();
  if (start.year == end.year) {
    if (start.month == end.month) return '${start.year}.${_two(start.month)}';
    return '${start.year}.${_two(start.month)} — ${_two(end.month)}';
  }
  return '${start.year}.${_two(start.month)} — '
      '${end.year}.${_two(end.month)}';
}

String _dayLabel(DateTime value) {
  final date = value.toLocal();
  return '${date.year}年${date.month}月${date.day}日';
}

String _two(int value) => value.toString().padLeft(2, '0');
