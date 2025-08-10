import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'diary_service.dart';
import 'map_selection_page.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:my_new_diary/diary_model.dart';
import 'ai_chat_page.dart';
import 'dart:convert';
import 'gemini_service_local.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:animate_do/animate_do.dart';


class AddDiaryPage extends StatefulWidget {
  // VVV 1. 改造构造函数 VVV
  final DateTime? selectedDate;  // 用于新建日记
  final DiaryEntry? entryToEdit; // 用于编辑日记

  const AddDiaryPage({super.key, this.selectedDate, this.entryToEdit});

  @override
  State<AddDiaryPage> createState() => _AddDiaryPageState();
}

class _AddDiaryPageState extends State<AddDiaryPage> {
  final TextEditingController _textController = TextEditingController();
  final List<File> _imageFiles = [];
  String? _selectedMood;
  final Map<String, String> _moodMap = {
    '1': '特别开心', '2': '很开心', '3': '有点开心', '4': '一般',
    '5': '有点伤心', '6': '伤心', '7': '很伤心', '8': '崩溃', '0': '生病',
  };
  final List<String> _tags = [];
  final TextEditingController _tagController = TextEditingController();

  double? _latitude;
  double? _longitude;
  String? _address;
  bool _isFetchingLocation = false;

  // VVV 2. 添加一个状态来判断当前是“编辑”还是“新建”模式 VVV
  bool _isEditMode = false;
  bool _isPrivate = false;
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  _SpokenSegment? _pendingTidyUpSegment;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    // VVV 3. 在初始化时，检查是否是编辑模式 VVV
    if (widget.entryToEdit != null) {
      setState(() {
        _isEditMode = true;
        final entry = widget.entryToEdit!;

        // 用旧日记的数据填充所有控件
        _textController.text = entry.text;
        _imageFiles.addAll(entry.imagePaths.map((path) => File(path)));
        _selectedMood = entry.mood;
        _tags.addAll(entry.tags);
        _latitude = entry.latitude;
        _longitude = entry.longitude;
        _address = entry.address;
        _isPrivate = entry.isPrivate;
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _tagController.dispose();
    _speechToText.stop();
    super.dispose();
  }

  // VVV 4. 改造保存方法，使其能处理两种模式 VVV
  void _saveDiary() async {
    // 为防止异步操作后 context 不可用，先获取 service
    final diaryService = context.read<DiaryService>();

    if (_tagController.text.trim().isNotEmpty) {
      setState(() => _tags.add(_tagController.text.trim()));
      _tagController.clear();
    }

    final text = _textController.text.trim();
    if (_imageFiles.isEmpty && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('至少需要一张图片或一些文字哦～')));
      return;
    }

    // 使用 try-catch 块来捕获并打印任何潜在的错误
    try {
      // VVV 2. 声明 entryId 变量 VVV
      String entryId;

      if (_isEditMode) {
        // --- 编辑模式 ---
        final updatedEntry = widget.entryToEdit!.copyWith(
          text: text,
          imagePaths: _imageFiles.map((f) => f.path).toList(),
          mood: _selectedMood,
          tags: _tags,
          latitude: _latitude,
          longitude: _longitude,
          address: _address,
          isPrivate: _isPrivate,
        );
        await diaryService.updateEntry(updatedEntry);
        // VVV 3. 获取已存在日记的ID VVV
        entryId = updatedEntry.diaryId;
      } else {
        // --- 新建模式 ---
        final newEntry = DiaryEntry(
          diaryId: '', // ID 为空，让 Service 自动生成
          text: text,
          imagePaths: _imageFiles.map((file) => file.path).toList(),
          date: widget.selectedDate!,
          creationTime: DateTime.now(),
          mood: _selectedMood,
          tags: _tags,
          latitude: _latitude,
          longitude: _longitude,
          address: _address,
          isPrivate: _isPrivate,
        );
        // VVV 4. 获取新创建日记的ID VVV
        // 注意：这里假设您的 addEntry 方法会返回创建后的 DiaryEntry 对象。
        // 如果没有，您需要修改 diaryService.dart 中的 addEntry 方法。
        final createdEntry = await diaryService.addEntry(newEntry);
        entryId = createdEntry.diaryId;
      }

      // 现在可以安全地调用AI分析了
      _runAiAnalysis(entryId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日记已保存！')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      // 如果发生任何错误，打印出来并显示提示
      print("保存日记时出错: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  void _initSpeech() async {
    var status = await Permission.microphone.status;
    if (status.isDenied) {
      await Permission.microphone.request();
    }
    _speechEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _toggleListening() {
    if (_pendingTidyUpSegment != null) {
      setState(() => _pendingTidyUpSegment = null);
    }
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _startListening() {
    if (!_speechEnabled) return;

    final cursorPosition = _textController.selection.baseOffset;
    final textBeforeCursor = _textController.text.substring(0, cursorPosition);
    final textAfterCursor = _textController.text.substring(cursorPosition);

    _speechToText.listen(
      onResult: (result) {
        if(mounted) {
          setState(() {
            _textController.text = textBeforeCursor + ' ' + result.recognizedWords + textAfterCursor;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: (textBeforeCursor + ' ' + result.recognizedWords).length),
            );
          });
        }
      },
      localeId: 'zh_CN',
    );
    if (mounted) setState(() => _isListening = true);
  }

  void _stopListening() async {
    await _speechToText.stop();

    final lastRecognizedText = _speechToText.lastRecognizedWords;
    if (lastRecognizedText.trim().isNotEmpty) {
      final fullText = _textController.text;
      final startIndex = fullText.lastIndexOf(lastRecognizedText);
      if (startIndex != -1) {
        setState(() {
          _pendingTidyUpSegment = _SpokenSegment(
            startIndex: startIndex,
            rawText: lastRecognizedText,
          );
        });
      }
    }
    if (mounted) setState(() => _isListening = false);
  }

  // --- VVV 新增：执行AI润色和弹出对比框的逻辑 VVV ---
  Future<void> _performTidyUp() async {
    if (_pendingTidyUpSegment == null) return;
    final segment = _pendingTidyUpSegment!;

    setState(() => _pendingTidyUpSegment = null);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    final geminiService = GeminiServiceLocal();
    final prompt = """你是一位语言润色大师。请将以下这段口语化的文本，优化成一段更加书面化、更连贯的文字。请注意：1. 忠实于原文的核心意思和情感。2. 修正语法，移除不必要的口头禅（如 '嗯', '啊', '那个'）。3. 不要添加任何原文没有的信息。4. 只返回优化后的文本。需要优化的口语文本如下:---${segment.rawText}""";

    final (processedText, _) = await geminiService.generateResponse([Content.text(prompt)], modelName: 'gemini-1.5-flash');

    Navigator.of(context).pop();

    if (processedText != null && !processedText.startsWith("ERROR:")) {
      final bool? shouldApply = await showDialog<bool>(
        context: context,
        builder: (_) => AiTidyUpComparisonDialog(originalText: segment.rawText, suggestedText: processedText),
      );

      if (shouldApply == true) {
        final originalFullText = _textController.text;
        final textBefore = originalFullText.substring(0, segment.startIndex);
        final textAfter = originalFullText.substring(segment.startIndex + segment.rawText.length);

        final newText = textBefore + processedText + textAfter;
        _textController.text = newText;
        _textController.selection = TextSelection.fromPosition(TextPosition(offset: (textBefore + processedText).length));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 润色失败，请稍后重试。')));
    }
  }



  // 文件位置: lib/add_diary_page.dart -> _AddDiaryPageState

  Future<void> _runAiAnalysis(String entryId) async {
    // 检查是否为私密，如果是，则跳过（根据我们之前的约定）
    if (_isPrivate) {
      print("日记为私密，跳过AI分析。");
      return;
    }

    final diaryService = context.read<DiaryService>();
    final geminiService = GeminiServiceLocal();

    // 延迟一秒，确保数据库写入完成
    await Future.delayed(const Duration(seconds: 1));
    final entry = await diaryService.getEntryById(entryId);

    if (entry == null || entry.text.isEmpty) {
      print("无法获取刚保存的日记或日记内容为空，跳过AI分析。");
      return;
    }

    final prompt = """
  请深度分析以下日记内容。请你扮演一个充满同理心、善于倾听的朋友。
  请严格按照以下JSON格式返回，不要有任何额外的解释或修饰:
  {
    "suggestedTitles": ["<标题1>", "<标题2>", "<标题3>"],
    "summary": "<大约50字的摘要>",
    "detectedEmotion": "<用一个描述性的词或短语总结文本中微妙的情绪>",
    "detectedThemes": ["<主题词1>", "<主题词2>", "<主题词3>"],
    "proactiveQuestion": "<基于日记内容，提出一个开放式的、能引导我深入思考的、友善的问题>"
  }
  日记内容如下:
  ---
  ${entry.text}
  """;

    final (responseText, _) = await geminiService.generateResponse([Content.text(prompt)], modelName: 'gemini-2.5-pro');

    if (responseText != null && responseText.isNotEmpty) {
      try {
        // 清洗可能存在的Markdown标记
        String cleanedJson = responseText.trim();
        if (cleanedJson.startsWith("```json")) {
          cleanedJson = cleanedJson.substring(7);
          if (cleanedJson.endsWith("```")) {
            cleanedJson = cleanedJson.substring(0, cleanedJson.length - 3);
          }
        }
        cleanedJson = cleanedJson.trim();

        final decodedJson = jsonDecode(cleanedJson);
        final newMetadata = AiMetadata.fromJson(decodedJson);
        final updatedEntry = entry.copyWith(aiMetadata: newMetadata);
        await diaryService.updateEntry(updatedEntry);

        print("AI分析已成功保存！");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI悄悄话已生成！'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        // VVVV 核心修改：如果解析失败，弹出错误提示 VVVV
        print("解析AI返回的JSON失败: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('生成AI悄悄话失败: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10), // 持续时间长一点方便查看
            ),
          );
        }
      }
    } else {
      // VVVV 核心修改：如果AI没有返回任何内容，也弹出提示 VVVV
      print("AI未能返回有效内容，无法生成悄悄话。");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI未能返回有效内容，无法生成悄悄话。'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultipleMedia(imageQuality: 80);

    if (pickedFiles.isNotEmpty) {
      setState(() {
        _imageFiles.addAll(pickedFiles.map((xfile) => File(xfile.path)));
      });
    }
  }

  Future<void> _selectLocationOnMap() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => MapSelectionPage(
          initialLocation: latlong.LatLng(_latitude ?? 39.9, _longitude ?? 116.4),
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _latitude = result['latitude'];
        _longitude = result['longitude'];
        _address = result['address'];
      });
    }
  }

