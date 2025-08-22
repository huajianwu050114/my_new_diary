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
import 'voice_diary_dialog.dart';
import 'package:collection/collection.dart';


class AddDiaryPage extends StatefulWidget {
  // VVV 1. 改造构造函数 VVV
  final DateTime? selectedDate;  // 用于新建日记
  final DiaryEntry? entryToEdit; // 用于编辑日记
  final String? initialText;

  const AddDiaryPage({
    super.key,
    this.selectedDate,
    this.entryToEdit,
    this.initialText,
  });

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
  DiaryEntry? _initialEntryState;

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
  List<String> _allTags = []; // 用于存储从数据库加载的所有历史标签
  List<String> _suggestedTags = []; // 用于在UI上显示给用户的推荐标签


  @override
  void initState() {
    super.initState();
    _loadAllTags();
    if (widget.entryToEdit != null) {
      _isEditMode = true;
      _populateFieldsFromEntry(widget.entryToEdit!);
      _initialEntryState = widget.entryToEdit!.copyWith(); // 保存一份副本
    } else {
      _initialEntryState = DiaryEntry.empty(date: widget.selectedDate ?? DateTime.now());
      if (widget.initialText != null) {
        _textController.text = widget.initialText!;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAndPromptForDraft();
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
  // 文件位置: lib/add_diary_page.dart -> _AddDiaryPageState

  // 文件位置: lib/add_diary_page.dart -> _AddDiaryPageState

  void _saveDiary() async {
    // 在所有异步操作和页面跳转之前，先获取所需的服务
    final diaryService = context.read<DiaryService>();
    final geminiService = GeminiServiceLocal(); // 直接实例化，因为它无状态

    if (_tagController.text.trim().isNotEmpty) {
      setState(() => _tags.add(_tagController.text.trim()));
      _tagController.clear();
    }

    final text = _textController.text.trim();
    if (_imageFiles.isEmpty && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('至少需要一张图片或一些文字哦～')));
      return;
    }

    try {
      String entryId;
      if (_isEditMode) {
        final updatedEntry = widget.entryToEdit!.copyWith(
          text: text, imagePaths: _imageFiles.map((f) => f.path).toList(),
          mood: _selectedMood, tags: _tags, latitude: _latitude,
          longitude: _longitude, address: _address, isPrivate: _isPrivate,
        );
        await diaryService.updateEntry(updatedEntry);
        entryId = updatedEntry.diaryId;
      } else {
        final newEntry = DiaryEntry(
          diaryId: '', text: text, imagePaths: _imageFiles.map((file) => file.path).toList(),
          date: widget.selectedDate!, creationTime: DateTime.now(),
          mood: _selectedMood, tags: _tags, latitude: _latitude,
          longitude: _longitude, address: _address, isPrivate: _isPrivate,
        );
        final createdEntry = await diaryService.addEntry(newEntry);
        entryId = createdEntry.diaryId;
      }
      await diaryService.deleteDraft();

      // 将获取到的服务作为参数传递给后台任务
      _runAiAnalysis(entryId, diaryService, geminiService);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日记已保存！')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("保存日记时出错: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  // file: lib/add_diary_page.dart -> _AddDiaryPageState class

  // VVVV 新增方法：加载所有历史标签并更新推荐列表 VVVV
  Future<void> _loadAllTags() async {
    if (!mounted) return;
    final diaryService = context.read<DiaryService>();
    final allTags = await diaryService.getAllUniqueTags();
    setState(() {
      _allTags = allTags;
      _updateSuggestedTags(); // 初始化推荐列表
    });
  }

  // VVVV 新增方法：根据当前已选标签，更新推荐列表 VVVV
  void _updateSuggestedTags() {
    // 推荐标签 = 所有历史标签 - 当前日记已选的标签
    _suggestedTags = _allTags.where((tag) => !_tags.contains(tag)).toList();
  }

  // VVVV 新增方法：当用户点击一个推荐标签时调用 VVVV
  void _addTagFromSuggestion(String tag) {
    setState(() {
      _tags.add(tag); // 将标签添加到当前日记
      _updateSuggestedTags(); // 更新推荐列表（移除刚被选择的标签）
    });
  }

  // VVVV 新增方法：当用户删除一个已选标签时调用 VVVV
  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
      _updateSuggestedTags(); // 更新推荐列表（将被删除的标签加回来）
    });
  }

