// file: lib/edit_diary_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'diary_service.dart';
import '';

class EditDiaryPage extends StatefulWidget {
  final DiaryEntry entry;
  const EditDiaryPage({super.key, required this.entry});

  @override
  State<EditDiaryPage> createState() => _EditDiaryPageState();
}

class _EditDiaryPageState extends State<EditDiaryPage> {
  // --- State Variables ---
  late TextEditingController _textController;
  late List<String> _existingImageUrls; // 存储已有的云端图片URL
  final List<File> _newImageFiles = []; // 存储新选择的本地图片文件
  String? _selectedMood;
  late List<String> _tags;
  // ... 其他状态变量
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // 使用传入的日记数据初始化所有状态
    _textController = TextEditingController(text: widget.entry.text);
    _existingImageUrls = List.from(widget.entry.imagePaths);
    _selectedMood = widget.entry.mood;
    _tags = List.from(widget.entry.tags);
    // ... 初始化其他字段
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// 保存编辑后的日记
  void _saveDiaryChanges() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    // 创建一个包含更新后数据的 DiaryEntry 对象
    final updatedData = DiaryEntry(
      diaryId: widget.entry.diaryId, // 保持原始ID不变
      authorId: widget.entry.authorId,
      text: _textController.text.trim(),
      imagePaths: [], // imagePaths 将在 service 中处理
      date: widget.entry.date,
      creationTime: widget.entry.creationTime, // 通常不更新创建时间
      mood: _selectedMood,
      tags: _tags,
      // ... 其他字段
    );

    try {
      // 调用新的 updateEntry 方法
      final DiaryService diaryService = context.read<DiaryService>();
      await diaryService.updateEntry(
          widget.entry, updatedData, _newImageFiles, _existingImageUrls);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('日记已更新！')));
        // 返回到详情页，并传递更新后的日记对象（可选）
        Navigator.of(context).pop(updatedData);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// 选择新图片
  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultipleMedia();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _newImageFiles.addAll(pickedFiles.map((xfile) => File(xfile.path)));
      });
    }
  }

  /// 构建图片网格，能同时显示已有的网络图和新选的本地图
  Widget _buildImageGrid() {
    final totalImages = _existingImageUrls.length + _newImageFiles.length;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalImages + 1, // +1 for the "add" button
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        if (index == totalImages) {
          // Add button
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

        Widget imageWidget;
        VoidCallback onDelete;

        if (index < _existingImageUrls.length) {
          // Display existing network images
          final imageUrl = _existingImageUrls[index];
          imageWidget = CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          );
          onDelete = () {
            setState(() {
              _existingImageUrls.removeAt(index);
            });
          };
        } else {
          // Display new local images
          final imageFile = _newImageFiles[index - _existingImageUrls.length];
          imageWidget = Image.file(imageFile, fit: BoxFit.cover);
          onDelete = () {
            setState(() {
              _newImageFiles.removeAt(index - _existingImageUrls.length);
            });
          };
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageWidget,
            ),
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: onDelete,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑日记'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_alt_outlined),
              tooltip: '保存更改',
              onPressed: _saveDiaryChanges,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 这里可以复用 AddDiaryPage 的 MoodSelector, TagEditor 等UI组件
            // 为简化，我们先只放核心的图片和文本编辑
            const Text("图片"),
            const SizedBox(height: 8),
            _buildImageGrid(),
            const SizedBox(height: 16),
            const Text("内容"),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '今天有什么新鲜事...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}