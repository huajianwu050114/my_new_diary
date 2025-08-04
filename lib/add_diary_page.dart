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

  @override
  void initState() {
    super.initState();
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
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _tagController.dispose();
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
        );
        await diaryService.updateEntry(updatedEntry);
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
        );
        await diaryService.addEntry(newEntry);
      }

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
          IconButton(icon: const Icon(Icons.save_alt_outlined), tooltip: '保存', onPressed: _saveDiary),
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