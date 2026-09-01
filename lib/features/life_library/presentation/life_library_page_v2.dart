import 'package:flutter/material.dart';

import '../domain/life_document_repository_v2.dart';
import '../domain/life_document_v2.dart';
import 'life_document_detail_page_v2.dart';
import 'life_document_editor_page_v2.dart';

class LifeLibraryPageV2 extends StatefulWidget {
  const LifeLibraryPageV2({required this.repository, super.key});

  final LifeDocumentRepositoryV2 repository;

  @override
  State<LifeLibraryPageV2> createState() => _LifeLibraryPageV2State();
}

class _LifeLibraryPageV2State extends State<LifeLibraryPageV2> {
  String? _selectedSpace;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LifeDocumentV2>>(
      stream: widget.repository.watchDocuments(space: _selectedSpace),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('读取生活库失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final documents = snapshot.data!;
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
              children: [
                Text(
                  '把计划放进生活里',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '菜谱、清单和每天真正做过的事，都可以从一篇 Markdown 开始。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Row(
                  children: LifeSpacesV2.values
                      .map(
                        (space) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: space == LifeSpacesV2.values.first ? 7 : 0,
                              left: space == LifeSpacesV2.values.last ? 7 : 0,
                            ),
                            child: _SpaceCard(
                              space: space,
                              count: _selectedSpace == null
                                  ? documents
                                        .where((item) => item.space == space)
                                        .length
                                  : (_selectedSpace == space
                                        ? documents.length
                                        : 0),
                              selected: _selectedSpace == space,
                              onTap: () => setState(
                                () => _selectedSpace = _selectedSpace == space
                                    ? null
                                    : space,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedSpace == null
                            ? '最近文档'
                            : LifeSpacesV2.label(_selectedSpace!),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_selectedSpace != null)
                      TextButton(
                        onPressed: () => setState(() => _selectedSpace = null),
                        child: const Text('查看全部'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (documents.isEmpty)
                  const _EmptyLibrary()
                else
                  for (final document in documents)
                    _DocumentCard(
                      document: document,
                      onTap: () => _open(document),
                    ),
              ],
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: FloatingActionButton.extended(
                heroTag: 'new-life-document',
                onPressed: _showCreateSheet,
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateSheet() async {
    final choice = await showModalBottomSheet<_DocumentPresetV2>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('从哪里开始？', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final preset in _DocumentPresetV2.values)
                ListTile(
                  leading: Icon(preset.icon),
                  title: Text(preset.title),
                  subtitle: Text(preset.subtitle),
                  onTap: () => Navigator.pop(context, preset),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LifeDocumentEditorPageV2(
          repository: widget.repository,
          initialSpace: choice.space,
          initialType: choice.type,
          initialMarkdown: choice.markdown,
        ),
      ),
    );
  }

  Future<void> _open(LifeDocumentV2 document) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LifeDocumentDetailPageV2(
        document: document,
        repository: widget.repository,
      ),
    ),
  );
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.space,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String space;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cooking = space == LifeSpacesV2.cooking;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                cooking ? Icons.soup_kitchen_outlined : Icons.route_outlined,
              ),
              const SizedBox(height: 22),
              Text(
                LifeSpacesV2.label(space),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text('$count 篇文档'),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.onTap});

  final LifeDocumentV2 document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      leading: Icon(_icon(document.type)),
      title: Row(
        children: [
          if (document.isPinned) ...[
            const Icon(Icons.push_pin_rounded, size: 15),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text(
              document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          document.checklistTotal == 0
              ? '${LifeSpacesV2.label(document.space)} · ${document.type.label}'
              : '${document.type.label} · ${document.checklistCompleted}/${document.checklistTotal} 已完成',
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );

  IconData _icon(LifeDocumentTypeV2 type) => switch (type) {
    LifeDocumentTypeV2.recipe => Icons.restaurant_menu_rounded,
    LifeDocumentTypeV2.checklist => Icons.checklist_rounded,
    LifeDocumentTypeV2.plan => Icons.event_note_rounded,
    LifeDocumentTypeV2.template => Icons.copy_all_outlined,
    LifeDocumentTypeV2.dailyLog => Icons.today_outlined,
    LifeDocumentTypeV2.note => Icons.description_outlined,
  };
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(
          Icons.library_books_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text('生活库还是空的', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        const Text('可以先粘贴一份 GPT 生成的采购清单'),
      ],
    ),
  );
}

enum _DocumentPresetV2 { blank, recipe, shopping, workout }

extension on _DocumentPresetV2 {
  String get title => switch (this) {
    _DocumentPresetV2.blank => '空白 Markdown',
    _DocumentPresetV2.recipe => '新菜谱',
    _DocumentPresetV2.shopping => '采购清单',
    _DocumentPresetV2.workout => '健身模板',
  };

  String get subtitle => switch (this) {
    _DocumentPresetV2.blank => '也可以直接从剪贴板粘贴',
    _DocumentPresetV2.recipe => '记录食材、步骤和下次调整',
    _DocumentPresetV2.shopping => '阅读时可以直接打钩',
    _DocumentPresetV2.workout => '之后可生成每天独立的训练记录',
  };

  String get space => switch (this) {
    _DocumentPresetV2.blank => LifeSpacesV2.cooking,
    _DocumentPresetV2.recipe => LifeSpacesV2.cooking,
    _DocumentPresetV2.shopping => LifeSpacesV2.cooking,
    _DocumentPresetV2.workout => LifeSpacesV2.habits,
  };

  LifeDocumentTypeV2 get type => switch (this) {
    _DocumentPresetV2.blank => LifeDocumentTypeV2.note,
    _DocumentPresetV2.recipe => LifeDocumentTypeV2.recipe,
    _DocumentPresetV2.shopping => LifeDocumentTypeV2.checklist,
    _DocumentPresetV2.workout => LifeDocumentTypeV2.template,
  };

  IconData get icon => switch (this) {
    _DocumentPresetV2.blank => Icons.note_add_outlined,
    _DocumentPresetV2.recipe => Icons.restaurant_menu_rounded,
    _DocumentPresetV2.shopping => Icons.shopping_cart_outlined,
    _DocumentPresetV2.workout => Icons.fitness_center_rounded,
  };

  String get markdown => switch (this) {
    _DocumentPresetV2.blank => '',
    _DocumentPresetV2.recipe =>
      '''# 菜名

## 食材

- 食材名称和用量

## 步骤

1. 第一步

## 下次调整

''',
    _DocumentPresetV2.shopping =>
      '''# 采购清单

## 蔬菜

- [ ] 待购买物品

## 其他

- [ ] 待购买物品
''',
    _DocumentPresetV2.workout =>
      '''# 健身计划

- [ ] 热身 10 分钟
- [ ] 动作一 4 × 8
- [ ] 动作二 4 × 10

## 今日感受

''',
  };
}
