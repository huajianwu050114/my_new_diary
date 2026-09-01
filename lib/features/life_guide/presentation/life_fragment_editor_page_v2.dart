import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../ai/application/diary_ai_service_v2.dart';
import '../../ai/data/ai_configuration_store_v2.dart';
import '../../ai/data/gemini_rest_client_v2.dart';
import '../../ai/domain/ai_chat_session_v2.dart';
import '../../ai/domain/ai_models_v2.dart';
import '../../diary/domain/entities/diary_entry.dart';
import '../domain/life_fragment_draft_v2.dart';
import '../domain/life_fragment_repository_v2.dart';
import '../domain/life_fragment_v2.dart';
import '../../../shared/tag_memory_field_v2.dart';

class LifeFragmentEditorPageV2 extends StatefulWidget {
  const LifeFragmentEditorPageV2({
    required this.entry,
    required this.repository,
    super.key,
  });

  final DiaryEntryV2 entry;
  final LifeFragmentRepositoryV2 repository;

  @override
  State<LifeFragmentEditorPageV2> createState() =>
      _LifeFragmentEditorPageV2State();
}

class _LifeFragmentEditorPageV2State extends State<LifeFragmentEditorPageV2> {
  late final DiaryAiServiceV2 _aiService;
  final _title = TextEditingController();
  final _coreInsight = TextEditingController();
  final _context = TextEditingController();
  final _evidence = TextEditingController();
  final _futureUse = TextEditingController();
  final _futureMessage = TextEditingController();
  final _theme = TextEditingController();
  final _tags = TextEditingController();

  bool _includeWhispers = false;
  bool _includeConversations = false;
  bool _isRope = false;
  bool _generating = false;
  bool _saving = false;
  bool _hasGenerated = false;
  String? _generationNote;
  String? _targetFragmentId;

  List<String> get _whispers => widget.entry.aiAnalyses
      .where(
        (value) => value.startsWith('【AI 悄悄话】') || value.startsWith('【AI 回信】'),
      )
      .toList(growable: false);

