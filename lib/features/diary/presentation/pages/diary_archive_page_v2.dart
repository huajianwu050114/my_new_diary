import 'package:flutter/material.dart';

import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../../../life_guide/domain/life_fragment_repository_v2.dart';
import 'diary_detail_page_v2.dart';
import 'diary_search_page_v2.dart';

class DiaryArchivePageV2 extends StatefulWidget {
  const DiaryArchivePageV2({
    required this.repository,
    required this.imageStore,
    this.initialYear,
    this.initialMonth,
    this.lifeFragmentRepository,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final int? initialYear;
  final int? initialMonth;
  final LifeFragmentRepositoryV2? lifeFragmentRepository;

  @override
  State<DiaryArchivePageV2> createState() => _DiaryArchivePageV2State();
}

class _DiaryArchivePageV2State extends State<DiaryArchivePageV2> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _monthKeys = {};
  bool _didRevealInitialMonth = false;

  String? get _initialKey {
    final year = widget.initialYear;
    final month = widget.initialMonth;
    return year == null || month == null ? null : '$year-$month';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('时光归档'),
        actions: [
          IconButton(
            tooltip: '搜索日记',
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<DiaryEntryV2>>(
        stream: widget.repository.watchEntries(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('读取日记失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = _groupEntries(snapshot.data!);
          if (groups.isEmpty) {
            return const Center(child: Text('还没有可以归档的日记'));
          }
          _revealInitialMonthAfterLayout();
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final key = '${group.year}-${group.month}';
              return _TimelineMonth(
                key: _monthKeys.putIfAbsent(key, GlobalKey.new),
                group: group,
                initiallyExpanded: key == (_initialKey ?? groups.first.key),
                isFirst: index == 0,
                isLast: index == groups.length - 1,
                onEntryTap: _openEntry,
              );
            },
          );
        },
      ),
    );
  }

  List<_MonthGroup> _groupEntries(List<DiaryEntryV2> entries) {
    final sorted = [...entries]
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    final groups = <String, _MonthGroup>{};
    for (final entry in sorted) {
      final date = entry.entryDate.toLocal();
      final key = '${date.year}-${date.month}';
      groups.putIfAbsent(
        key,
        () => _MonthGroup(year: date.year, month: date.month, entries: []),
      );
      groups[key]!.entries.add(entry);
    }
    return groups.values.toList(growable: false);
  }

  void _revealInitialMonthAfterLayout() {
    if (_didRevealInitialMonth || _initialKey == null) return;
    _didRevealInitialMonth = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _monthKeys[_initialKey]?.currentContext;
      if (!mounted || targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _openEntry(DiaryEntryV2 entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiaryDetailPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          entryId: entry.id,
          lifeFragmentRepository: widget.lifeFragmentRepository,
        ),
      ),
    );
  }

  void _openSearch() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiarySearchPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          lifeFragmentRepository: widget.lifeFragmentRepository,
        ),
      ),
    );
  }
}

class _MonthGroup {
  const _MonthGroup({
    required this.year,
    required this.month,
    required this.entries,
  });

  final int year;
  final int month;
  final List<DiaryEntryV2> entries;

  String get key => '$year-$month';
}

class _TimelineMonth extends StatefulWidget {
  const _TimelineMonth({
    required this.group,
    required this.initiallyExpanded,
    required this.isFirst,
    required this.isLast,
    required this.onEntryTap,
    super.key,
  });

  final _MonthGroup group;
  final bool initiallyExpanded;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<DiaryEntryV2> onEntryTap;

  @override
  State<_TimelineMonth> createState() => _TimelineMonthState();
}

class _TimelineMonthState extends State<_TimelineMonth> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: widget.isFirst
                        ? Colors.transparent
                        : colors.outlineVariant,
                  ),
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary,
                    border: Border.all(color: colors.surface, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.2),
                        blurRadius: 0,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Container(
                    width: 1.5,
                    color: widget.isLast
                        ? Colors.transparent
                        : colors.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: -13,
                    top: 25,
                    child: Container(
                      width: 14,
                      height: 1.5,
                      color: colors.outlineVariant,
                    ),
                  ),
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${widget.group.year} 年 '
                                        '${widget.group.month} 月',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${widget.group.entries.length} 篇日记',
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _expanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_expanded) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final entry in widget.group.entries)
                                  _TimelineEntryTile(
                                    entry: entry,
                                    onTap: () => widget.onEntryTap(entry),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntryTile extends StatelessWidget {
  const _TimelineEntryTile({required this.entry, required this.onTap});

  final DiaryEntryV2 entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = entry.entryDate.toLocal();
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: SizedBox(
        width: 34,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text('日', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
      title: Text(entry.body, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: entry.tags.isEmpty
          ? null
          : Text(
              entry.tags.map((tag) => '#$tag').join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: entry.mood == null ? null : Text(entry.mood!),
    );
  }
}
