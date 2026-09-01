import 'package:flutter/material.dart';

import '../../diary/application/ports/diary_image_store_v2.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../domain/life_fragment_repository_v2.dart';
import '../domain/life_fragment_v2.dart';
import 'life_fragment_detail_page_v2.dart';

enum _GuideViewV2 { confirmed, reminders, drafts }

class LifeGuidePageV2 extends StatefulWidget {
  const LifeGuidePageV2({
    required this.repository,
    this.diaryRepository,
    this.imageStore,
    super.key,
  });

  final LifeFragmentRepositoryV2 repository;
  final DiaryRepositoryV2? diaryRepository;
  final DiaryImageStoreV2? imageStore;

  @override
  State<LifeGuidePageV2> createState() => _LifeGuidePageV2State();
}

class _LifeGuidePageV2State extends State<LifeGuidePageV2> {
  _GuideViewV2 _view = _GuideViewV2.confirmed;
  String? _theme;

  @override
  Widget build(BuildContext context) {
    final status = _view == _GuideViewV2.drafts
        ? LifeFragmentStatusV2.draft
        : LifeFragmentStatusV2.confirmed;
    return Scaffold(
      appBar: AppBar(title: const Text('人生指南')),
      body: StreamBuilder<List<LifeFragmentV2>>(
        stream: widget.repository.watchFragments(
          status: status,
          onlyRopes: _view == _GuideViewV2.reminders,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('读取人生指南失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final fragments = snapshot.data!
              .where((fragment) => _theme == null || fragment.theme == _theme)
              .toList(growable: false);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context, snapshot.data!)),
              if (fragments.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyGuide(view: _view),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
                  sliver: SliverList.separated(
                    itemCount: fragments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _FragmentCard(
                      fragment: fragments[index],
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => LifeFragmentDetailPageV2(
                            fragmentId: fragments[index].id,
                            repository: widget.repository,
                            diaryRepository: widget.diaryRepository,
                            imageStore: widget.imageStore,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<LifeFragmentV2> values) {
    final confirmed = values
        .where((item) => item.status == LifeFragmentStatusV2.confirmed)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '把经历慢慢读成自己',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('已经确认 $confirmed 片。这里只收录你愿意相信和保留的认识。'),
          const SizedBox(height: 18),
          SegmentedButton<_GuideViewV2>(
            segments: const [
              ButtonSegment(value: _GuideViewV2.confirmed, label: Text('指南')),
              ButtonSegment(value: _GuideViewV2.reminders, label: Text('重要提醒')),
              ButtonSegment(value: _GuideViewV2.drafts, label: Text('草稿')),
            ],
            selected: {_view},
            onSelectionChanged: (value) => setState(() {
              _view = value.single;
              _theme = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _theme,
            decoration: const InputDecoration(
              labelText: '主题',
              prefixIcon: Icon(Icons.filter_alt_outlined),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('全部主题')),
              ...values
                  .map((fragment) => fragment.theme.trim())
                  .where((theme) => theme.isNotEmpty)
                  .toSet()
                  .map(
                    (theme) =>
                        DropdownMenuItem(value: theme, child: Text(theme)),
                  ),
            ],
            onChanged: (value) => setState(() => _theme = value),
          ),
        ],
      ),
    );
  }
}

class _FragmentCard extends StatelessWidget {
  const _FragmentCard({required this.fragment, required this.onTap});

  final LifeFragmentV2 fragment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (fragment.isRope) ...[
                    Icon(
                      Icons.bookmark_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      fragment.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                fragment.coreInsight,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  if (fragment.theme.isNotEmpty) _SmallLabel(fragment.theme),
                  ...fragment.tags.take(3).map(_SmallLabel.new),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    ),
  );
}

class _EmptyGuide extends StatelessWidget {
  const _EmptyGuide({required this.view});
  final _GuideViewV2 view;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (view) {
      _GuideViewV2.confirmed => (
        Icons.auto_stories_outlined,
        '指南还在等待第一片内容',
        '在一篇日记详情中，选择“提炼为人生碎片”。',
      ),
      _GuideViewV2.reminders => (
        Icons.bookmark_outline_rounded,
        '还没有重要提醒',
        '你可以把以后想更快找到的内容标记在这里。',
      ),
      _GuideViewV2.drafts => (
        Icons.edit_note_rounded,
        '没有待确认的草稿',
        '草稿不会自动成为对你的定义。',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
