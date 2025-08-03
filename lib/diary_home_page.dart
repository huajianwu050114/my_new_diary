// 文件: lib/diary_home_page.dart (已适配混合存储模式)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'add_diary_page.dart';
import 'diary_service.dart';
import 'diary_view_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p; // VVV 1. 添加 path 包的导入 VVV
import 'dart:io';

class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key});

  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends State<DiaryHomePage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  // VVV 2. 新增这个辅助方法，用于获取本地图片的完整路径 VVV
  Future<String> _getLocalImagePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'diary_images', fileName);
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }
  }

  void _showDeleteConfirmDialog(DiaryEntry entry) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('你确定要把这篇日记移入回收站吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ],
        );
      },
    );
    if (shouldDelete == true && mounted) {
      await context.read<DiaryService>().moveEntryToTrash(entry.diaryId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${DateFormat.yMd().format(entry.date)} 的日记已移入回收站')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // VVV 3. 在 build 方法顶部获取 DiaryService 实例 VVV
    final diaryService = context.watch<DiaryService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AddDiaryPage(selectedDate: _selectedDay!),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<DiaryEntry>>(
        stream: diaryService.getAllEntriesSortedStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载数据失败: ${snapshot.error}'));
          }

          final allEntries = snapshot.data ?? [];

          final selectedDayEntries = allEntries.where((entry) {
            return isSameDay(entry.date, _selectedDay);
          }).toList();

          return Column(
            children: [
              // --- 日历部分 (无需修改) ---
              Container(
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.4 : 0.1),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TableCalendar<DiaryEntry>(
                  locale: 'zh_CN',
                  firstDay: DateTime.utc(2022, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  calendarFormat: _calendarFormat,
                  eventLoader: (day) {
                    return allEntries.where((entry) => isSameDay(entry.date, day)).toList();
                  },
                  onDaySelected: _onDaySelected,
                  onFormatChanged: (format) {
                    if (_calendarFormat != format) {
                      setState(() => _calendarFormat = format);
                    }
                  },
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
                  },
                ),
              ),
              const SizedBox(height: 8.0),

              // --- 日记列表部分 ---
              Expanded(
                child: selectedDayEntries.isEmpty
                    ? const Center(child: Text('今天没有日记，快来写一篇吧！'))
                    : ListView.builder(
                  itemCount: selectedDayEntries.length,
                  itemBuilder: (context, index) {
                    final entry = selectedDayEntries[index];
                    return Slidable(
                      key: Key(entry.diaryId),
                      endActionPane: ActionPane(
                        motion: const StretchMotion(),
                        children: [
                          SlidableAction(
                            onPressed: (context) => _showDeleteConfirmDialog(entry),
                            backgroundColor: const Color(0xFFFE4A49),
                            foregroundColor: Colors.white,
                            icon: Icons.delete,
                            label: '删除',
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => DiaryViewPage(entry: entry),
                            ),
                          );
                        },
                        child: Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // --- VVV 4. 这里的图片显示逻辑是核心修改点 VVV ---
                              if (entry.imagePaths.isNotEmpty)
                                diaryService.currentMode == StorageMode.cloud
                                    ? CachedNetworkImage( // 云端模式
                                  imageUrl: entry.imagePaths.first,
                                  width: double.infinity,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    height: 150,
                                    color: Colors.grey[200],
                                    child: const Center(child: CircularProgressIndicator()),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    height: 150,
                                    color: Colors.grey[200],
                                    child: const Center(child: Icon(Icons.broken_image)),
                                  ),
                                )
                                    : FutureBuilder<String>( // 本地模式
                                  future: _getLocalImagePath(entry.imagePaths.first),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      return Image.file(
                                        File(snapshot.data!),
                                        width: double.infinity,
                                        height: 150,
                                        fit: BoxFit.cover,
                                      );
                                    }
                                    return Container(
                                      height: 150,
                                      color: Colors.grey[200],
                                      child: const Center(child: CircularProgressIndicator()),
                                    );
                                  },
                                ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                                      style: theme.textTheme.bodyMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8.0),
                                    Text(
                                      DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}