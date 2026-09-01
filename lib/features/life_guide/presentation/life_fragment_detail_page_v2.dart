import 'package:flutter/material.dart';

import '../../diary/application/ports/diary_image_store_v2.dart';
import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../../diary/presentation/pages/diary_detail_page_v2.dart';
import '../domain/life_fragment_repository_v2.dart';
import '../domain/life_fragment_v2.dart';
import 'life_fragment_edit_page_v2.dart';
import 'life_fragment_history_page_v2.dart';

class LifeFragmentDetailPageV2 extends StatefulWidget {
  const LifeFragmentDetailPageV2({
    required this.fragmentId,
    required this.repository,
    this.diaryRepository,
    this.imageStore,
    super.key,
  });

  final String fragmentId;
  final LifeFragmentRepositoryV2 repository;
  final DiaryRepositoryV2? diaryRepository;
  final DiaryImageStoreV2? imageStore;

  @override
  State<LifeFragmentDetailPageV2> createState() =>
      _LifeFragmentDetailPageV2State();
}

class _LifeFragmentDetailPageV2State extends State<LifeFragmentDetailPageV2> {
  late Future<LifeFragmentV2?> _fragment;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _fragment = widget.repository.getById(widget.fragmentId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LifeFragmentV2?>(
      future: _fragment,
      builder: (context, snapshot) {
        final fragment = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('人生碎片'),
            actions: fragment == null
                ? null
                : [
                    IconButton(
                      tooltip: fragment.isRope ? '取消重要提醒' : '标记为重要提醒',
                      onPressed: () => _toggleRope(fragment),
                      icon: Icon(
                        fragment.isRope
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_outline_rounded,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(fragment);
                        if (value == 'history') _history(fragment);
                        if (value == 'delete') _delete(fragment);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'history', child: Text('修改历史')),
                        PopupMenuItem(value: 'delete', child: Text('删除碎片')),
                      ],
                    ),
                  ],
          ),
          body: snapshot.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : fragment == null
              ? const Center(child: Text('这片内容已经不存在'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        if (fragment.theme.isNotEmpty)
                          Chip(label: Text(fragment.theme)),
                        if (fragment.isRope)
                          const Chip(
                            avatar: Icon(Icons.bookmark_rounded, size: 17),
                            label: Text('重要提醒'),
                          ),
                        if (fragment.status == LifeFragmentStatusV2.draft)
                          const Chip(label: Text('待确认草稿')),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      fragment.title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 22),
                    _Section(title: '我留下的认识', body: fragment.coreInsight),
                    _Section(title: '它来自', body: fragment.context),
                    _Section(title: '我为什么相信它', body: fragment.evidence),
                    _Section(title: '未来何时重新读', body: fragment.futureUse),
                    _Section(
                      title: '写给未来的我',
                      body: fragment.messageToFutureSelf,
                      highlighted: true,
                    ),
                    if (fragment.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: fragment.tags
                            .map((tag) => Chip(label: Text(tag)))
                            .toList(growable: false),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      '来自 ${fragment.sourceDiaryIds.length} 篇日记 · '
                      '${_date(fragment.updatedAt)} 更新',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (widget.diaryRepository != null &&
                        widget.imageStore != null &&
                        fragment.sourceDiaryIds.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        '回到这些经历',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ...fragment.sourceDiaryIds.map(
                        (id) => _SourceDiaryTile(
                          diaryId: id,
                          repository: widget.diaryRepository!,
                          onOpen: (entry) => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => DiaryDetailPageV2(
                                repository: widget.diaryRepository!,
                                imageStore: widget.imageStore!,
                                entryId: entry.id,
                                lifeFragmentRepository: widget.repository,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (fragment.status == LifeFragmentStatusV2.draft) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _confirm(fragment),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('确认并收进人生指南'),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Future<void> _toggleRope(LifeFragmentV2 fragment) async {
    await widget.repository.save(
      fragment.copyWith(
        isRope: !fragment.isRope,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _edit(LifeFragmentV2 fragment) async {
    final result = await Navigator.of(context).push<LifeFragmentV2>(
      MaterialPageRoute(
        builder: (_) => LifeFragmentEditPageV2(
          fragment: fragment,
          repository: widget.repository,
        ),
      ),
    );
    if (result != null && mounted) setState(_reload);
  }

  Future<void> _history(LifeFragmentV2 fragment) async {
    final result = await Navigator.of(context).push<LifeFragmentV2>(
      MaterialPageRoute(
        builder: (_) => LifeFragmentHistoryPageV2(
          fragment: fragment,
          repository: widget.repository,
        ),
      ),
    );
    if (result != null && mounted) setState(_reload);
  }

  Future<void> _confirm(LifeFragmentV2 fragment) async {
    await widget.repository.save(
      fragment.copyWith(
        status: LifeFragmentStatusV2.confirmed,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _delete(LifeFragmentV2 fragment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这片人生碎片？'),
        content: const Text('来源日记不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.delete(fragment.id);
    if (mounted) Navigator.pop(context);
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}年${local.month}月${local.day}日';
  }
}

class _SourceDiaryTile extends StatelessWidget {
  const _SourceDiaryTile({
    required this.diaryId,
    required this.repository,
    required this.onOpen,
  });

  final String diaryId;
  final DiaryRepositoryV2 repository;
  final ValueChanged<DiaryEntryV2> onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DiaryEntryV2?>(
      future: repository.getById(diaryId),
      builder: (context, snapshot) {
        final entry = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('读取来源日记…'),
          );
        }
        if (entry == null || entry.isDeleted) {
          return const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link_off_rounded),
            title: Text('来源日记已不存在'),
          );
        }
        final preview = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
        final date = entry.entryDate.toLocal();
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.menu_book_outlined),
          title: Text('${date.year}年${date.month}月${date.day}日'),
          subtitle: Text(
            preview.isEmpty ? '无文字内容' : preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => onOpen(entry),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    this.highlighted = false,
  });

  final String title;
  final String body;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7),
          ),
        ],
      ),
    );
    if (!highlighted) return content;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: content,
      ),
    );
  }
}
