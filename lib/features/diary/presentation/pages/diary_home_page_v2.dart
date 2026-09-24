import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../ai/presentation/ai_recap_page_v2.dart';
import '../../../ai/presentation/daily_encouragement_card_v2.dart';
import '../../../ai/presentation/guided_journal_page_v2.dart';
import '../../../ai/domain/guided_journal_v2.dart';
import '../../../analysis/presentation/analysis_page_v2.dart';
import '../../../export/presentation/data_tools_page_v2.dart';
import '../../../festival/data/public_holiday_service_v2.dart';
import '../../../festival/domain/festival_repository_v2.dart';
import '../../../festival/domain/festival_v2.dart';
import '../../../festival/presentation/festivals_page_v2.dart';
import '../../../settings/application/app_lock_controller_v2.dart';
import '../../../settings/application/reminder_service_v2.dart';
import '../../../settings/application/theme_controller_v2.dart';
import '../../../settings/data/local_profile_store_v2.dart';
import '../../../settings/data/privacy_settings_store_v2.dart';
import '../../../settings/presentation/settings_page_v2.dart';
import '../../../life_guide/domain/life_fragment_repository_v2.dart';
import '../../../life_guide/presentation/life_guide_page_v2.dart';
import '../../../life_library/domain/life_document_repository_v2.dart';
import '../../../life_library/presentation/life_library_page_v2.dart';
import '../../application/legacy_migration_controller_v2.dart';
import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import 'diary_calendar_page_v2.dart';
import 'diary_archive_page_v2.dart';
import 'diary_detail_page_v2.dart';
import 'diary_search_page_v2.dart';
import 'favorite_diaries_page_v2.dart';
import 'location_memories_page_v2.dart';
import 'new_diary_page_v2.dart';
import 'recycle_bin_page_v2.dart';
import 'voice_diary_page_v2.dart';

