// file: add_diary_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart'; // 导入 provider
import 'diary_service.dart';

class AddDiaryPage extends StatefulWidget {
  final DateTime selectedDate;

  const AddDiaryPage({super.key, required this.selectedDate});

  @override
  State<AddDiaryPage> createState() => _AddDiaryPageState();
}

class _AddDiaryPageState extends State<AddDiaryPage> {
  final TextEditingController _textController = TextEditingController();
  File? _imageFile;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  void _saveDiary() async {
    if (_imageFile == null && _textController.text.trim().isEmpty) {
      // 如果图片和文字都为空，提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要一张图片或一些文字哦～')),
      );
      return;
    }

    final newEntry = DiaryEntry(
      filePath: '', // filePath 将在 service 中生成，这里留空
      imagePath: _imageFile?.path,
      text: _textController.text,
      date: widget.selectedDate,
      creationTime: DateTime.now(),
    );

    // <-- 使用 context.read<DiaryService>() 来调用方法
    // 因为这只是一个单次操作，不需要监听变化
    await context.read<DiaryService>().addEntry(newEntry);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('写下今天的故事'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            tooltip: '保存',
            onPressed: _saveDiary,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _imageFile != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_imageFile!, fit: BoxFit.cover),
                  )
                      : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, size: 50, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('点击选择封面照片', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _textController,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: '今天有什么新鲜事...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}