  // VVV 4. Add method to get current location
  Future<void> _getCurrentLocation() async {
    setState(() => _isFetchingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取位置，因为权限被拒绝。')));
          setState(() => _isFetchingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('位置权限被永久拒绝，请在系统设置中开启。')));
        setState(() => _isFetchingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _address = "${place.locality}, ${place.street}";
        });
      }
    } catch (e) {
      print("获取位置失败: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取位置信息失败。')));
    } finally {
      setState(() => _isFetchingLocation = false);
    }
  }

  // VVV 5. Add a UI widget for the location selector
  Widget _buildLocationSelector() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: Text(_address ?? '添加位置'),
        subtitle: _address != null ? const Text('点击可重新选择位置') : const Text('点击从地图选择或自动定位'),
        onTap: _selectLocationOnMap, // VVV 主要点击行为改为打开地图
        trailing: _isFetchingLocation
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
          icon: const Icon(Icons.my_location),
          tooltip: '自动定位当前位置',
          onPressed: _getCurrentLocation, // VVV 按钮保留为自动定位
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '编辑日记' : '写下今天的故事'),
        actions: [
          // VVVV 核心修改：将开关移到这里 VVVV
          Tooltip(
            message: _isPrivate ? '设为公开日记' : '设为私密日记',
            child: Switch(
              value: _isPrivate,
              onChanged: (bool value) {
                setState(() {
                  _isPrivate = value;
                });
              },
              activeTrackColor: Colors.deepPurple.shade200,
              activeColor: Colors.deepPurple,
            ),
          ),
          IconButton(icon: const Icon(Icons.save_alt_outlined), tooltip: '保存', onPressed: _saveDiary),
          const SizedBox(width: 8), // 增加一点边距
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildMoodSelector(),
            const Divider(height: 32),
            _buildLocationSelector(),
            const Divider(height: 32),
            Text('添加标签', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildTagEditor(),
            const Divider(height: 32),

            // VVVV 核心修改：之前这里的 SwitchListTile 已被移除 VVVV

            _buildImageGrid(),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 10,
              onChanged: (text) { // 当用户手动输入时，自动隐藏润色建议
                if (_pendingTidyUpSegment != null) {
                  setState(() => _pendingTidyUpSegment = null);
                }
              },
              decoration: InputDecoration(
                hintText: '今天有什么新鲜事...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
                suffixIcon: _buildVoiceIcon(),
              ),
            ),
            _buildAiTidyUpCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceIcon() {
    return IconButton(
      icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
      color: _isListening ? Theme.of(context).colorScheme.primary : Colors.grey,
      tooltip: '语音输入',
      onPressed: _speechEnabled ? _toggleListening : null,
    );
  }

  // VVV 新增：构建AI建议卡片的辅助方法 VVV
  Widget _buildAiTidyUpCard() {
    if (_pendingTidyUpSegment == null) return const SizedBox.shrink();

    return FadeInUp(
      duration: const Duration(milliseconds: 300),
      child: Card(
        margin: const EdgeInsets.only(top: 12.0),
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: Theme.of(context).colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(child: Text('需要AI帮你整理刚才说的话吗？', style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer))),
              TextButton(onPressed: () => setState(() => _pendingTidyUpSegment = null), child: const Text('忽略')),
              FilledButton(onPressed: _performTidyUp, child: const Text('一键润色')),
            ],
          ),
        ),
      ),
    );
  }

  // Helper methods below are unchanged
  Widget _buildMoodSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今天心情如何?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _moodMap.entries.map((entry) {
              final moodCode = entry.key;
              final moodText = entry.value;
              final isSelected = _selectedMood == moodCode;
              IconData? moodIcon;

              // This switch statement assigns the correct icon for each mood
              switch (moodCode) {
                case '1': moodIcon = isSelected ? Icons.sentiment_very_satisfied : Icons.sentiment_very_satisfied_outlined; break;
                case '2': moodIcon = isSelected ? Icons.sentiment_satisfied : Icons.sentiment_satisfied_outlined; break;
                case '3': moodIcon = isSelected ? Icons.mood : Icons.mood_outlined; break;
                case '4': moodIcon = isSelected ? Icons.sentiment_neutral : Icons.sentiment_neutral_outlined; break;
                case '5': moodIcon = isSelected ? Icons.sentiment_dissatisfied : Icons.sentiment_dissatisfied_outlined; break;
                case '6': moodIcon = isSelected ? Icons.sentiment_dissatisfied : Icons.sentiment_dissatisfied_outlined; break;
                case '7': moodIcon = isSelected ? Icons.sentiment_very_dissatisfied : Icons.sentiment_very_dissatisfied_outlined; break;
                case '8': moodIcon = isSelected ? Icons.mood_bad : Icons.mood_bad_outlined; break;
                case '0': moodIcon = isSelected ? Icons.sick : Icons.sick_outlined; break;
              }

              return ChoiceChip(
                avatar: Icon( // The avatar property displays the icon
                  moodIcon,
                  color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
                ),
                label: Text(moodText),
                labelStyle: TextStyle(
                  color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).textTheme.bodyLarge?.color,
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedMood = selected ? moodCode : null;
                  });
                },
                selectedColor: Theme.of(context).colorScheme.primary,
                showCheckmark: false, // No need for a checkmark when the icon fills in
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTagEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: _tags.map((tag) {
            return Chip(
              label: Text(tag),
              onDeleted: () {
                setState(() {
                  _tags.remove(tag);
                });
              },
            );
          }).toList(),
        ),
        TextField(
          controller: _tagController,
          decoration: InputDecoration(
            hintText: '输入标签后按回车或空格...',
            prefixIcon: const Icon(Icons.label_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              setState(() {
                _tags.add(value.trim());
                _tagController.clear();
              });
            }
          },
          onChanged: (value) {
            if (value.endsWith(' ') || value.endsWith('，')) {
              final tag = value.trim().replaceAll('，', '');
              if (tag.isNotEmpty) {
                setState(() {
                  _tags.add(tag);
                  _tagController.clear();
                });
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _imageFiles.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        if (index == _imageFiles.length) {
          return GestureDetector(
            onTap: _pickImages,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: const Center(
                child: Icon(Icons.add_a_photo_outlined, size: 40, color: Colors.grey),
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_imageFiles[index], fit: BoxFit.cover),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _imageFiles.removeAt(index);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpokenSegment {
  final int startIndex;
  final String rawText;
  _SpokenSegment({required this.startIndex, required this.rawText});
}

class AiTidyUpComparisonDialog extends StatelessWidget {
  final String originalText;
  final String suggestedText;

  const AiTidyUpComparisonDialog({
    super.key,
    required this.originalText,
    required this.suggestedText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('AI 修改建议'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('原文:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Container(width: double.maxFinite, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.dividerColor)), child: Text(originalText)),
            const SizedBox(height: 16),
            Text('AI 建议:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Container(width: double.maxFinite, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withOpacity(0.3), borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.primary)), child: Text(suggestedText)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('应用修改')),
      ],
    );
  }
}