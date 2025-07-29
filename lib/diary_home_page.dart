// 文件: lib/diary_home_page.dart (已适配云端数据)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- 新增导入

import 'add_diary_page.dart';
import 'diary_service.dart';
import 'diary_view_page.dart';

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

  // onDaySelected 方法保持不变
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }
  }

  // --- 核心修正点 1: 更新删除对话框的逻辑 ---
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
      // 使用 diaryId 替代 filePath
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
      // --- 核心修正点 2: 使用一个顶级的 StreamBuilder 来获取所有日记数据 ---
      body: StreamBuilder<List<DiaryEntry>>(
        stream: context.watch<DiaryService>().getAllEntriesSortedStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载数据失败: ${snapshot.error}'));
          }

          final allEntries = snapshot.data ?? [];

          // 筛选出当天选中的日记
          final selectedDayEntries = allEntries.where((entry) {
            return isSameDay(entry.date, _selectedDay);
          }).toList();

          return Column(
            children: [
              // --- 日历部分 ---
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
                  // --- 核心修正点 3: 更新日历事件加载器 ---
                  eventLoader: (day) {
                    // 从所有日记中筛选出对应日期的日记作为事件标记
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
                  // ... 日历样式部分保持不变 ...
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
                      // --- 核心修正点 4: 使用 diaryId 作为 Key ---
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
                              if (entry.imagePaths.isNotEmpty)
                              // --- 核心修正点 5: 使用 CachedNetworkImage 加载网络图片 ---
                                CachedNetworkImage(
                                  imageUrl: entry.imagePaths.first,
                                  width: double.infinity,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    height: 150,
                                    color: Colors.grey[200],
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    height: 150,
                                    color: Colors.grey[200],
                                    child: Center(child: Icon(Icons.broken_image)),
                                  ),
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