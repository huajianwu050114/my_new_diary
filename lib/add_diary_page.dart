// file: lib/add_diary_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart'; // VVV 1. Import new packages
import 'package:geocoding/geocoding.dart';
import 'diary_service.dart';
import 'map_selection_page.dart';
import 'package:latlong2/latlong.dart' as latlong;// flutter_map 使用 latlong2 包来处理坐标

class AddDiaryPage extends StatefulWidget {
  final DateTime selectedDate;
  const AddDiaryPage({super.key, required this.selectedDate});

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

  // VVV 2. Add state variables for location
  double? _latitude;
  double? _longitude;
  String? _address;
  bool _isFetchingLocation = false;

  bool _isSaving = false;

  @override
  void dispose() {
    _textController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  // VVV 3. Update save logic to include location
  void _saveDiary() async {
    // --- 诊断代码 ---
    print("DEBUG: 1. 保存按钮被点击。");

    if (_isSaving) {
      print("DEBUG: 2. 检测到正在保存，操作被阻止。");
      return;
    }

    setState(() {
      _isSaving = true;
    });
    print("DEBUG: 3. UI状态更新为“保存中...”。");

    // ... (其余检查逻辑保持不变)
    if (_tagController.text.trim().isNotEmpty) {
      _tags.add(_tagController.text.trim());
      _tagController.clear();
    }
    final text = _textController.text.trim();
    if (_imageFiles.isEmpty && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('至少需要一张图片或一些文字哦～')));
      setState(() {
        _isSaving = false;
      });
      print("DEBUG: 内容为空，操作已终止。");
      return;
    }

    final newEntry = DiaryEntry(
      diaryId: '',
      authorId: '',
      text: text,
      imagePaths: [],
      date: widget.selectedDate,
      creationTime: DateTime.now(),
      mood: _selectedMood,
      tags: _tags,
      latitude: _latitude,
      longitude: _longitude,
      address: _address,
    );

    try {
      print("DEBUG: 4. 即将调用 diaryService.addEntry 方法...");

      await context.read<DiaryService>().addEntry(newEntry, _imageFiles);

      // --- 这是最关键的诊断点 ---
      print("DEBUG: 5. diaryService.addEntry 方法执行完毕！");

      if (mounted) {
        print("DEBUG: 6. 页面仍然挂载，准备跳转...");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日记已保存！')));
        Navigator.of(context).pop();
        print("DEBUG: 7. 页面已跳转。");
      } else {
        print("DEBUG: 6. 警告：页面在保存完成后已被卸载。");
      }
    } catch (e) {
      print("DEBUG: X. 保存过程中捕获到错误: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      print("DEBUG: 8. finally代码块执行，准备重置UI状态。");
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
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
        title: const Text('写下今天的故事'),
        actions: [
          // --- 核心修正点 3: 根据 _isSaving 状态显示不同按钮 ---
          if (_isSaving)
          // 如果正在保存，显示一个加载动画
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
              ),
            )
          else
          // 如果未在保存，显示保存按钮
            IconButton(
              icon: const Icon(Icons.save_alt_outlined),
              tooltip: '保存',
              onPressed: _saveDiary,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ... _buildMoodSelector remains unchanged ...
            _buildMoodSelector(),
            const Divider(height: 32),
            _buildLocationSelector(), // VVV 6. Add the location widget to the layout
            const Divider(height: 32),
            // ... _buildTagEditor remains unchanged ...
            Text('添加标签', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildTagEditor(),
            const Divider(height: 32),
            // ... _buildImageGrid remains unchanged ...
            _buildImageGrid(),
            const SizedBox(height: 16),
            // ... TextField remains unchanged ...
            TextField(
              controller: _textController,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '今天有什么新鲜事...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
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