import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../domain/life_document_repository_v2.dart';
import '../domain/life_document_v2.dart';
import '../domain/life_space_v2.dart';
import 'life_document_detail_page_v2.dart';
import 'life_document_editor_page_v2.dart';

class LifeLibraryPageV2 extends StatefulWidget {
  const LifeLibraryPageV2({required this.repository, super.key});
  final LifeDocumentRepositoryV2 repository;

  @override
  State<LifeLibraryPageV2> createState() => _LifeLibraryPageV2State();
}

class _LifeLibraryPageV2State extends State<LifeLibraryPageV2> {
  _LibraryView _view = _LibraryView.recent;
  String? _selectedSpaceId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LifeSpaceV2>>(
      stream: widget.repository.watchSpaces(),
      builder: (context, spacesSnapshot) {
        if (spacesSnapshot.hasError) {
          return _ErrorState(message: spacesSnapshot.error.toString());
        }
        if (!spacesSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final spaces = spacesSnapshot.data!;
        return StreamBuilder<List<LifeDocumentV2>>(
          stream: widget.repository.watchDocuments(),
          builder: (context, documentsSnapshot) {
            if (documentsSnapshot.hasError) {
              return _ErrorState(message: documentsSnapshot.error.toString());
            }
            if (!documentsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final documents = documentsSnapshot.data!;
            final visible = _visibleDocuments(documents);
            final spaceNames = {
              for (final space in spaces) space.id: space.name,
            };
            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 116),
                  children: [
                    _buildHeading(context),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        hintText: '搜索标题、标签和正文',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    if (_selectedSpaceId == null) ...[
                      const SizedBox(height: 16),
                      _QuickViews(
                        selected: _view,
                        todayCount: documents.where(_isToday).length,
                        inboxCount: documents
                            .where(
                              (item) =>
                                  item.space == LifeSpaceDefaultsV2.inboxId,
                            )
                            .length,
                        pinnedCount: documents
                            .where((item) => item.isPinned)
                            .length,
                        templateCount: documents
                            .where(
                              (item) =>
                                  item.type == LifeDocumentTypeV2.template,
                            )
                            .length,
                        onSelected: (view) => setState(() => _view = view),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '我的空间',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _editSpace(spaces: spaces),
                            icon: const Icon(Icons.add_rounded, size: 19),
                            label: const Text('新建空间'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _SpaceGrid(
                        spaces: spaces
                            .where(
                              (space) =>
                                  space.id != LifeSpaceDefaultsV2.inboxId,
                            )
                            .toList(growable: false),
                        documents: documents,
                        selectedId: _selectedSpaceId,
                        onTap: (space) => setState(() {
                          _selectedSpaceId = space.id;
                        }),
                        onLongPress: (space) =>
                            _showSpaceActions(space, spaces),
                        onAdd: () => _editSpace(spaces: spaces),
                      ),
                      const SizedBox(height: 28),
                    ] else
                      const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sectionTitle(spaces),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          '${visible.length} 篇',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (visible.isEmpty)
                      _EmptyLibrary(
                        hasSpaces: spaces.length > 1,
                        onCreateSpace: () => _editSpace(spaces: spaces),
                      )
                    else
                      for (final document in visible)
                        _DocumentCard(
                          document: document,
                          spaceName:
                              spaceNames[document.space] ?? document.space,
                          onTap: () => _open(document),
                        ),
                  ],
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: FloatingActionButton.extended(
                    heroTag: 'new-life-document',
                    onPressed: () => _showCreateSheet(spaces),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新建'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHeading(BuildContext context) {
    if (_selectedSpaceId != null) {
      return Row(
        children: [
          IconButton.filledTonal(
            tooltip: '返回生活桌面',
            onPressed: () => setState(() => _selectedSpaceId = null),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('空间中的一切，都由你来定义。')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '我的生活工作台',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '收下灵感，整理成属于自己的页面、清单和长期计划。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  List<LifeDocumentV2> _visibleDocuments(List<LifeDocumentV2> documents) {
    if (_query.isNotEmpty) {
      return documents
          .where((document) {
            final searchable = [
              document.title,
              document.markdown,
              ...document.tags,
            ].join('\n').toLowerCase();
            return searchable.contains(_query);
          })
          .toList(growable: false);
    }
    final selectedSpaceId = _selectedSpaceId;
    late final Iterable<LifeDocumentV2> candidates;
    if (selectedSpaceId != null) {
      candidates = documents.where(
        (document) => document.space == selectedSpaceId,
      );
    } else {
      candidates = switch (_view) {
        _LibraryView.today => documents.where(_isToday),
        _LibraryView.inbox => documents.where(
          (item) => item.space == LifeSpaceDefaultsV2.inboxId,
        ),
        _LibraryView.pinned => documents.where((item) => item.isPinned),
        _LibraryView.templates => documents.where(
          (item) => item.type == LifeDocumentTypeV2.template,
        ),
        _LibraryView.recent => documents.take(12),
      };
    }
    return candidates.toList(growable: false);
  }

  bool _isToday(LifeDocumentV2 document) {
    final date = document.documentDate?.toLocal();
    final now = DateTime.now();
    return date != null &&
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  String _sectionTitle(List<LifeSpaceV2> spaces) {
    if (_query.isNotEmpty) return '搜索结果';
    final selectedSpaceId = _selectedSpaceId;
    if (selectedSpaceId != null) {
      for (final space in spaces) {
        if (space.id == selectedSpaceId) return space.name;
      }
      return '空间';
    }
    return _view.title;
  }

  Future<void> _showCreateSheet(List<LifeSpaceV2> spaces) async {
    final choice = await showModalBottomSheet<_CreateChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('创建新内容', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('先记录下来，之后随时可以移动到其他空间。'),
              const SizedBox(height: 12),
              for (final choice in _CreateChoice.values)
                ListTile(
                  leading: Icon(choice.icon),
                  title: Text(choice.title),
                  subtitle: Text(choice.subtitle),
                  onTap: () => Navigator.pop(context, choice),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    var markdown = choice.markdown;
    if (choice == _CreateChoice.paste) {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      markdown = clipboard?.text?.trim() ?? '';
      if (markdown.isEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('剪贴板中没有可以导入的文字')));
        return;
      }
    }
    if (!mounted) return;

    final targetSpace = _selectedSpaceId ?? LifeSpaceDefaultsV2.inboxId;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LifeDocumentEditorPageV2(
          repository: widget.repository,
          initialSpace: targetSpace,
          initialType: choice.typeFor(markdown),
          initialMarkdown: markdown,
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

  Future<void> _editSpace({
    required List<LifeSpaceV2> spaces,
    LifeSpaceV2? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var iconCodePoint = existing?.iconCodePoint ?? _spaceIcons.first.codePoint;
    var colorValue = existing?.colorValue ?? _spaceColors.first;
    final result = await showDialog<LifeSpaceV2>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '创建生活空间' : '编辑空间'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '空间名称',
                    hintText: '例如：旅行、阅读、家庭事务',
                  ),
                ),
                const SizedBox(height: 14),
                Text('图标', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final icon in _spaceIcons)
                      IconButton.filledTonal(
                        isSelected: icon.codePoint == iconCodePoint,
                        onPressed: () => setDialogState(
                          () => iconCodePoint = icon.codePoint,
                        ),
                        icon: Icon(icon),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('颜色', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final value in _spaceColors)
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setDialogState(() => colorValue = value),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(value),
                          child: value == colorValue
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final now = DateTime.now().toUtc();
                Navigator.pop(
                  context,
                  existing == null
                      ? LifeSpaceV2(
                          id: const Uuid().v4(),
                          name: name,
                          iconCodePoint: iconCodePoint,
                          colorValue: colorValue,
                          sortOrder: spaces.length,
                          createdAt: now,
                          updatedAt: now,
                        )
                      : existing.copyWith(
                          name: name,
                          iconCodePoint: iconCodePoint,
                          colorValue: colorValue,
                          updatedAt: now,
                        ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null) return;
    await widget.repository.saveSpace(result);
    if (mounted) setState(() => _selectedSpaceId = result.id);
  }

  Future<void> _showSpaceActions(
    LifeSpaceV2 space,
    List<LifeSpaceV2> spaces,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑空间'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('删除空间'),
              subtitle: const Text('空间内的页面会移入收件箱'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      await _editSpace(spaces: spaces, existing: space);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('删除“${space.name}”？'),
          content: const Text('页面不会被删除，而是统一移动到收件箱。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除空间'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.repository.deleteSpace(space.id);
        if (mounted) setState(() => _selectedSpaceId = null);
      }
    }
  }
}

class _QuickViews extends StatelessWidget {
  const _QuickViews({
    required this.selected,
    required this.todayCount,
    required this.inboxCount,
    required this.pinnedCount,
    required this.templateCount,
    required this.onSelected,
  });

  final _LibraryView? selected;
  final int todayCount;
  final int inboxCount;
  final int pinnedCount;
  final int templateCount;
  final ValueChanged<_LibraryView> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = [
      (_LibraryView.today, Icons.today_outlined, todayCount),
      (_LibraryView.inbox, Icons.inbox_outlined, inboxCount),
      (_LibraryView.pinned, Icons.push_pin_outlined, pinnedCount),
      (_LibraryView.templates, Icons.copy_all_outlined, templateCount),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final columns = constraints.maxWidth < 560 ? 2 : 4;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _QuickViewCard(
                  view: item.$1,
                  icon: item.$2,
                  count: item.$3,
                  selected: selected == item.$1,
                  onTap: () => onSelected(item.$1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickViewCard extends StatelessWidget {
  const _QuickViewCard({
    required this.view,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final _LibraryView view;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Column(
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 6),
              Text(
                view.title,
                maxLines: 1,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '$count',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colors.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LibraryView { recent, today, inbox, pinned, templates }

extension on _LibraryView {
  String get title => switch (this) {
    _LibraryView.recent => '最近使用',
    _LibraryView.today => '今天',
    _LibraryView.inbox => '收件箱',
    _LibraryView.pinned => '置顶内容',
    _LibraryView.templates => '我的模板',
  };
}

class _SpaceGrid extends StatelessWidget {
  const _SpaceGrid({
    required this.spaces,
    required this.documents,
    required this.selectedId,
    required this.onTap,
    required this.onLongPress,
    required this.onAdd,
  });
  final List<LifeSpaceV2> spaces;
  final List<LifeDocumentV2> documents;
  final String? selectedId;
  final ValueChanged<LifeSpaceV2> onTap;
  final ValueChanged<LifeSpaceV2> onLongPress;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (spaces.isEmpty) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAdd,
          child: const Padding(
            padding: EdgeInsets.all(22),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline_rounded),
                SizedBox(width: 12),
                Expanded(child: Text('创建第一个空间，让内容逐渐长成自己的系统')),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final space in spaces)
              SizedBox(
                width: width,
                child: _SpaceCard(
                  space: space,
                  count: documents
                      .where((item) => item.space == space.id)
                      .length,
                  selected: selectedId == space.id,
                  onTap: () => onTap(space),
                  onLongPress: () => onLongPress(space),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.space,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final LifeSpaceV2 space;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = Color(space.colorValue);
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.20)
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accent.withValues(alpha: 0.18),
                foregroundColor: accent,
                child: Icon(_spaceIcon(space.iconCodePoint), size: 20),
              ),
              const SizedBox(height: 18),
              Text(
                space.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text('$count 篇 · 长按管理'),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.spaceName,
    required this.onTap,
  });
  final LifeDocumentV2 document;
  final String spaceName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      leading: Icon(_documentIcon(document.type)),
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
              ? '$spaceName · ${document.type.label}'
              : '$spaceName · ${document.checklistCompleted}/${document.checklistTotal} 已完成',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

IconData _documentIcon(LifeDocumentTypeV2 type) => switch (type) {
  LifeDocumentTypeV2.recipe => Icons.description_outlined,
  LifeDocumentTypeV2.checklist => Icons.checklist_rounded,
  LifeDocumentTypeV2.plan => Icons.event_note_rounded,
  LifeDocumentTypeV2.template => Icons.copy_all_outlined,
  LifeDocumentTypeV2.dailyLog => Icons.today_outlined,
  LifeDocumentTypeV2.note => Icons.description_outlined,
};

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.hasSpaces, required this.onCreateSpace});
  final bool hasSpaces;
  final VoidCallback onCreateSpace;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 38),
    child: Column(
      children: [
        Icon(
          Icons.auto_stories_outlined,
          size: 46,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text('这里还是空的', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(hasSpaces ? '新建页面，或者从剪贴板收下一段 Markdown' : '先创建一个属于你的生活空间'),
        if (!hasSpaces) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onCreateSpace,
            icon: const Icon(Icons.add_rounded),
            label: const Text('创建空间'),
          ),
        ],
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('读取生活工作台失败\n$message', textAlign: TextAlign.center),
    ),
  );
}

enum _CreateChoice { paste, blank, checklist, template }

extension on _CreateChoice {
  String get title => switch (this) {
    _CreateChoice.paste => '粘贴 Markdown',
    _CreateChoice.blank => '空白页面',
    _CreateChoice.checklist => '新建清单',
    _CreateChoice.template => '新建模板',
  };

  String get subtitle => switch (this) {
    _CreateChoice.paste => '收下来自 GPT、网页或聊天中的内容',
    _CreateChoice.blank => '自由记录任何想法和资料',
    _CreateChoice.checklist => '阅读时可以直接逐项勾选',
    _CreateChoice.template => '以后可以重复生成独立记录',
  };

  IconData get icon => switch (this) {
    _CreateChoice.paste => Icons.content_paste_rounded,
    _CreateChoice.blank => Icons.note_add_outlined,
    _CreateChoice.checklist => Icons.checklist_rounded,
    _CreateChoice.template => Icons.copy_all_outlined,
  };

  String get markdown => switch (this) {
    _CreateChoice.checklist => '# 新清单\n\n- [ ] 第一项\n- [ ] 第二项',
    _CreateChoice.template => '# 新模板\n\n- [ ] 待完成内容\n\n## 本次记录\n',
    _ => '',
  };

  LifeDocumentTypeV2 typeFor(String content) => switch (this) {
    _CreateChoice.checklist => LifeDocumentTypeV2.checklist,
    _CreateChoice.template => LifeDocumentTypeV2.template,
    _CreateChoice.paste
        when RegExp(
          r'^\s*[-*+]\s+\[[ xX]\]',
          multiLine: true,
        ).hasMatch(content) =>
      LifeDocumentTypeV2.checklist,
    _ => LifeDocumentTypeV2.note,
  };
}

const _spaceIcons = <IconData>[
  Icons.folder_outlined,
  Icons.auto_stories_outlined,
  Icons.explore_outlined,
  Icons.lightbulb_outline_rounded,
  Icons.favorite_border_rounded,
  Icons.home_outlined,
  Icons.school_outlined,
  Icons.work_outline_rounded,
];

const _spaceColors = <int>[
  0xff5c6bc0,
  0xff00897b,
  0xff7e57c2,
  0xffef6c00,
  0xffd81b60,
  0xff546e7a,
];

IconData _spaceIcon(int codePoint) {
  for (final icon in _spaceIcons) {
    if (icon.codePoint == codePoint) return icon;
  }
  return Icons.folder_outlined;
}