  Future<void> _loadAndPromptForDraft() async {
    if (!mounted || _isEditMode) return;
    final diaryService = context.read<DiaryService>();
    final draft = await diaryService.loadDraft();

    if (draft != null && mounted) {
      final bool? load = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发现草稿'),
          content: const Text('你有一份上次未保存的草稿，要加载它吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('丢弃')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('加载')),
          ],
        ),
      );
      if (load == true && mounted) {
        _populateFieldsFromEntry(draft);
      } else {
        await diaryService.deleteDraft(); // 如果用户选择丢弃，就删除草稿
      }
    }
  }

  // VVVV 新增：从日记对象填充页面的方法 VVVV
  void _populateFieldsFromEntry(DiaryEntry entry) {
    setState(() {
      _textController.text = entry.text;
      _imageFiles.clear();
      _imageFiles.addAll(entry.imagePaths.map((path) => File(path)));
      _selectedMood = entry.mood;
      _tags.clear();
      _tags.addAll(entry.tags);
      _latitude = entry.latitude;
      _longitude = entry.longitude;
      _address = entry.address;
      _isPrivate = entry.isPrivate;
    });
  }

  // VVVV 新增：检查是否有未保存的更改 VVVV
  bool _hasUnsavedChanges() {
    if (_initialEntryState == null) return false;
    // 检查所有字段是否与初始状态不同
    return _textController.text.trim() != _initialEntryState!.text.trim() ||
        _imageFiles.length != _initialEntryState!.imagePaths.length ||
        !ListEquality().equals(_imageFiles.map((f) => f.path).toList(), _initialEntryState!.imagePaths) ||
        _selectedMood != _initialEntryState!.mood ||
        !ListEquality().equals(_tags, _initialEntryState!.tags) ||
        _isPrivate != _initialEntryState!.isPrivate;
  }

  // VVVV 新增：构建当前页面状态的日记对象 VVVV
  DiaryEntry _getCurrentEntry() {
    return DiaryEntry(
      diaryId: _isEditMode ? widget.entryToEdit!.diaryId : '',
      text: _textController.text.trim(),
      date: _isEditMode ? widget.entryToEdit!.date : widget.selectedDate!,
      creationTime: _isEditMode ? widget.entryToEdit!.creationTime : DateTime.now(),
      imagePaths: _imageFiles.map((f) => f.path).toList(),
      mood: _selectedMood,
      tags: _tags,
      latitude: _latitude,
      longitude: _longitude,
      address: _address,
      isPrivate: _isPrivate,
    );
  }

  // VVVV 新增：处理返回操作的核心逻辑 VVVV
  Future<bool> _onWillPop() async {
    if (_hasUnsavedChanges()) {
      final result = await showDialog<ExitAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('有未保存的内容'),
          content: const Text('你要如何处理当前的更改？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(ExitAction.cancel),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ExitAction.discard),
              child: const Text('直接退出'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(ExitAction.saveDraft),
              child: const Text('保存草稿'),
            ),
          ],
        ),
      );

      if (!mounted) return false;

      final diaryService = context.read<DiaryService>();
      switch (result) {
        case ExitAction.saveDraft:
          await diaryService.saveDraft(_getCurrentEntry());
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('草稿已保存')));
          return true; // 允许退出
        case ExitAction.discard:
          await diaryService.deleteDraft(); // 如果放弃，也删除旧草稿
          return true; // 允许退出
        case ExitAction.cancel:
        default:
          return false; // 不允许退出
      }
    }
    // 如果没有更改，直接允许退出
    return true;
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

  Future<void> _handleVoiceInput() async {
    // 步骤 A: 打开语音输入框，等待AI润色后的文本返回
    final String? polishedText = await showDialog<String>(
      context: context,
      builder: (context) => const VoiceInputDialog(),
    );

    if (!mounted || polishedText == null) return;

    if (polishedText.startsWith('语音处理失败:')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(polishedText), backgroundColor: Colors.red));
      return;
    }

    // 步骤 B: 打开一个新的对话框，让用户编辑和确认文本
    final String? finalText = await showDialog<String>(
      context: context,
      builder: (context) => AiCorrectionDialog(initialText: polishedText),
    );

    if (!mounted || finalText == null) return;

    // 步骤 C: 将最终确认的文本插入到主输入框的光标位置
    final text = _textController.text;
    final selection = _textController.selection;
    final newText = text.replaceRange(selection.start, selection.end, finalText);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + finalText.length),
    );
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

    final (processedText, _) = await geminiService.generateResponse([Content.text(prompt)], modelName: 'gemini-2.5-flash');

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



  // 文件位置: libs/add_diary_page.dart -> _AddDiaryPageState

  // 文件位置: lib/add_diary_page.dart -> _AddDiaryPageState