class DiaryHomePageV2 extends StatefulWidget {
  const DiaryHomePageV2({
    required this.repository,
    required this.imageStore,
    required this.festivalRepository,
    required this.publicHolidayService,
    required this.themeController,
    required this.appLockController,
    this.lifeFragmentRepository,
    this.lifeDocumentRepository,
    this.migrationController,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final FestivalRepositoryV2 festivalRepository;
  final PublicHolidayServiceV2 publicHolidayService;
  final ThemeControllerV2 themeController;
  final AppLockControllerV2 appLockController;
  final LifeFragmentRepositoryV2? lifeFragmentRepository;
  final LifeDocumentRepositoryV2? lifeDocumentRepository;
  final LegacyMigrationControllerV2? migrationController;

  @override
  State<DiaryHomePageV2> createState() => _DiaryHomePageV2State();
}

class _DiaryHomePageV2State extends State<DiaryHomePageV2> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(const ['日记', '日历', '生活', '回忆', '我的'][_selectedTab]),
        actions: _selectedTab == 0
            ? [
                IconButton(
                  tooltip: '搜索',
                  onPressed: () => _openSearch(context),
                  icon: const Icon(Icons.search),
                ),
                const SizedBox(width: 4),
              ]
            : null,
      ),
      body: StreamBuilder<List<DiaryEntryV2>>(
        stream: widget.repository.watchEntries(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          return switch (_selectedTab) {
            0 => _JournalTab(
              entries: entries,
              onWrite: () => _openComposer(context),
              onVoice: _openVoiceComposer,
              onGuided: _openGuidedComposer,
              onEntryTap: _openEntry,
              onArchive: () => _openArchive(),
              onMonthArchive: (year, month) =>
                  _openArchive(year: year, month: month),
            ),
            1 => DiaryCalendarPageV2(
              repository: widget.repository,
              imageStore: widget.imageStore,
              lifeFragmentRepository: widget.lifeFragmentRepository,
              embedded: true,
            ),
            2 =>
              widget.lifeDocumentRepository == null
                  ? const Center(child: Text('生活库尚未准备好'))
                  : LifeLibraryPageV2(
                      repository: widget.lifeDocumentRepository!,
                    ),
            3 => _MemoriesTab(
              entries: entries,
              imageStore: widget.imageStore,
              onEntryTap: _openEntry,
              onAiTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => AiRecapPageV2(entries: entries),
                ),
              ),
              onLocationsTap: () =>
                  _openSection(context, _HomeSection.locations),
              onFestivalsTap: () =>
                  _openSection(context, _HomeSection.festivals),
              onLifeGuideTap: widget.lifeFragmentRepository == null
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => LifeGuidePageV2(
                          repository: widget.lifeFragmentRepository!,
                          diaryRepository: widget.repository,
                          imageStore: widget.imageStore,
                        ),
                      ),
                    ),
            ),
            _ => _MeTab(
              profileStore: LocalProfileStoreV2(),
              onOpen: (section) => _openSection(context, section),
            ),
          };
        },
      ),
      floatingActionButton: _selectedTab == 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'voice-diary',
                  tooltip: '语音写日记',
                  onPressed: _openVoiceComposer,
                  child: const Icon(Icons.mic_none_rounded),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  heroTag: 'write-diary',
                  tooltip: '写日记',
                  onPressed: () => _openComposer(context),
                  child: const Icon(Icons.edit_outlined),
                ),
              ],
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '日记',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '日历',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '生活',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_mosaic_outlined),
            selectedIcon: Icon(Icons.auto_awesome_mosaic),
            label: '回忆',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
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

  Future<void> _openComposer(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NewDiaryPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
        ),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiarySearchPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          lifeFragmentRepository: widget.lifeFragmentRepository,
        ),
      ),
    );
  }

  Future<void> _openVoiceComposer() async {
    final draft = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const VoiceDiaryPageV2()));
    if (draft == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NewDiaryPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          initialBody: draft,
        ),
      ),
    );
  }

  Future<void> _openGuidedComposer() async {
    final draft = await Navigator.of(context).push<GuidedJournalDraftV2>(
      MaterialPageRoute(builder: (_) => const GuidedJournalPageV2()),
    );
    if (draft == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NewDiaryPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          initialBody: draft.body,
          initialAiSession: draft.session,
          skipAutomaticReply: true,
        ),
      ),
    );
  }

  Future<void> _openArchive({int? year, int? month}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiaryArchivePageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          lifeFragmentRepository: widget.lifeFragmentRepository,
          initialYear: year,
          initialMonth: month,
        ),
      ),
    );
  }

  Future<void> _openSection(BuildContext context, _HomeSection section) async {
    final Widget page = switch (section) {
      _HomeSection.favorites => FavoriteDiariesPageV2(
        repository: widget.repository,
        imageStore: widget.imageStore,
        lifeFragmentRepository: widget.lifeFragmentRepository,
      ),
      _HomeSection.locations => LocationMemoriesPageV2(
        repository: widget.repository,
        imageStore: widget.imageStore,
        lifeFragmentRepository: widget.lifeFragmentRepository,
      ),
      _HomeSection.festivals => FestivalsPageV2(
        repository: widget.festivalRepository,
        publicHolidayService: widget.publicHolidayService,
      ),
      _HomeSection.analysis => AnalysisPageV2(repository: widget.repository),
      _HomeSection.dataTools => DataToolsPageV2(
        diaryRepository: widget.repository,
        imageStore: widget.imageStore,
        festivalRepository: widget.festivalRepository,
        lifeDocumentRepository: widget.lifeDocumentRepository,
      ),
      _HomeSection.settings => SettingsPageV2(
        themeController: widget.themeController,
        profileStore: LocalProfileStoreV2(),
        privacySettingsStore: PrivacySettingsStoreV2(),
        reminderService: ReminderServiceV2(),
        appLockController: widget.appLockController,
        migrationController: widget.migrationController,
      ),
      _HomeSection.recycleBin => RecycleBinPageV2(
        repository: widget.repository,
        imageStore: widget.imageStore,
      ),
    };
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }
}

class _JournalTab extends StatefulWidget {
  const _JournalTab({
    required this.entries,
    required this.onWrite,
    required this.onVoice,
    required this.onGuided,
    required this.onEntryTap,
    required this.onArchive,
    required this.onMonthArchive,
  });

