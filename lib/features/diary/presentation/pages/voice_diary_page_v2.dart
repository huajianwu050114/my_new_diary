import 'package:flutter/material.dart';

import '../../../ai/application/diary_ai_service_v2.dart';
import '../../../ai/data/ai_configuration_store_v2.dart';
import '../../../ai/data/gemini_rest_client_v2.dart';
import '../../../ai/domain/ai_models_v2.dart';

class VoiceDiaryPageV2 extends StatefulWidget {
  const VoiceDiaryPageV2({this.initialText = '', this.aiService, super.key});

  final String initialText;
  final DiaryAiServiceV2? aiService;

  @override
  State<VoiceDiaryPageV2> createState() => _VoiceDiaryPageV2State();
}

class _VoiceDiaryPageV2State extends State<VoiceDiaryPageV2> {
  late final TextEditingController _transcriptController;
  late final TextEditingController _polishedController;
  late final FocusNode _transcriptFocusNode;
  late final DiaryAiServiceV2 _aiService;
  bool _polishing = false;

  @override
  void initState() {
    super.initState();
    _transcriptController = TextEditingController(text: widget.initialText);
    _polishedController = TextEditingController();
    _transcriptFocusNode = FocusNode();
    final configurationStore = AiConfigurationStoreV2();
    _aiService =
        widget.aiService ??
        DiaryAiServiceV2(
          GeminiRestClientV2(configurationStore: configurationStore),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _transcriptFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    _polishedController.dispose();
    _transcriptFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('语音成稿')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.keyboard_voice_rounded,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '点击下方文本框，再使用搜狗输入法键盘上的语音按钮。说出的内容会由输入法直接写进这里。',
                    style: TextStyle(color: colors.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '文字草稿',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: _polishing ? null : _clearTranscript,
                child: const Text('清空文字'),
              ),
            ],
          ),
          TextField(
            key: const Key('voice_transcript_field'),
            controller: _transcriptController,
            focusNode: _transcriptFocusNode,
            autofocus: true,
            minLines: 10,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(_polishedController.clear),
            decoration: const InputDecoration(
              hintText: '搜狗语音输入的文字会出现在这里，也可以直接打字修改',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _canPolish ? _polish : null,
            icon: _polishing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_rounded),
            label: Text(_polishing ? '正在整理…' : 'AI 轻度润色'),
          ),
          if (_polishedController.text.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '润色后的日记',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(_polishedController.clear),
                  child: const Text('放弃润色'),
                ),
              ],
            ),
            TextField(
              controller: _polishedController,
              minLines: 6,
              maxLines: null,
              decoration: const InputDecoration(
                helperText: 'AI 只负责去语气词、重复内容和整理断句；使用前仍可修改',
                alignLabelWithHint: true,
              ),
            ),
          ],
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: _hasDraft && !_polishing ? _useDraft : null,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(_polishedController.text.isEmpty ? '使用文字草稿' : '使用润色稿'),
          ),
        ],
      ),
    );
  }

  bool get _hasDraft =>
      _polishedController.text.trim().isNotEmpty ||
      _transcriptController.text.trim().isNotEmpty;

  bool get _canPolish =>
      !_polishing && _transcriptController.text.trim().isNotEmpty;

  Future<void> _polish() async {
    FocusScope.of(context).unfocus();
    setState(() => _polishing = true);
    try {
      final response = await _aiService.polishVoiceTranscript(
        _transcriptController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _polishedController.text = response.text.trim());
    } on AiNotConfiguredV2 catch (error) {
      if (mounted) _message('${error.message}，仍可直接使用文字草稿');
    } on AiFailureV2 catch (error) {
      if (mounted) _message('${error.message}，仍可直接使用文字草稿');
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  void _clearTranscript() {
    setState(() {
      _transcriptController.clear();
      _polishedController.clear();
    });
    _transcriptFocusNode.requestFocus();
  }

  void _useDraft() {
    final draft = _polishedController.text.trim().isNotEmpty
        ? _polishedController.text.trim()
        : _transcriptController.text.trim();
    Navigator.of(context).pop(draft);
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