// VVVV 核心修改 1: 修改方法签名，接收传递进来的服务，不再依赖 context VVVV
  Future<void> _runAiAnalysis(String entryId, DiaryService diaryService, GeminiServiceLocal geminiService) async {
    if (_isPrivate) {
      print("日记为私密，跳过AI分析。");
      return;
    }

    // 延迟一秒，确保数据库写入操作完成
    await Future.delayed(const Duration(seconds: 1));
    final entry = await diaryService.getEntryById(entryId);
    if (entry == null || entry.text.isEmpty) {
      print("无法获取刚保存的日记或日记内容为空，跳过AI分析。");
      return;
    }

    String finalPrompt;
    const String separator = "---AI_SAMPLE_ANSWER---";

    if (entry.text.contains(separator)) {
      // --- 这是针对“AI灵感”日记的专属指令 ---
      final contentWithoutSample = entry.text.split(separator)[0].trim();
      final parts = contentWithoutSample.split('\n---\n');
      final aiQuestion = parts.length > 0 ? parts[0].replaceAll('> ## AI 灵感:', '').replaceAll('>', '').trim() : '';
      final userAnswer = parts.length > 1 ? parts[1].trim() : contentWithoutSample;

      if (userAnswer.isEmpty) { return; }

      finalPrompt = """
你是一位充满同理心、善于倾听和点评的朋友。接下来我会为你提供一个背景“写作灵感”和我对这个灵感的“我的回答”。

你的任务是：请深度分析“我的回答”这部分内容，而不是分析“写作灵感”那个问题。你需要根据我的回答，来点评我的想法和状态。

背景“写作灵感”如下:
"$aiQuestion"

“我的回答”如下:
"$userAnswer"

请严格按照以下JSON格式返回你对“我的回答”的分析，不要有任何额外的解释或修饰:
{
  "suggestedTitles": ["<为我的回答取一个标题1>", "<标题2>", "<标题3>"],
  "summary": "<对我回答的大约50字的摘要>",
  "detectedEmotion": "<总结我回答中体现的微妙情绪>",
  "detectedThemes": ["<我回答中的主题词1>", "<主题词2>", "<主题词3>"],
  "proactiveQuestion": "<基于我的回答，提出一个能引导我深入思考的、友善的问题>"
}
""";
    } else {
      // --- 这是针对普通日记的原始指令 ---
      finalPrompt = """
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
    }

    final (responseText, _) = await geminiService.generateResponse([Content.text(finalPrompt)], modelName: 'gemini-2.5-pro');

    if (responseText != null && responseText.isNotEmpty) {
      try {
        String extractedJson;
        final startIndex = responseText.indexOf('{');
        final endIndex = responseText.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          extractedJson = responseText.substring(startIndex, endIndex + 1);
        } else {
          throw FormatException("AI返回的内容中未找到有效的JSON对象。");
        }
        final decodedJson = jsonDecode(extractedJson);
        final newMetadata = AiMetadata.fromJson(decodedJson);
        final updatedEntry = entry.copyWith(aiMetadata: newMetadata);
        await diaryService.updateEntry(updatedEntry);
        print("AI分析已成功保存！");
      } catch (e) {
        print("解析或保存AI分析失败: $e");
      }
    } else {
      print("AI未能返回有效内容，无法生成悄悄话。");
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

  // 文件位置: libs/add_diary_page.dart -> _AddDiaryPageState

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          appBar: AppBar(
        title: Text(_isEditMode ? '编辑日记' : '写下今天的故事'),
        actions: [
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
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        // VVVV 主要修改区域 VVVV
        child: Column(
          children: [
            // --- 1. 核心编辑区 (已移到顶部) ---
            _buildImageGrid(),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 10,
              onChanged: (text) {
                if (_pendingTidyUpSegment != null) {
                  setState(() => _pendingTidyUpSegment = null);
                }
              },
              decoration: InputDecoration(
                hintText: '今天有什么新鲜事...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic_outlined),
                  tooltip: '语音输入',
                  onPressed: _handleVoiceInput,
                ),
              ),
            ),
            _buildAiTidyUpCard(), // 这个AI润色卡片紧随文本框

            const Divider(height: 32),

            // --- 2. 附加信息区 (已移到下方) ---
            _buildMoodSelector(),
            const Divider(height: 32),
            _buildLocationSelector(),
            const Divider(height: 32),
            Text('添加标签', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildTagEditor(),
          ],
        ),
        // ^^^^ 主要修改区域结束 ^^^^
      ),
    )
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

  // file: lib/add_diary_page.dart -> _AddDiaryPageState class

  Widget _buildTagEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- 1. 当前已选标签 ---
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: _tags.map((tag) {
            return Chip(
              label: Text(tag),
              onDeleted: () {
                // 调用新的移除方法
                _removeTag(tag);
              },
            );
          }).toList(),
        ),

        // --- 2. 标签输入框 ---
        TextField(
          controller: _tagController,
          decoration: InputDecoration(
            hintText: '输入标签后按回车或空格...',
            prefixIcon: const Icon(Icons.label_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (value) {
            final tag = value.trim();
            if (tag.isNotEmpty && !_tags.contains(tag)) {
              setState(() {
                _tags.add(tag);
                _tagController.clear();
                _updateSuggestedTags(); // 更新推荐
              });
            } else {
              _tagController.clear(); // 如果是空或重复，也清空输入框
            }
          },
          onChanged: (value) {
            if (value.endsWith(' ') || value.endsWith('，')) {
              final tag = value.trim().replaceAll('，', '');
              if (tag.isNotEmpty && !_tags.contains(tag)) {
                setState(() {
                  _tags.add(tag);
                  _tagController.clear();
                  _updateSuggestedTags(); // 更新推荐
                });
              } else if (tag.isNotEmpty) {
                _tagController.clear(); // 如果是重复，也清空输入框
              }
            }
          },
        ),

        // --- 3. 历史标签推荐 (仅在有推荐时显示) ---
        if (_suggestedTags.isNotEmpty) ...[
          const Divider(height: 32),
          Text('历史标签', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: _suggestedTags.map((tag) {
              return ActionChip(
                label: Text(tag),
                avatar: const Icon(Icons.add_circle_outline, size: 16),
                onPressed: () {
                  // 调用新的添加方法
                  _addTagFromSuggestion(tag);
                },
              );
            }).toList(),
          ),
        ]
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
class AiCorrectionDialog extends StatefulWidget {
  final String initialText;
  const AiCorrectionDialog({super.key, required this.initialText});

  @override
  State<AiCorrectionDialog> createState() => _AiCorrectionDialogState();
}

class _AiCorrectionDialogState extends State<AiCorrectionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认AI转换结果'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // 取消，返回 null
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text), // 确认，返回编辑后的文本
          child: const Text('确认并插入'),
        ),
      ],
    );
  }
}

enum ExitAction { saveDraft, discard, cancel }