  final List<DiaryEntryV2> entries;
  final VoidCallback onWrite;
  final VoidCallback onVoice;
  final VoidCallback onGuided;
  final ValueChanged<DiaryEntryV2> onEntryTap;
  final VoidCallback onArchive;
  final void Function(int year, int month) onMonthArchive;

  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  _HomeDiaryFilter _filter = _HomeDiaryFilter.recent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sortedEntries = [...widget.entries]
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    final visibleEntries = switch (_filter) {
      _HomeDiaryFilter.recent => sortedEntries,
      _HomeDiaryFilter.favorites =>
        sortedEntries.where((entry) => entry.isFavorite).toList(),
    };
    final monthSummaries = _monthSummaries(sortedEntries).take(3).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        Text(
          '${now.month}月${now.day}日 · ${_TodayHeader._weekdays[now.weekday - 1]}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '今天，想记下什么？',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        const DailyEncouragementCardV2(),
        const SizedBox(height: 20),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onWrite,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.edit_outlined),
                  ),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '写下这一刻',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 4),
                        Text('几句话、一种心情，或者一张照片'),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '陪我聊着写',
                        onPressed: widget.onGuided,
                        icon: const Icon(Icons.forum_outlined),
                      ),
                      IconButton(
                        tooltip: '语音写日记',
                        onPressed: widget.onVoice,
                        icon: const Icon(Icons.mic_none_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: Text(
                _filter.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${visibleEntries.length} 篇',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_HomeDiaryFilter>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _HomeDiaryFilter.recent,
                label: Text('最近'),
                icon: Icon(Icons.schedule_rounded),
              ),
              ButtonSegment(
                value: _HomeDiaryFilter.favorites,
                label: Text('收藏'),
                icon: Icon(Icons.favorite_border_rounded),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (selected) =>
                setState(() => _filter = selected.first),
          ),
        ),
        const SizedBox(height: 14),
        if (visibleEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 42),
            child: Center(child: Text(_filter.emptyMessage)),
          )
        else
          for (final entry in visibleEntries.take(6))
            _PaperDiaryCard(
              entry: entry,
              onTap: () => widget.onEntryTap(entry),
            ),
        if (visibleEntries.length > 6)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onArchive,
              child: const Text('继续查看'),
            ),
          ),
        if (monthSummaries.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '月份归档',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(onPressed: widget.onArchive, child: const Text('全部')),
            ],
          ),
          const SizedBox(height: 4),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < monthSummaries.length; index++) ...[
                  _MonthArchiveTile(
                    summary: monthSummaries[index],
                    onTap: () => widget.onMonthArchive(
                      monthSummaries[index].year,
                      monthSummaries[index].month,
                    ),
                  ),
                  if (index != monthSummaries.length - 1)
                    const Divider(height: 1, indent: 18, endIndent: 18),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<_MonthSummary> _monthSummaries(List<DiaryEntryV2> entries) {
    final counts = <({int year, int month}), int>{};
    for (final entry in entries) {
      final date = entry.entryDate.toLocal();
      final key = (year: date.year, month: date.month);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries
        .map(
          (entry) => _MonthSummary(
            year: entry.key.year,
            month: entry.key.month,
            count: entry.value,
          ),
        )
        .toList(growable: false);
  }
}

enum _HomeDiaryFilter { recent, favorites }

extension on _HomeDiaryFilter {
  String get title => switch (this) {
    _HomeDiaryFilter.recent => '最近日记',
    _HomeDiaryFilter.favorites => '收藏日记',
  };

  String get emptyMessage => switch (this) {
    _HomeDiaryFilter.recent => '还没有日记，从此刻开始吧',
    _HomeDiaryFilter.favorites => '还没有收藏的日记',
  };
}

class _MonthSummary {
  const _MonthSummary({
    required this.year,
    required this.month,
    required this.count,
  });

  final int year;
  final int month;
  final int count;
}

class _MonthArchiveTile extends StatelessWidget {
  const _MonthArchiveTile({required this.summary, required this.onTap});

  final _MonthSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        Icons.calendar_view_month_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text('${summary.year} 年 ${summary.month} 月'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${summary.count} 篇'),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _PaperDiaryCard extends StatelessWidget {
  const _PaperDiaryCard({required this.entry, required this.onTap});

  final DiaryEntryV2 entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = entry.entryDate.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Column(
                    children: [
                      Text(
                        '${date.day}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${date.month}月',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 62,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(height: 1.55),
                      ),
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Text(
                          entry.tags.map((tag) => '#$tag').join('  '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (entry.mood != null) Text(entry.mood!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoriesTab extends StatelessWidget {
  const _MemoriesTab({
    required this.entries,
    required this.imageStore,
    required this.onEntryTap,
    required this.onAiTap,
    required this.onLocationsTap,
    required this.onFestivalsTap,
    required this.onLifeGuideTap,
  });

  final List<DiaryEntryV2> entries;
  final DiaryImageStoreV2 imageStore;
  final ValueChanged<DiaryEntryV2> onEntryTap;
  final VoidCallback onAiTap;
  final VoidCallback onLocationsTap;
  final VoidCallback onFestivalsTap;
  final VoidCallback? onLifeGuideTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final onThisDay = entries.where((entry) {
      final date = entry.entryDate.toLocal();
      return date.month == now.month &&
          date.day == now.day &&
          date.year != now.year;
    }).toList();
    final photos = entries.where((entry) => entry.imageIds.isNotEmpty).take(8);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            if (onLifeGuideTap != null) ...[
              Expanded(child: _LifeGuideEntryCard(onTap: onLifeGuideTap!)),
              const SizedBox(width: 12),
            ],
            Expanded(child: _AiRecapCard(onTap: onAiTap)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MemoryShortcut(
                icon: Icons.place_outlined,
                label: '地点',
                onTap: onLocationsTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MemoryShortcut(
                icon: Icons.celebration_outlined,
                label: '纪念日',
                onTap: onFestivalsTap,
              ),
            ),
          ],
        ),
        if (onThisDay.isNotEmpty) ...[
          const _SectionTitle(title: '那年今日', icon: Icons.history_rounded),
          ...onThisDay.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MemoryCard(
                entry: entry,
                imageStore: imageStore,
                onTap: () => onEntryTap(entry),
              ),
            ),
          ),
        ],
        if (photos.isNotEmpty) ...[
          const _SectionTitle(
            title: '照片回忆',
            icon: Icons.photo_library_outlined,
          ),
          ...photos.map(
            (entry) => SizedBox(
              height: 190,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PhotoMemoryCard(
                  entry: entry,
                  imageStore: imageStore,
                  onTap: () => onEntryTap(entry),
                ),
              ),
            ),
          ),
        ],
        if (onThisDay.isEmpty && photos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: Text('继续记录，回忆会慢慢在这里生长')),
          ),
      ],
    );
  }
}