  List<AiChatSessionV2> get _conversations => widget.entry.aiAnalyses
      .map(AiChatSessionV2.tryDecode)
      .whereType<AiChatSessionV2>()
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final configurationStore = AiConfigurationStoreV2();
    _aiService = DiaryAiServiceV2(
      GeminiRestClientV2(configurationStore: configurationStore),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _coreInsight.dispose();
    _context.dispose();
    _evidence.dispose();
    _futureUse.dispose();
    _futureMessage.dispose();
    _theme.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提炼人生碎片')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: [
          Text(
            '这段经历，留下了什么？',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'AI 只帮助整理。只有你确认的内容，才会进入人生指南。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '本次使用的材料',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    onChanged: null,
                    title: Text('当前日记正文'),
                    subtitle: Text('提炼的必选来源'),
                  ),
                  if (_whispers.isNotEmpty)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _includeWhispers,
                      onChanged: _generating
                          ? null
                          : (value) => setState(
                              () => _includeWhispers = value ?? false,
                            ),
                      title: const Text('这篇日记的 AI 悄悄话'),
                      subtitle: Text('${_whispers.length} 条，默认不发送'),
                    ),
                  if (_conversations.isNotEmpty)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _includeConversations,
                      onChanged: _generating
                          ? null
                          : (value) => setState(
                              () => _includeConversations = value ?? false,
                            ),
                      title: const Text('围绕这篇日记的 AI 对话'),
                      subtitle: Text('${_conversations.length} 个会话，默认不发送'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_generating ? '正在提炼…' : '生成可编辑草稿'),
          ),
          if (_generationNote != null) ...[
            const SizedBox(height: 12),
            Text(
              _generationNote!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          if (_hasGenerated) ...[
            const SizedBox(height: 28),
            StreamBuilder<List<LifeFragmentV2>>(
              stream: widget.repository.watchFragments(
                status: LifeFragmentStatusV2.confirmed,
              ),
              builder: (context, snapshot) {
                final existing = snapshot.data ?? const <LifeFragmentV2>[];
                if (existing.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: DropdownButtonFormField<String?>(
                    value: _targetFragmentId,
                    decoration: const InputDecoration(
                      labelText: '保存到哪里',
                      prefixIcon: Icon(Icons.call_merge_rounded),
                      helperText: '选择既有碎片时，会保留原文并把这次认识追加进去',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('创建一片新内容'),
                      ),
                      ...existing.map(
                        (fragment) => DropdownMenuItem<String?>(
                          value: fragment.id,
                          child: Text(
                            fragment.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _targetFragmentId = value),
                  ),
                );
              },
            ),
            _field(_title, '标题', minLines: 1),
            _field(_coreInsight, '核心认识'),
            _field(_context, '它来自什么经历'),
            _field(_evidence, '支撑这份认识的真实证据'),
            _field(_futureUse, '未来什么时候值得重新读到它'),
            _field(_futureMessage, '写给未来自己的话'),
            TextField(
              controller: _theme,
              decoration: const InputDecoration(
                labelText: '主题（由你命名）',
                hintText: '例如：独处、创作、关于家的想法',
              ),
            ),
            const SizedBox(height: 14),
            StreamBuilder<List<LifeFragmentV2>>(
              stream: widget.repository.watchFragments(),
              builder: (context, snapshot) => TagMemoryFieldV2(
                controller: _tags,
                suggestions: {
                  ...widget.entry.tags,
                  ...(snapshot.data ?? const <LifeFragmentV2>[]).expand(
                    (fragment) => fragment.tags,
                  ),
                },
                hintText: '希望, 选择, 低谷',
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isRope,
              onChanged: (value) => setState(() => _isRope = value),
              title: const Text('标记为重要提醒'),
              subtitle: const Text('把以后想更快找到的内容放在这里'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving || _targetFragmentId != null
                        ? null
                        : () => _save(LifeFragmentStatusV2.draft),
                    child: const Text('保存草稿'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _save(LifeFragmentStatusV2.confirmed),
                    child: Text(
                      _saving
                          ? '保存中…'
                          : _targetFragmentId == null
                          ? '确认并收进指南'
                          : '补充进既有碎片',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int minLines = 3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: null,
        decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      ),
    );
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _generating = true;
      _generationNote = null;
    });
    try {
      final response = await _aiService.createLifeFragmentDraft(
        entry: widget.entry,
        supportingTexts: _supportingTexts(),
      );
      final draft = LifeFragmentDraftV2.parse(response.text);
      if (!mounted) return;
      setState(() {
        _applyDraft(draft);
        _hasGenerated = draft.suitable;
        _generationNote = draft.suitable
            ? draft.reason
            : (draft.reason.isEmpty ? '这次材料暂时不必提炼成人生碎片。' : draft.reason);
      });
    } on AiNotConfiguredV2 catch (error) {
      if (mounted) _message(error.message);
    } on AiFailureV2 catch (error) {
      if (mounted) _message(error.message);
    } on FormatException {
      if (mounted) _message('AI 返回的草稿格式不完整，请重新生成');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  List<String> _supportingTexts() {
    final values = <String>[];
    if (_includeWhispers) {
      values.addAll(
        _whispers.map(
          (value) => value
              .replaceFirst('【AI 悄悄话】', '')
              .replaceFirst('【AI 回信】', '')
              .trim(),
        ),
      );
    }
    if (_includeConversations) {
      for (final session in _conversations) {
        values.add(
          [
            '会话：${session.title}',
            ...session.messages.map(
              (message) =>
                  '${message.role == AiChatRoleV2.user ? '用户' : 'AI'}：${message.text}',
            ),
          ].join('\n'),
        );
      }
    }
    return values;
  }

  void _applyDraft(LifeFragmentDraftV2 draft) {
    _title.text = draft.title;
    _coreInsight.text = draft.coreInsight;
    _context.text = draft.context;
    _evidence.text = draft.evidence;
    _futureUse.text = draft.futureUse;
    _futureMessage.text = draft.messageToFutureSelf;
    _tags.text = draft.tags.join(', ');
  }

  Future<void> _save(LifeFragmentStatusV2 status) async {
    if (_title.text.trim().isEmpty || _coreInsight.text.trim().isEmpty) {
      _message('标题和核心认识不能为空');
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final newFragment = LifeFragmentV2(
      id: const Uuid().v4(),
      title: _title.text.trim(),
      coreInsight: _coreInsight.text.trim(),
      context: _context.text.trim(),
      evidence: _evidence.text.trim(),
      futureUse: _futureUse.text.trim(),
      messageToFutureSelf: _futureMessage.text.trim(),
      theme: _theme.text.trim(),
      tags: _tags.text
          .split(RegExp(r'[,，]'))
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(growable: false),
      sourceDiaryIds: [widget.entry.id],
      isRope: _isRope,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final target = _targetFragmentId == null
          ? null
          : await widget.repository.getById(_targetFragmentId!);
      final fragment = target == null
          ? newFragment
          : mergeLifeFragmentsV2(target, newFragment, updatedAt: now);
      await widget.repository.save(fragment);
      if (mounted) Navigator.of(context).pop(fragment);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _message('保存人生碎片失败：$error');
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
