// file: lib/add_diary_page.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:my_new_diary/diary_model.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'diary_service.dart';
import 'map_selection_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' as latlong;

class AddDiaryPage extends StatefulWidget {
  final DateTime? selectedDate;
  final DiaryEntry? entryToEdit;

  const AddDiaryPage({super.key, this.selectedDate, this.entryToEdit});

  @override
  State<AddDiaryPage> createState() => _AddDiaryPageState();
}

class _AddDiaryPageState extends State<AddDiaryPage> {
  // --- STATE VARIABLES ---
  late QuillController _controller;
  final FocusNode _focusNode = FocusNode();

  // Metadata state variables
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

  bool _isEditMode = false;

  // --- INITIALIZATION ---
  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  void _loadContent() {
    Document doc;
    if (widget.entryToEdit != null) {
      _isEditMode = true;
      final entry = widget.entryToEdit!;

      _selectedMood = entry.mood;
      _tags.addAll(entry.tags);
      _latitude = entry.latitude;
      _longitude = entry.longitude;
      _address = entry.address;

      try {
        doc = Document.fromJson(jsonDecode(entry.text));
      } catch (e) {
        doc = Document()..insert(0, entry.text);
      }
    } else {
      doc = Document();
    }
    _controller = QuillController(
        document: doc, selection: const TextSelection.collapsed(offset: 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _tagController.dispose();
    super.dispose();
  }

  // --- CORE LOGIC ---
  void _saveDiary() async {
    final diaryService = context.read<DiaryService>();
    final String richTextJson = jsonEncode(_controller.document.toDelta().toJson());

    if (_controller.document.isEmpty()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('至少需要写一些内容哦～')));
      return;
    }

    try {
      if (_isEditMode) {
        final updatedEntry = widget.entryToEdit!.copyWith(
          text: richTextJson,
          mood: _selectedMood,
          tags: _tags,
          latitude: _latitude,
          longitude: _longitude,
          address: _address,
        );
        await diaryService.updateEntry(updatedEntry);
      } else {
        final newEntry = DiaryEntry(
          diaryId: '',
          text: richTextJson,
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
      print("保存日记时出错: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  // --- METADATA BOTTOM SHEET ---
  void _showMetadataSheet() {
    // Tapping the button unfocuses the editor to prevent keyboard overlap
    _focusNode.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (_, scrollController) {
                return Container(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Text('日记详情与设置', style: Theme.of(context).textTheme.headlineSmall),
                      const Divider(height: 32),
                      _buildMoodSelector(setSheetState),
                      const Divider(height: 32),
                      _buildLocationSelector(setSheetState),
                      const Divider(height: 32),
                      Text('添加标签', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _buildTagEditor(setSheetState),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- UI LAYOUT (BUILD METHOD) ---
  @override
  Widget build(BuildContext context) {
    // Don't show the UI until the controller is ready.


    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '编辑日记' : '写下今天的故事'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: '日记设置',
            onPressed: _showMetadataSheet,
          ),
          IconButton(
              icon: const Icon(Icons.save_alt_outlined),
              tooltip: '保存',
              onPressed: _saveDiary),
        ],
      ),
      body: Column(
        children: [
          QuillToolbar.simple(
            configurations: QuillSimpleToolbarConfigurations(
              controller: _controller,
              sharedConfigurations: const QuillSharedConfigurations(
                locale: Locale('zh'),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: QuillEditor(
              // Both focusNode and configurations are required
              focusNode: _focusNode,
              scrollController: ScrollController(),

              configurations: QuillEditorConfigurations(
                controller: _controller,
                sharedConfigurations: const QuillSharedConfigurations(
                  locale: Locale('zh'),
                ),
                padding: const EdgeInsets.all(16),
                placeholder: '今天有什么新鲜事...',
                readOnly: false,
                autoFocus: true,
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- UI HELPER WIDGETS ---
  Widget _buildMoodSelector(StateSetter setSheetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('今天心情如何?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: _moodMap.entries.map((entry) {
            final moodCode = entry.key;
            final isSelected = _selectedMood == moodCode;
            IconData? moodIcon;
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
              avatar: Icon(moodIcon, color: isSelected ? Theme.of(context).colorScheme.onPrimary : null),
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (selected) {
                setSheetState(() {
                  _selectedMood = selected ? moodCode : null;
                });
              },
              selectedColor: Theme.of(context).colorScheme.primary,
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLocationSelector(StateSetter setSheetState) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: Text(_address ?? '添加位置'),
        onTap: () => _selectLocationOnMap(setSheetState),
        trailing: _isFetchingLocation
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
          icon: const Icon(Icons.my_location),
          tooltip: '自动定位当前位置',
          onPressed: () => _getCurrentLocation(setSheetState),
        ),
      ),
    );
  }

  Widget _buildTagEditor(StateSetter setSheetState) {
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
                setSheetState(() {
                  _tags.remove(tag);
                });
              },
            );
          }).toList(),
        ),
        TextField(
          controller: _tagController,
          decoration: InputDecoration(
            hintText: '输入标签后按回车...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty && !_tags.contains(value.trim())) {
              setSheetState(() {
                _tags.add(value.trim());
                _tagController.clear();
              });
            }
          },
        ),
      ],
    );
  }

  Future<void> _getCurrentLocation(StateSetter setSheetState) async {
    setSheetState(() => _isFetchingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取位置，因为权限被拒绝。')));
        setSheetState(() => _isFetchingLocation = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setSheetState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _address = "${place.locality}, ${place.street}";
        });
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取位置信息失败。')));
    } finally {
      if (mounted) {
        setSheetState(() => _isFetchingLocation = false);
      }
    }
  }

  Future<void> _selectLocationOnMap(StateSetter setSheetState) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => MapSelectionPage(
          initialLocation: latlong.LatLng(_latitude ?? 39.9, _longitude ?? 116.4),
        ),
      ),
    );
    if (result != null) {
      setSheetState(() {
        _latitude = result['latitude'];
        _longitude = result['longitude'];
        _address = result['address'];
      });
    }
  }
}