class _MeTab extends StatelessWidget {
  const _MeTab({required this.profileStore, required this.onOpen});

  final LocalProfileStoreV2 profileStore;
  final ValueChanged<_HomeSection> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FutureBuilder<LocalProfileV2>(
          future: profileStore.load(),
          builder: (context, snapshot) {
            final profile = snapshot.data;
            return Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage: profile?.avatarBytes == null
                      ? null
                      : MemoryImage(profile!.avatarBytes!),
                  child: profile?.avatarBytes == null
                      ? const Icon(Icons.person_outline, size: 30)
                      : null,
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    profile?.nickname ?? '日记主人',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        _MeItem(
          icon: Icons.insights_outlined,
          title: '统计分析',
          onTap: () => onOpen(_HomeSection.analysis),
        ),
        _MeItem(
          icon: Icons.favorite_border,
          title: '收藏',
          onTap: () => onOpen(_HomeSection.favorites),
        ),
        _MeItem(
          icon: Icons.import_export,
          title: '导出与备份',
          onTap: () => onOpen(_HomeSection.dataTools),
        ),
        _MeItem(
          icon: Icons.delete_outline,
          title: '回收站',
          onTap: () => onOpen(_HomeSection.recycleBin),
        ),
        _MeItem(
          icon: Icons.settings_outlined,
          title: '设置',
          onTap: () => onOpen(_HomeSection.settings),
        ),
      ],
    );
  }
}

