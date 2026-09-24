import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../ai/application/diary_ai_service_v2.dart';
import '../../../ai/application/automatic_diary_reply_coordinator_v2.dart';
import '../../../ai/data/ai_configuration_store_v2.dart';
import '../../../ai/data/ai_reply_task_store_v2.dart';
import '../../../ai/data/gemini_rest_client_v2.dart';
import '../../../ai/domain/ai_chat_session_v2.dart';
import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import 'location_picker_page_v2.dart';
import 'voice_diary_page_v2.dart';
import '../../../../shared/tag_memory_field_v2.dart';

class DiaryEditorPageV2 extends StatefulWidget {
  const DiaryEditorPageV2({
    required this.repository,
    required this.imageStore,
    this.entry,
    this.initialBody = '',
    this.initialAiSession,
    this.skipAutomaticReply = false,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final DiaryEntryV2? entry;
  final String initialBody;
  final AiChatSessionV2? initialAiSession;
  final bool skipAutomaticReply;

  bool get isEditing => entry != null;

  @override
  State<DiaryEditorPageV2> createState() => _DiaryEditorPageV2State();
}

class _DiaryEditorPageV2State extends State<DiaryEditorPageV2> {
  late final TextEditingController _bodyController;
  late final TextEditingController _tagsController;
  late DateTime _entryDate;
  late final List<String> _existingImageIds;
  final List<String> _removedImageIds = [];
  final List<_PendingImage> _pendingImages = [];
  String? _mood;
  DiaryLocation? _location;
  bool _isSaving = false;
  late final AutomaticDiaryReplyCoordinatorV2 _automaticReply;

  static const _moods = ['😊', '😌', '🥰', '😔', '😴'];

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _bodyController = TextEditingController(
      text: entry?.body ?? widget.initialBody,
    );
    _tagsController = TextEditingController(text: entry?.tags.join(', '));
    _entryDate = entry?.entryDate.toLocal() ?? DateTime.now();
    _mood = entry?.mood;
    _location = entry?.location;
    _existingImageIds = [...?entry?.imageIds];
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
    _bodyController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑日记' : '写下今天'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? '保存中…' : '保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('日记日期'),
            subtitle: Text(_formatDate(_entryDate)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('地点'),
            subtitle: Text(_location?.address ?? '添加地点'),
            trailing: _location == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: '清除地点',
                    onPressed: () => setState(() => _location = null),
                    icon: const Icon(Icons.close),
                  ),
            onTap: _pickLocation,
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _bodyController,
            autofocus: !widget.isEditing,
            minLines: 12,
            maxLines: null,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: '今天发生了什么？',
              alignLabelWithHint: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              suffixIcon: IconButton(
                tooltip: '语音输入',
                onPressed: _isSaving ? null : _openVoiceDraft,
                icon: const Icon(Icons.mic_none_rounded),
              ),
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.8),
          ),
          const SizedBox(height: 28),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '照片',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: _isSaving ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('添加'),
              ),
            ],
          ),
          if (_existingImageIds.isEmpty && _pendingImages.isEmpty)
            Text('可以添加多张照片', style: Theme.of(context).textTheme.bodySmall)
          else
            SizedBox(
              height: 112,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final imageId in _existingImageIds)
                    _ExistingImageTile(
                      imageStore: widget.imageStore,
                      imageId: imageId,
                      onRemove: () {
                        setState(() {
                          _existingImageIds.remove(imageId);
                          _removedImageIds.add(imageId);
                        });
                      },
                    ),
                  for (final image in _pendingImages)
                    _ImageTile(
                      bytes: image.bytes,
                      onRemove: () {
                        setState(() => _pendingImages.remove(image));
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Text('此刻心情', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: _moods
                .map(
                  (mood) => ChoiceChip(
                    label: Text(mood, style: const TextStyle(fontSize: 20)),
                    selected: _mood == mood,
                    onSelected: (selected) {
                      setState(() => _mood = selected ? mood : null);
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 20),
          StreamBuilder<List<DiaryEntryV2>>(
            stream: widget.repository.watchEntries(),
            builder: (context, snapshot) => TagMemoryFieldV2(
              controller: _tagsController,
              suggestions: (snapshot.data ?? const <DiaryEntryV2>[]).expand(
                (entry) => entry.tags,
              ),
              hintText: '生活, 工作, 旅行',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null && mounted) {
      setState(() => _entryDate = selected);
    }
  }

  Future<void> _openVoiceDraft() async {
    final draft = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VoiceDiaryPageV2(initialText: _bodyController.text),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _bodyController.text = draft;
      _bodyController.selection = TextSelection.collapsed(offset: draft.length);
    });
  }

  Future<void> _pickImages() async {
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 90);
      final images = <_PendingImage>[];
      for (final file in files) {
        images.add(
          _PendingImage(
            bytes: await file.readAsBytes(),
            extension: path.extension(file.name),
          ),
        );
      }
      if (mounted && images.isNotEmpty) {
        setState(() => _pendingImages.addAll(images));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择照片失败：$error')));
      }
    }
  }

  Future<void> _pickLocation() async {
    final selected = await Navigator.of(context).push<DiaryLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPageV2(initialLocation: _location),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _location = selected);
    }
  }

  Future<void> _save() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先写一点内容吧')));
      return;
    }

    setState(() => _isSaving = true);
    final now = DateTime.now().toUtc();
    final tags = _tagsController.text
        .split(RegExp(r'[,，]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final existing = widget.entry;
    final newImageIds = <String>[];

    try {
      for (final image in _pendingImages) {
        newImageIds.add(
          await widget.imageStore.save(
            bytes: image.bytes,
            extension: image.extension,
          ),
        );
      }
      final imageIds = [..._existingImageIds, ...newImageIds];
      final savedEntry = existing == null
          ? DiaryEntryV2(
              id: const Uuid().v4(),
              body: body,
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
      for (final imageId in _removedImageIds) {
        await widget.imageStore.delete(imageId);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      for (final imageId in newImageIds) {
        await widget.imageStore.delete(imageId);
      }
      if (!mounted) {
        return;
      }
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
      // The diary is already safely stored. A background AI failure must never
      // surface as a red error screen or make saving appear to have failed.
      debugPrint('Automatic diary reply failed: $error\n$stackTrace');
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }
}

class _PendingImage {
  const _PendingImage({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

class _ExistingImageTile extends StatelessWidget {
  const _ExistingImageTile({
    required this.imageStore,
    required this.imageId,
    required this.onRemove,
  });

  final DiaryImageStoreV2 imageStore;
  final String imageId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: imageStore.read(imageId),
      builder: (context, snapshot) =>
          _ImageTile(bytes: snapshot.data, onRemove: onRemove),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.bytes, required this.onRemove});

  final Uint8List? bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 112,
              height: 112,
              child: bytes == null
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Icon(Icons.broken_image_outlined),
                    )
                  : Image.memory(bytes!, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filled(
              visualDensity: VisualDensity.compact,
              tooltip: '移除照片',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
