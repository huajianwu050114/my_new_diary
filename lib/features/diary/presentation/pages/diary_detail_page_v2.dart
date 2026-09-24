import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../ai/application/diary_ai_service_v2.dart';
import '../../../ai/application/automatic_diary_reply_coordinator_v2.dart';
import '../../../ai/data/ai_configuration_store_v2.dart';
import '../../../ai/data/ai_reply_task_store_v2.dart';
import '../../../ai/data/gemini_rest_client_v2.dart';
import '../../../ai/data/ai_response_feedback_store_v2.dart';
import '../../../ai/domain/ai_models_v2.dart';
import '../../../ai/domain/ai_response_feedback_v2.dart';
import '../../../ai/domain/ai_chat_session_v2.dart';
import '../../../ai/presentation/ai_settings_page_v2.dart';
import '../../../ai/presentation/ai_memory_suggestion_page_v2.dart';
import '../../../ai/presentation/diary_ai_chat_page_v2.dart';
import '../../../life_guide/domain/life_fragment_repository_v2.dart';
import '../../../life_guide/presentation/life_fragment_editor_page_v2.dart';
import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import 'diary_editor_page_v2.dart';

class DiaryDetailPageV2 extends StatefulWidget {
  const DiaryDetailPageV2({
    required this.repository,
    required this.imageStore,
    required this.entryId,
    this.lifeFragmentRepository,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final String entryId;
  final LifeFragmentRepositoryV2? lifeFragmentRepository;

  @override
  State<DiaryDetailPageV2> createState() => _DiaryDetailPageV2State();
}

class _DiaryDetailPageV2State extends State<DiaryDetailPageV2> {
  late Future<DiaryEntryV2?> _entry;
  late final DiaryAiServiceV2 _aiService;
  late final AutomaticDiaryReplyCoordinatorV2 _automaticReply;
  final _feedbackStore = AiResponseFeedbackStoreV2();
  bool _summarizing = false;
  int _currentImagePage = 0;

  @override
  void initState() {
    super.initState();
    final configurationStore = AiConfigurationStoreV2();
    _aiService = DiaryAiServiceV2(
      GeminiRestClientV2(configurationStore: configurationStore),
    );
    _automaticReply = AutomaticDiaryReplyCoordinatorV2(
      repository: widget.repository,
      taskStore: SharedPreferencesAiReplyTaskStoreV2(),
      loadConfiguration: configurationStore.load,
      generateReply: (entry) async =>
          (await _aiService.writeFriendReply(entry)).text,
    );
    _reload();
  }

  void _reload() {
    _entry = widget.repository.getById(widget.entryId);
    unawaited(_refreshAfterAutomaticReply());
  }

  Future<void> _refreshAfterAutomaticReply() async {
    await _automaticReply.retryIfNeeded(widget.entryId);
    final refreshed = widget.repository.getById(widget.entryId);
    if (mounted) {
      setState(() {
        _entry = refreshed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DiaryEntryV2?>(
      future: _entry,
      builder: (context, snapshot) {
        final entry = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('日记'),
            actions: entry == null
                ? null
                : [
                    IconButton(
                      tooltip: '与 AI 交流',
                      onPressed: () => _openChat(entry),
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
                    if (widget.lifeFragmentRepository != null)
                      IconButton(
                        tooltip: '提炼为人生碎片',
                        onPressed: () => _extractLifeFragment(entry),
                        icon: const Icon(Icons.psychology_alt_outlined),
                      ),
                    IconButton(
                      tooltip: entry.isFavorite ? '取消收藏' : '收藏',
                      onPressed: () => _toggleFavorite(entry),
                      icon: Icon(
                        entry.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      onPressed: () => _edit(entry),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    PopupMenuButton<_DetailAction>(
                      onSelected: (action) {
                        if (action == _DetailAction.memorySuggestions) {
                          _suggestMemories(entry);
                        }
                        if (action == _DetailAction.trash) {
                          _moveToTrash(entry);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _DetailAction.memorySuggestions,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.psychology_outlined),
                            title: Text('让AI提出记忆建议'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _DetailAction.trash,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline),
                            title: Text('移入回收站'),
                          ),
                        ),
                      ],
                    ),
                  ],
          ),
          body: _buildBody(snapshot),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<DiaryEntryV2?> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(child: Text('读取日记失败：${snapshot.error}'));
    }
    final entry = snapshot.data;
    if (entry == null) {
      return const Center(child: Text('这篇日记已经不存在了'));
    }

    final date = entry.entryDate.toLocal();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: [
        if (entry.imageIds.isNotEmpty) ...[
          _ImageViewer(
            imageStore: widget.imageStore,
            imageIds: entry.imageIds,
            currentPage: _currentImagePage,
            onPageChanged: (page) => setState(() => _currentImagePage = page),
          ),
          const SizedBox(height: 24),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${date.year}年${date.month}月${date.day}日',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (entry.mood != null)
              Text(entry.mood!, style: const TextStyle(fontSize: 30)),
          ],
        ),
        if (entry.location != null) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                Icons.location_on_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                entry.location!.address ??
                    '${entry.location!.latitude.toStringAsFixed(5)}, '
                        '${entry.location!.longitude.toStringAsFixed(5)}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        SelectableText(
          entry.body,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.8),
        ),
        if (entry.tags.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entry.tags
                .map((tag) => Chip(label: Text('#$tag')))
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '写于 ${_formatTimestamp(entry.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_hasAiReply(entry)) ...[
          const SizedBox(height: 28),
          _buildAiSummaryCard(entry),
          const SizedBox(height: 14),
          _buildChatInvitation(entry),
        ],
        _buildChatHistory(entry),
      ],
    );
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildAiSummaryCard(DiaryEntryV2 entry) {
    final summaries = entry.aiAnalyses
        .where(
          (analysis) =>
              analysis.startsWith('【AI 悄悄话】') ||
              analysis.startsWith('【AI 回信】') ||
              analysis.startsWith('【AI 总结】'),
        )
        .toList(growable: false);
    final latest = summaries.isEmpty
        ? null
        : summaries.last
              .replaceFirst('【AI 悄悄话】', '')
              .replaceFirst('【AI 回信】', '')
              .replaceFirst('【AI 总结】', '')
              .trim();
    if (latest == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'AI 的悄悄话',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '重新生成',
                  visualDensity: VisualDensity.compact,
                  onPressed: _summarizing ? null : () => _summarize(entry),
                  icon: _summarizing
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
            const Divider(height: 18),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: MarkdownBody(
                data: latest,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.55),
                      h1: Theme.of(context).textTheme.titleMedium,
                      h2: Theme.of(context).textTheme.titleSmall,
                      h3: Theme.of(context).textTheme.titleSmall,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            _buildFeedbackButtons(entry, latest),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackButtons(DiaryEntryV2 entry, String response) {
    final responseId = AiResponseFeedbackStoreV2.responseId(entry.id, response);
    return FutureBuilder<AiResponseFeedbackV2?>(
      future: _feedbackStore.read(responseId),
      builder: (context, snapshot) {
        final feedback = snapshot.data;
        return Row(
          children: [
            Text('这次回应', style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            IconButton(
              tooltip: '有帮助',
              visualDensity: VisualDensity.compact,
              onPressed: () => _saveFeedback(responseId, helpful: true),
              icon: Icon(
                feedback?.helpful == true
                    ? Icons.thumb_up_rounded
                    : Icons.thumb_up_outlined,
                size: 19,
              ),
            ),
            IconButton(
              tooltip: '不太合适',
              visualDensity: VisualDensity.compact,
              onPressed: () => _chooseNegativeFeedback(responseId),
              icon: Icon(
                feedback?.helpful == false
                    ? Icons.thumb_down_rounded
                    : Icons.thumb_down_outlined,
                size: 19,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveFeedback(
    String responseId, {
    required bool helpful,
    String reason = '',
  }) async {
    await _feedbackStore.save(
      AiResponseFeedbackV2(
        responseId: responseId,
        helpful: helpful,
        reason: reason,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (mounted) {
      setState(() {});
      _message(helpful ? '已记下：这次回应有帮助' : '已记下你的反馈');
    }
  }

  Future<void> _chooseNegativeFeedback(String responseId) async {
    const reasons = ['太空泛', '说教感太强', '建议太多', '问题太多', '没有理解重点', '回复太长'];
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('哪里不太合适？', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons
                    .map(
                      (value) => ActionChip(
                        label: Text(value),
                        onPressed: () => Navigator.pop(context, value),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
    if (reason != null) {
      await _saveFeedback(responseId, helpful: false, reason: reason);
    }
  }

  Widget _buildChatInvitation(DiaryEntryV2 entry) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openChat(entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '还想继续说说吗？',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 3),
                    Text('想继续说说的话，可以从这里开始'),
                  ],
                ),
              ),
              Text(
                '继续聊',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasAiReply(DiaryEntryV2 entry) => entry.aiAnalyses.any(
    (analysis) =>
        analysis.startsWith('【AI 悄悄话】') ||
        analysis.startsWith('【AI 回信】') ||
        analysis.startsWith('【AI 总结】'),
  );

  Widget _buildChatHistory(DiaryEntryV2 entry) {
    final sessions =
        entry.aiAnalyses
            .map(AiChatSessionV2.tryDecode)
            .whereType<AiChatSessionV2>()
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final legacyRecords = entry.aiAnalyses
        .where(
          (analysis) =>
              !analysis.startsWith('【AI 总结】') &&
              !analysis.startsWith('【AI 悄悄话】') &&
              !analysis.startsWith('【AI 回信】') &&
              AiChatSessionV2.tryDecode(analysis) == null,
        )
        .toList(growable: false);
    if (sessions.isEmpty && legacyRecords.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: Icon(
            Icons.forum_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text(
            'AI 对话记录',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            sessions.isEmpty
                ? '${legacyRecords.length} 条旧版记录'
                : '${sessions.length} 个 Chat',
          ),
          children: [
            const Divider(height: 1),
            ...sessions.map(
              (session) => ExpansionTile(
                leading: const Icon(Icons.chat_bubble_outline, size: 20),
                title: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${session.messages.length} 条消息 · '
                  '${_formatTimestamp(session.updatedAt)}',
                ),
                children: [
                  ...session.messages.map(
                    (message) => Align(
                      alignment: message.role == AiChatRoleV2.user
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 560),
                        margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: message.role == AiChatRoleV2.user
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: message.role == AiChatRoleV2.user
                            ? SelectableText(message.text)
                            : MarkdownBody(
                                data: message.text,
                                selectable: true,
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _openChat(entry, session: session),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('继续这个 Chat'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (legacyRecords.isNotEmpty)
              ExpansionTile(
                title: const Text('旧版保存内容'),
                subtitle: Text('${legacyRecords.length} 条'),
                children: legacyRecords
                    .map(
                      (record) => Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                        child: MarkdownBody(
                          data: record.replaceFirst('【AI 伴聊】', '').trim(),
                          selectable: true,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _summarize(DiaryEntryV2 entry) async {
    setState(() => _summarizing = true);
    try {
      final response = await _aiService.writeFriendReply(entry);
      if (!mounted) return;
      final saved = entry.copyWith(
        aiAnalyses: [...entry.aiAnalyses, '【AI 悄悄话】\n${response.text}'],
        updatedAt: DateTime.now().toUtc(),
      );
      await widget.repository.save(saved);
      await _automaticReply.markCompleted(saved);
      if (mounted) {
        setState(_reload);
        _message('AI 悄悄话已保存到本篇日记');
      }
    } on AiNotConfiguredV2 catch (error) {
      if (mounted) await _showAiConfiguration(error.message);
    } on AiFailureV2 catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _openChat(DiaryEntryV2 entry, {AiChatSessionV2? session}) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiaryAiChatPageV2(
          entry: entry,
          repository: widget.repository,
          session: session,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _showAiConfiguration(String message) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI 尚未配置'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
    if (open == true && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsPageV2()));
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit(DiaryEntryV2 entry) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiaryEditorPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          entry: entry,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(_reload);
    }
  }

  Future<void> _toggleFavorite(DiaryEntryV2 entry) async {
    await widget.repository.setFavorite(
      entry.id,
      isFavorite: !entry.isFavorite,
    );
    if (mounted) {
      setState(_reload);
    }
  }

  Future<void> _extractLifeFragment(DiaryEntryV2 entry) async {
    final repository = widget.lifeFragmentRepository;
    if (repository == null) return;
    final saved = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LifeFragmentEditorPageV2(entry: entry, repository: repository),
      ),
    );
    if (saved != null && mounted) {
      _message('已保存到人生指南');
    }
  }

  Future<void> _suggestMemories(DiaryEntryV2 entry) async {
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) =>
            AiMemorySuggestionPageV2(entry: entry, service: _aiService),
      ),
    );
    if (saved != null && saved > 0 && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已确认保存 $saved 条AI记忆')));
    }
  }

  Future<void> _moveToTrash(DiaryEntryV2 entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移入回收站？'),
        content: const Text('可以稍后从回收站恢复这篇日记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.repository.moveToTrash(
      entry.id,
      deletedAt: DateTime.now().toUtc(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

enum _DetailAction { memorySuggestions, trash }

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({
    required this.imageStore,
    required this.imageIds,
    required this.currentPage,
    required this.onPageChanged,
  });

  final DiaryImageStoreV2 imageStore;
  final List<String> imageIds;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PageView.builder(
            key: const Key('detail-image-viewer'),
            itemCount: imageIds.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) => _StoredImage(
              key: ValueKey('detail-image-$index'),
              imageStore: imageStore,
              imageId: imageIds[index],
            ),
          ),
        ),
        if (imageIds.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              imageIds.length,
              (index) => AnimatedContainer(
                key: ValueKey('detail-image-indicator-$index'),
                duration: const Duration(milliseconds: 180),
                width: index == currentPage ? 20 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: index == currentPage
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StoredImage extends StatelessWidget {
  const _StoredImage({
    required this.imageStore,
    required this.imageId,
    super.key,
  });

  final DiaryImageStoreV2 imageStore;
  final String imageId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: imageStore.read(imageId),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: bytes == null
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined, size: 42),
                        SizedBox(height: 8),
                        Text('图片加载失败'),
                      ],
                    ),
                  ),
                )
              : Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => _FullScreenPhoto(bytes: bytes),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        const Positioned(
                          right: 10,
                          bottom: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0x88000000),
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(
                                Icons.fullscreen_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('查看照片'),
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Center(
            child: Image.memory(
              bytes,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