class _MeItem extends StatelessWidget {
  const _MeItem({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _LifeGuideEntryCard extends StatelessWidget {
  const _LifeGuideEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _MemoryFeatureButton(
      icon: Icons.auto_stories_rounded,
      label: '我的人生指南',
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
      onTap: onTap,
    );
  }
}

class _MemoryShortcut extends StatelessWidget {
  const _MemoryShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [Icon(icon), const SizedBox(width: 10), Text(label)],
          ),
        ),
      ),
    );
  }
}

class _MemoryFeatureButton extends StatelessWidget {
  const _MemoryFeatureButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 22, color: foregroundColor),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Kept temporarily while the user compares the restored and minimal concepts.
// ignore: unused_element
class _HomeTimeline extends StatelessWidget {
  const _HomeTimeline({
    required this.entries,
    required this.imageStore,
    required this.festivalRepository,
    required this.publicFestivals,
    required this.onEntryTap,
    required this.onAiTap,
    required this.onFestivalTap,
  });

  final List<DiaryEntryV2> entries;
  final DiaryImageStoreV2 imageStore;
  final FestivalRepositoryV2 festivalRepository;
  final Future<List<FestivalOccurrenceV2>> publicFestivals;
  final ValueChanged<DiaryEntryV2> onEntryTap;
  final VoidCallback onAiTap;
  final VoidCallback onFestivalTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final memories = entries
        .where((entry) {
          final date = entry.entryDate.toLocal();
          return date.month == today.month &&
              date.day == today.day &&
              date.year != today.year;
        })
        .toList(growable: false);
    final withImages = entries
        .where((entry) => entry.imageIds.isNotEmpty)
        .take(10)
        .toList(growable: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 112),
      children: [
        const _TodayHeader(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _AiRecapCard(onTap: onAiTap),
        ),
        const SizedBox(height: 20),
        _FestivalStrip(
          repository: festivalRepository,
          publicFestivals: publicFestivals,
          onTap: onFestivalTap,
        ),
        if (memories.isNotEmpty) ...[
          const _SectionTitle(title: '那年今日', icon: Icons.history_rounded),
          ...memories.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: _MemoryCard(
                entry: entry,
                imageStore: imageStore,
                onTap: () => onEntryTap(entry),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (withImages.isNotEmpty) ...[
          const _SectionTitle(
            title: '近期精彩瞬间',
            icon: Icons.photo_library_outlined,
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: withImages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = withImages[index];
                return SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.82,
                  child: _PhotoMemoryCard(
                    entry: entry,
                    imageStore: imageStore,
                    onTap: () => onEntryTap(entry),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (entries.isEmpty)
          const _EmptyState()
        else
          for (var index = 0; index < entries.length; index++) ...[
            if (index == 0 ||
                !_sameMonth(
                  entries[index - 1].entryDate,
                  entries[index].entryDate,
                ))
              _MonthSeparator(date: entries[index].entryDate),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: _DiaryGradientCard(
                entry: entries[index],
                imageStore: imageStore,
                gradientIndex: index,
                onTap: () => onEntryTap(entries[index]),
              ),
            ),
          ],
      ],
    );
  }

  static bool _sameMonth(DateTime first, DateTime second) {
    final a = first.toLocal();
    final b = second.toLocal();
    return a.year == b.year && a.month == b.month;
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader();

  static const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  static const _sentences = [
    '把今天轻轻收好，日子会在文字里发光。',
    '不必写得完美，真实就是最好的记录。',
    '生活的细小波纹，也值得被认真记住。',
    '愿你在回望时，仍能认出此刻的自己。',
    '今天也有一些温柔，藏在普通时刻里。',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sentence = _sentences[now.day % _sentences.length];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: dark
                    ? const [Color(0xFF3A3A3A), Color(0xFF252525)]
                    : const [Color(0xFFC49BEF), Color(0xFFF4B8C5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${now.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 18),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _weekdays[now.weekday - 1],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${now.year} / ${now.month.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Text(
            sentence,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FestivalStrip extends StatelessWidget {
  const _FestivalStrip({
    required this.repository,
    required this.publicFestivals,
    required this.onTap,
  });

  final FestivalRepositoryV2 repository;
  final Future<List<FestivalOccurrenceV2>> publicFestivals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CustomFestivalV2>>(
      stream: repository.watchCustomFestivals(),
      builder: (context, customSnapshot) {
        return FutureBuilder<List<FestivalOccurrenceV2>>(
          future: publicFestivals,
          builder: (context, publicSnapshot) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final festivals = [
              ...(publicSnapshot.data ?? const <FestivalOccurrenceV2>[]).where(
                (value) => !value.date.isBefore(today),
              ),
              ...(customSnapshot.data ?? const <CustomFestivalV2>[]).map(
                (value) => FestivalOccurrenceV2(
                  id: value.id,
                  name: value.name,
                  date: value.nextOccurrence(now),
                  isCustom: true,
                ),
              ),
            ]..sort((a, b) => a.date.compareTo(b.date));
            if (festivals.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                const _SectionTitle(
                  title: '节日与纪念日',
                  icon: Icons.celebration_outlined,
                ),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: festivals.take(6).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final festival = festivals[index];
                      return _FestivalGradientCard(
                        occurrence: festival,
                        index: index,
                        onTap: onTap,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
            );
          },
        );
      },
    );
  }
}

class _FestivalGradientCard extends StatelessWidget {
  const _FestivalGradientCard({
    required this.occurrence,
    required this.index,
    required this.onTap,
  });

  final FestivalOccurrenceV2 occurrence;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _homeGradients(
      context,
    )[index % _homeGradients(context).length];
    final days = occurrence.daysUntil(DateTime.now());
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 245,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    occurrence.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${occurrence.date.month}月${occurrence.date.day}日',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              days == 0 ? '今天' : '$days\n天后',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaryGradientCard extends StatelessWidget {
  const _DiaryGradientCard({
    required this.entry,
    required this.imageStore,
    required this.gradientIndex,
    required this.onTap,
  });

  final DiaryEntryV2 entry;
  final DiaryImageStoreV2 imageStore;
  final int gradientIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = entry.entryDate.toLocal();
    final gradients = _homeGradients(context);
    final colors = gradients[gradientIndex % gradients.length];
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          height: 128,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 86,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 31,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${date.month}月',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    Text(
                      _TodayHeader._weekdays[date.weekday - 1],
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(
                width: 1,
                indent: 18,
                endIndent: 18,
                color: Colors.white30,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.mood != null)
                        Text(entry.mood!, style: const TextStyle(fontSize: 18)),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.body,
                            maxLines: entry.mood == null ? 4 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.96),
                              fontSize: 15,
                              height: 1.42,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (entry.imageIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(9),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: _StoredThumbnail(
                      imageStore: imageStore,
                      imageId: entry.imageIds.first,
                      width: 92,
                      height: 110,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoMemoryCard extends StatelessWidget {
  const _PhotoMemoryCard({
    required this.entry,
    required this.imageStore,
    required this.onTap,
  });

  final DiaryEntryV2 entry;
  final DiaryImageStoreV2 imageStore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = entry.entryDate.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _StoredThumbnail(
                imageStore: imageStore,
                imageId: entry.imageIds.first,
                width: double.infinity,
                height: 210,
                fit: BoxFit.contain,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xD0000000), Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0, 0.72],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 15,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                      '${date.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.entry,
    required this.imageStore,
    required this.onTap,
  });

  final DiaryEntryV2 entry;
  final DiaryImageStoreV2 imageStore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = entry.entryDate.toLocal();
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${date.year}\n${date.month}月${date.day}日',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        title: Text(entry.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: entry.imageIds.isEmpty
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _StoredThumbnail(
                  imageStore: imageStore,
                  imageId: entry.imageIds.first,
                  width: 52,
                  height: 52,
                ),
              ),
      ),
    );
  }
}

class _StoredThumbnail extends StatelessWidget {
  const _StoredThumbnail({
    required this.imageStore,
    required this.imageId,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  final DiaryImageStoreV2 imageStore;
  final String imageId;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: imageStore.read(imageId),
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return SizedBox(
            width: width,
            height: height,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.photo_outlined),
            ),
          );
        }
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}

class _AiRecapCard extends StatelessWidget {
  const _AiRecapCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _MemoryFeatureButton(
      icon: Icons.auto_awesome_rounded,
      label: 'AI 时光回顾',
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      onTap: onTap,
    );
  }
}

class _MonthSeparator extends StatelessWidget {
  const _MonthSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final local = date.toLocal();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 7),
      child: Text(
        '${local.year}年 ${local.month}月',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.expanded,
    required this.onToggle,
    required this.onWrite,
    required this.onCalendar,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onWrite;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: expanded
              ? Column(
                  key: const ValueKey('open'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _QuickActionButton(
                      label: '看日历',
                      icon: Icons.calendar_month,
                      onTap: onCalendar,
                    ),
                    const SizedBox(height: 10),
                    _QuickActionButton(
                      label: '写日记',
                      icon: Icons.edit_outlined,
                      onTap: onWrite,
                    ),
                    const SizedBox(height: 12),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey('closed')),
        ),
        FloatingActionButton(
          tooltip: '快速操作',
          onPressed: onToggle,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 180),
            turns: expanded ? 0.125 : 0,
            child: Icon(expanded ? Icons.close : Icons.menu),
          ),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer({required this.profileStore, required this.onSelected});

