import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../../shared/tag_memory_field_v2.dart';
import '../../../ai/application/automatic_diary_reply_coordinator_v2.dart';
import '../../../ai/application/diary_ai_service_v2.dart';
import '../../../ai/data/ai_configuration_store_v2.dart';
import '../../../ai/data/ai_reply_task_store_v2.dart';
import '../../../ai/data/gemini_rest_client_v2.dart';
import '../../../ai/domain/ai_chat_session_v2.dart';
import '../../application/ports/diary_image_store_v2.dart';
import '../../data/local/diary_metadata_template_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/entities/diary_metadata_template_v2.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../widgets/diary_rich_text_v2.dart';
import 'location_picker_page_v2.dart';

class DiaryEditorPageV2 extends StatefulWidget {
  const DiaryEditorPageV2({
    required this.repository,
    required this.imageStore,
    this.entry,
    this.initialBody = '',
    this.initialAiSession,
    this.skipAutomaticReply = false,
    this.metadataTemplateStore,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final DiaryEntryV2? entry;
  final String initialBody;
  final AiChatSessionV2? initialAiSession;
  final bool skipAutomaticReply;
  final DiaryMetadataTemplateStoreV2? metadataTemplateStore;

  bool get isEditing => entry != null;

  @override
  State<DiaryEditorPageV2> createState() => _DiaryEditorPageV2State();
}

class _DiaryEditorPageV2State extends State<DiaryEditorPageV2> {
  late final QuillController _editorController;
  late final TextEditingController _tagsController;
  late final TextEditingController _moodController;
  late final FocusNode _editorFocusNode;
  late final ScrollController _editorScrollController;
  late final DiaryMetadataTemplateStoreV2 _metadataTemplateStore;
  late DateTime _entryDate;
  final Set<String> _newImageIds = {};
  String? _mood;
  DiaryLocation? _location;
  bool _isSaving = false;
  bool _didSave = false;
  late final AutomaticDiaryReplyCoordinatorV2 _automaticReply;

  static const _moods = ['😊', '😌', '🥰', '😔', '😴'];

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _editorController = QuillController(
      document: diaryDocumentFromContent(
        deltaJson: entry?.contentDelta,
        plainText: entry?.body ?? widget.initialBody,
        trailingImageIds: entry?.contentDelta == null
            ? entry?.imageIds ?? const []
            : const [],
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _tagsController = TextEditingController(text: entry?.tags.join(', '));
    _moodController = TextEditingController(text: entry?.mood);
    _editorFocusNode = FocusNode();
    _editorScrollController = ScrollController();
    _metadataTemplateStore =
        widget.metadataTemplateStore ?? DiaryMetadataTemplateStoreV2();
    _entryDate = entry?.entryDate.toLocal() ?? DateTime.now();
    _mood = entry?.mood;
    _location = entry?.location;

    final configurationStore = AiConfigurationStoreV2();
    final aiService = DiaryAiServiceV2(
      GeminiRestClientV2(configurationStore: configurationStore),
    );
    _automaticReply = AutomaticDiaryReplyCoordinatorV2(
      repository: widget.repository,
      taskStore: SharedPreferencesAiReplyTaskStoreV2(),
      loadConfiguration: configurationStore.load,
      generateReply: (entry) async =>
          (await aiService.writeFriendReply(entry)).text,
    );
  }

  @override
  void dispose() {
    if (!_didSave) {
      for (final imageId in _newImageIds) {
        unawaited(widget.imageStore.delete(imageId));
      }
    }
    _editorController.dispose();
    _tagsController.dispose();
    _moodController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑' : '新日记'),
        actions: [
          IconButton(
            tooltip: '日记信息',
            onPressed: _isSaving ? null : _openMetadata,
            icon: const Icon(Icons.more_horiz),
          ),
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? '保存中…' : '保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: QuillEditor.basic(
              key: const Key('diary-rich-editor'),
              controller: _editorController,
              focusNode: _editorFocusNode,
              scrollController: _editorScrollController,
              config: QuillEditorConfig(
                autoFocus: !widget.isEditing,
                expands: true,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 36),
                placeholder: '从这里开始写…',
                scrollBottomInset: 96,
                customStyles: quietDiaryStyles(context),
                embedBuilders: [
                  DiaryImageEmbedBuilderV2(imageStore: widget.imageStore),
                ],
              ),
            ),
          ),
          _QuietEditorToolbar(
            controller: _editorController,
            onInsertImage: _isSaving ? null : _pickAndInsertImages,
          ),
        ],
      ),
    );
  }

  Future<void> _openMetadata() async {
    var templates = (await _metadataTemplateStore.load()).toList();
    if (!mounted) return;
    final templateNameController = TextEditingController();
    var isNamingTemplate = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickDate() async {
            final selected = await showDatePicker(
              context: sheetContext,
              initialDate: _entryDate,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (selected == null || !mounted) return;
            setState(() => _entryDate = selected);
            setSheetState(() {});
          }

          Future<void> pickLocation() async {
            final selected = await Navigator.of(sheetContext)
                .push<DiaryLocation>(
                  MaterialPageRoute(
                    builder: (_) =>
                        LocationPickerPageV2(initialLocation: _location),
                  ),
                );
            if (selected == null || !mounted) return;
            setState(() => _location = selected);
            setSheetState(() {});
          }

          void applyTemplate(DiaryMetadataTemplateV2 template) {
            setState(() {
              _mood = template.mood;
              _moodController.text = template.mood ?? '';
              _tagsController.text = template.tags.join(', ');
              _location = template.location;
            });
            setSheetState(() {});
          }

          Future<void> saveTemplate() async {
            final name = templateNameController.text.trim();
            if (name.isEmpty) return;
            final template = DiaryMetadataTemplateV2(
              id: const Uuid().v4(),
              name: name,
              mood: _mood,
              tags: _currentTags(),
              location: _location,
            );
            await _metadataTemplateStore.save(template);
            if (!sheetContext.mounted) return;
            templates = [...templates, template];
            templateNameController.clear();
            isNamingTemplate = false;
            setSheetState(() {});
          }

          Future<void> deleteTemplate(String id) async {
            await _metadataTemplateStore.delete(id);
            if (!sheetContext.mounted) return;
            templates.removeWhere((template) => template.id == id);
            setSheetState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                22,
                24,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '日记信息',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '完成',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.check),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '信息模板',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            isNamingTemplate = true;
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('保存当前'),
                        ),
                      ],
                    ),
                    if (templates.isEmpty && !isNamingTemplate)
                      Text(
                        '保存常用的地点、心情和标签，下次轻点一次即可填入。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (final template in templates)
                      _MetadataTemplateLine(
                        template: template,
                        onApply: () => applyTemplate(template),
                        onDelete: () => deleteTemplate(template.id),
                      ),
                    if (isNamingTemplate)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('metadata-template-name'),
                                controller: templateNameController,
                                autofocus: true,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => saveTemplate(),
                                decoration: const InputDecoration(
                                  hintText: '模板名称，例如：学校',
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                templateNameController.clear();
                                isNamingTemplate = false;
                                setSheetState(() {});
                              },
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: saveTemplate,
                              child: const Text('存下'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    _MetadataLine(
                      label: '时间',
                      value: _formatDate(_entryDate),
                      onTap: pickDate,
                    ),
                    _MetadataLine(
                      label: '地点',
                      value: _location?.address ?? '未添加',
                      onTap: pickLocation,
                      onClear: _location == null
                          ? null
                          : () {
                              setState(() => _location = null);
                              setSheetState(() {});
                            },
                    ),
                    const SizedBox(height: 26),
                    Text('心情', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final mood in _moods)
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: InkResponse(
                              radius: 24,
                              onTap: () {
                                setState(() {
                                  _mood = _mood == mood ? null : mood;
                                  _moodController.text = _mood ?? '';
                                });
                                setSheetState(() {});
                              },
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 160),
                                opacity: _mood == null || _mood == mood
                                    ? 1
                                    : 0.32,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    mood,
                                    style: const TextStyle(fontSize: 25),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('custom-mood-field'),
                      controller: _moodController,
                      maxLength: 24,
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        setState(
                          () => _mood = value.trim().isEmpty
                              ? null
                              : value.trim(),
                        );
                        setSheetState(() {});
                      },
                      decoration: const InputDecoration(
                        hintText: '或写下自己的心情，例如：期待又紧张 🌧️',
                        counterText: '',
                        border: UnderlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('标签', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    StreamBuilder<List<DiaryEntryV2>>(
                      stream: widget.repository.watchEntries(),
                      builder: (context, snapshot) => TagMemoryFieldV2(
                        controller: _tagsController,
                        suggestions: (snapshot.data ?? const <DiaryEntryV2>[])
                            .expand((entry) => entry.tags),
                        hintText: '生活, 工作, 旅行',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    templateNameController.dispose();
    if (mounted) _editorFocusNode.requestFocus();
  }

  Future<void> _pickAndInsertImages() async {
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 90);
      for (final file in files) {
        final extension = path.extension(file.name);
        final imageId = await widget.imageStore.save(
          bytes: await file.readAsBytes(),
          extension: extension.isEmpty ? '.jpg' : extension,
        );
        _newImageIds.add(imageId);
        _insertImage(imageId);
      }
      if (mounted) _editorFocusNode.requestFocus();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择照片失败：$error')));
      }
    }
  }

  void _insertImage(String imageId) {
    final selection = _editorController.selection;
    final index = selection.start.clamp(
      0,
      _editorController.document.length - 1,
    );
    _editorController.replaceText(
      index,
      selection.isValid ? selection.end - selection.start : 0,
      BlockEmbed.image(imageId),
      TextSelection.collapsed(offset: index + 1),
    );
    _editorController.replaceText(
      index + 1,
      0,
      '\n',
      TextSelection.collapsed(offset: index + 2),
    );
  }

  Future<void> _save() async {
    final document = _editorController.document;
    final body = diaryPlainText(document);
    final imageIds = diaryImageIds(document);
    if (body.isEmpty && imageIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写一点内容吧')));
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now().toUtc();
    final tags = _currentTags();
    final existing = widget.entry;

    try {
      final contentDelta = encodeDiaryDocument(document);
      final savedEntry = existing == null
          ? DiaryEntryV2(
              id: const Uuid().v4(),
              body: body,
              contentDelta: contentDelta,
              entryDate: _entryDate,
              createdAt: now,
              updatedAt: now,
              mood: _mood,
              tags: tags,
              imageIds: imageIds,
              location: _location,
              aiAnalyses: [
                if (widget.initialAiSession != null)
                  widget.initialAiSession!.encode(),
              ],
            )
          : existing.copyWith(
              body: body,
              contentDelta: contentDelta,
              entryDate: _entryDate,
              updatedAt: now,
              mood: _mood,
              clearMood: _mood == null,
              tags: tags,
              imageIds: imageIds,
              location: _location,
              clearLocation: _location == null,
            );
      await widget.repository.save(savedEntry);
      if (!widget.skipAutomaticReply) {
        unawaited(_runAutomaticReplySafely(savedEntry));
      }

      final unusedImageIds = {
        ...?existing?.imageIds,
        ..._newImageIds,
      }.difference(imageIds.toSet());
      for (final imageId in unusedImageIds) {
        await widget.imageStore.delete(imageId);
      }
      _didSave = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _runAutomaticReplySafely(DiaryEntryV2 entry) async {
    try {
      await _automaticReply.scheduleAndRun(entry);
    } catch (error, stackTrace) {
      debugPrint('Automatic diary reply failed: $error\n$stackTrace');
    }
  }

  String _formatDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  List<String> _currentTags() => _tagsController.text
      .split(RegExp(r'[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

class _QuietEditorToolbar extends StatelessWidget {
  const _QuietEditorToolbar({
    required this.controller,
    required this.onInsertImage,
  });

  final QuillController controller;
  final VoidCallback? onInsertImage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FormatButton(
                  tooltip: '小标题',
                  icon: Icons.title,
                  selected: _isSelected(Attribute.h2),
                  onPressed: () => _toggle(Attribute.h2),
                ),
                _FormatButton(
                  tooltip: '粗体',
                  icon: Icons.format_bold,
                  selected: _isSelected(Attribute.bold),
                  onPressed: () => _toggle(Attribute.bold),
                ),
                _FormatButton(
                  tooltip: '斜体',
                  icon: Icons.format_italic,
                  selected: _isSelected(Attribute.italic),
                  onPressed: () => _toggle(Attribute.italic),
                ),
                _FormatButton(
                  tooltip: '项目符号',
                  icon: Icons.format_list_bulleted,
                  selected: _isSelected(Attribute.ul),
                  onPressed: () => _toggle(Attribute.ul),
                ),
                _FormatButton(
                  tooltip: '引用',
                  icon: Icons.format_quote,
                  selected: _isSelected(Attribute.blockQuote),
                  onPressed: () => _toggle(Attribute.blockQuote),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: '在这里插入图片',
                  onPressed: onInsertImage,
                  icon: const Icon(Icons.image_outlined, size: 21),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isSelected(Attribute attribute) {
    final current = controller.getSelectionStyle().attributes[attribute.key];
    return current?.value == attribute.value;
  }

  void _toggle(Attribute attribute) {
    controller.formatSelection(
      _isSelected(attribute) ? Attribute.clone(attribute, null) : attribute,
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: selected
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurfaceVariant,
        backgroundColor: selected
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.transparent,
      ),
      icon: Icon(icon, size: 21),
    );
  }
}

class _MetadataTemplateLine extends StatelessWidget {
  const _MetadataTemplateLine({
    required this.template,
    required this.onApply,
    required this.onDelete,
  });

  final DiaryMetadataTemplateV2 template;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (template.location != null)
        template.location!.address?.trim().isNotEmpty == true
            ? template.location!.address!.trim()
            : '已保存位置',
      if (template.mood?.trim().isNotEmpty == true) template.mood!.trim(),
      ...template.tags.map((tag) => '#$tag'),
    ];
    return InkWell(
      onTap: onApply,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      details.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Text('使用', style: Theme.of(context).textTheme.labelMedium),
            IconButton(
              tooltip: '删除模板',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (onClear != null)
              IconButton(
                tooltip: '清除$label',
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 17),
              )
            else
              const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
