// lib/voice_diary_dialog.dart
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:my_new_diary/diary_model.dart';
import 'package:my_new_diary/diary_service.dart';
import 'package:my_new_diary/gemini_service_local.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';



class VoiceDiaryDialog extends StatefulWidget {
  const VoiceDiaryDialog({super.key});

  @override
  State<VoiceDiaryDialog> createState() => _VoiceDiaryDialogState();
}

class _VoiceDiaryDialogState extends State<VoiceDiaryDialog> {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  String _rawText = '';
  String _statusText = '请授予麦克风权限...';
  bool _isProcessing = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _statusText = '点击麦克风开始录音...';
      });
      await _speechToText.initialize();
    } else {
      setState(() {
        _hasPermission = false;
        _statusText = '麦克风权限被拒绝，无法使用语音功能。';
      });
    }
  }

  void _startListening() async {
    if (!_hasPermission || !_speechToText.isAvailable) return;

    setState(() {
      _isListening = true;
      _statusText = '正在聆听...';
    });
    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _rawText = result.recognizedWords;
        });
      },
      localeId: 'zh_CN', // 设置为中文
    );
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
      _statusText = '录音结束，正在处理...';
    });
    // 增加一个小延迟，确保用户能看到状态变化
    Future.delayed(const Duration(milliseconds: 500), _processWithAi);
  }

  Future<void> _processWithAi() async {
    if (_rawText.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isProcessing = true);

    final geminiService = GeminiServiceLocal();
    final prompt = """
      你是一位出色的编辑。请将以下口语化的录音文本，整理成一篇流畅、有条理的书面日记。
      请保留原始的语气和核心情感，但可以修正语法、移除口头禅（比如 '嗯', '啊', '那个'），并组织成逻辑清晰的段落。
      请不要添加任何标题或额外的评论。只返回整理后的日记内容本身。
      
      原始文本:
      ---
      $_rawText
      """;

    // 从你的 AiModelService 获取模型名称，或者直接指定
    // 这里我们用 flash 模型，因为它对于这类任务来说速度快且成本低
    final (processedText, _) = await geminiService.generateResponse(
      [Content.text(prompt)],
      modelName: 'gemini-1.5-flash',
    );

    if (mounted) {
      DiaryEntry newEntry;
      if (processedText != null && !processedText.startsWith("ERROR:")) {
        newEntry = DiaryEntry(
          diaryId: '', // DiaryService 会生成 ID
          text: processedText,
          date: DateTime.now(),
          creationTime: DateTime.now(),
        );
      } else {
        // 如果 AI 处理失败，保存原始录音文本作为备用
        newEntry = DiaryEntry(
          diaryId: '',
          text: "语音记录 (AI整理失败):\n\n$_rawText",
          date: DateTime.now(),
          creationTime: DateTime.now(),
        );
      }
      await context.read<DiaryService>().addEntry(newEntry);
      Navigator.of(context).pop(true); // 返回 `true` 表示成功
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('语音日记'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('AI 正在整理您的思绪...'),
                  ],
                ),
              )
            else
              Column(
                children: [
                  Text(_statusText, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Container(
                    width: double.maxFinite,
                    constraints: const BoxConstraints(minHeight: 100),
                    child: Text(
                      _rawText,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: !_isProcessing
          ? [
        IconButton(
          icon: Icon(_isListening ? Icons.mic_off : Icons.mic, size: 32),
          color: Theme.of(context).colorScheme.primary,
          onPressed: !_hasPermission ? null : (_isListening ? _stopListening : _startListening),
        ),
      ]
          : null,
    );
  }
}