  final LocalProfileStoreV2 profileStore;
  final ValueChanged<_HomeSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          FutureBuilder<LocalProfileV2>(
            future: profileStore.load(),
            builder: (context, snapshot) {
              final profile = snapshot.data;
              return DrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFC49BEF), Color(0xFFF4B8C5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 29,
                        backgroundImage: profile?.avatarBytes == null
                            ? null
                            : MemoryImage(profile!.avatarBytes!),
                        child: profile?.avatarBytes == null
                            ? const Icon(Icons.person_outline)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          profile?.nickname ?? '我的日记',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.favorite_border,
            label: '收藏',
            section: _HomeSection.favorites,
            onSelected: onSelected,
          ),
          _DrawerItem(
            icon: Icons.place_outlined,
            label: '地点回忆',
            section: _HomeSection.locations,
            onSelected: onSelected,
          ),
          _DrawerItem(
            icon: Icons.celebration_outlined,
            label: '节日与纪念日',
            section: _HomeSection.festivals,
            onSelected: onSelected,
          ),
          _DrawerItem(
            icon: Icons.insights_outlined,
            label: '统计分析',
            section: _HomeSection.analysis,
            onSelected: onSelected,
          ),
          const Divider(),
          _DrawerItem(
            icon: Icons.import_export,
            label: '导出与备份',
            section: _HomeSection.dataTools,
            onSelected: onSelected,
          ),
          _DrawerItem(
            icon: Icons.delete_outline,
            label: '回收站',
            section: _HomeSection.recycleBin,
            onSelected: onSelected,
          ),
          _DrawerItem(
            icon: Icons.settings_outlined,
            label: '设置',
            section: _HomeSection.settings,
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.section,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final _HomeSection section;
  final ValueChanged<_HomeSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        onSelected(section);
      },
    );
  }
}

enum _HomeSection {
  favorites,
  locations,
  festivals,
  analysis,
  dataTools,
  settings,
  recycleBin,
}

List<List<Color>> _homeGradients(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return const [
      [Color(0xFF0D47A1), Color(0xFF4527A0)],
      [Color(0xFF004D40), Color(0xFF00796B)],
      [Color(0xFF37474F), Color(0xFF546E7A)],
      [Color(0xFF880E4F), Color(0xFFC2185B)],
      [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    ];
  }
  return const [
    [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
    [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
    [Color(0xFF84FAB0), Color(0xFF8FD3F4)],
    [Color(0xFFFCCB90), Color(0xFFD57EEB)],
    [Color(0xFFA6C0FE), Color(0xFFF68084)],
    [Color(0xFFF6D365), Color(0xFFFDA085)],
  ];
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 58),
      child: Column(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 16),
          Text('还没有日记', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('展开右下角菜单，写下第一篇吧'),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('读取日记失败\n$message', textAlign: TextAlign.center),
      ),
    );
  }
}
