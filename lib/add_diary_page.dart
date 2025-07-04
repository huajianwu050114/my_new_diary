import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'diary_service.dart'; // 导入我们的日记服务和数据模型

class AddDiaryPage extends StatefulWidget {
  final DateTime selectedDate;

  const AddDiaryPage({super.key, required this.selectedDate});

  @override
  State<AddDiaryPage> createState() => _AddDiaryPageState();
}

class _AddDiaryPageState extends State<AddDiaryPage> {
  // --- 把所有变量和方法都放在 build 方法之前 ---

  final DiaryService _diaryService = DiaryService();
  final TextEditingController _textController = TextEditingController();
  File? _imageFile;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  void _saveDiary() async {
    // 在 _saveDiary 方法里
    final newEntry = DiaryEntry(
      filePath: '',
      imagePath: _imageFile?.path,
      text: _textController.text.isNotEmpty ? _textController.text : "记录今天的美好...",
      date: widget.selectedDate,
      creationTime: DateTime.now(), // <-- 在这里记录下当前的精确时间
    );

    await _diaryService.addEntry(newEntry);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // --- build 方法是类的最后一个部分 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('写下今天的故事'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveDiary, // 现在可以正确找到了
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage, // 现在可以正确找到了
                child: Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: _imageFile != null // 现在可以正确找到了
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_imageFile!, fit: BoxFit.cover),
                  )
                      : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 50, color: Colors.grey),
                        Text('点击选择封面照片', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _textController, // 现在可以正确找到了
                maxLines: 8,
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