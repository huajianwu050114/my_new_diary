// 文件: libs/comfort_zone_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:intl/intl.dart';

import 'diary_model.dart';
import 'diary_service.dart';
import 'favorites_provider.dart';
import 'ai_chat_page.dart';
import 'diary_view_page.dart';

class ComfortZonePage extends StatefulWidget {
  const ComfortZonePage({super.key});

  @override
  State<ComfortZonePage> createState() => _ComfortZonePageState();
}

class _ComfortZonePageState extends State<ComfortZonePage> {
  Future<List<DiaryEntry>>? _happyEntriesFuture;

  @override
  void initState() {
    super.initState();
    // 页面加载时，开始异步获取开心日记
    _happyEntriesFuture = context.read<DiaryService>().getHappyEntries();
  }

  // 启动一个带有特殊安慰指令的AI聊天
  // 文件位置: libs/comfort_zone_page.dart -> _ComfortZonePageState class

// 启动一个带有特殊安慰指令的AI聊天
  void _startComfortingChat() async { // 1. 将方法标记为 async
    // 2. 检查页面是否还存在，这是异步操作的好习惯
    if (!mounted) return;

    // 3. 调用我们新建的 service 方法来获取或创建对话
    final diaryService = context.read<DiaryService>();
    final comfortEntry = await diaryService.getOrCreateComfortChatEntry();

    // 4. 再次检查页面是否存在，然后跳转
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => AiChatPage(entry: comfortEntry),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final favoritesProvider = context.watch<FavoritesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('温柔乡'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. 与AI聊一聊 按钮
          ElevatedButton.icon(
            icon: const Icon(Icons.psychology_outlined),
            label: const Text('和朋友聊一聊'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
            onPressed: _startComfortingChat,
          ),
          const SizedBox(height: 24),

          // 2. 重温美好瞬间 板块
          Text('重温美好瞬间', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          _buildHappyMemoriesSection(),
          const SizedBox(height: 24),

          // 3. 收藏的慰藉 板块
          Text('来自收藏的慰藉', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          _buildFavoritesSection(favoritesProvider.favorites),
        ],
      ),
    );
  }

  Widget _buildHappyMemoriesSection() {
    return FutureBuilder<List<DiaryEntry>>(
      future: _happyEntriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Card(child: ListTile(title: Text('暂时没有找到开心的回忆...')));
        }
        final happyEntries = snapshot.data!;
        return SizedBox(
          height: 150, // 为横向滚动的列表设置一个固定高度
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: happyEntries.length,
            itemBuilder: (context, index) {
              final entry = happyEntries[index];
              return _buildMemoryCard(entry);
            },
          ),
        );
      },
    );
  }

  Widget _buildMemoryCard(DiaryEntry entry) {
    return SizedBox(
      width: 250,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiaryViewPage(entry: entry))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.imagePaths.isNotEmpty)
                Expanded(
                  child: Image.file(
                    File(entry.imagePaths.first),
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  entry.text,
                  maxLines: entry.imagePaths.isNotEmpty ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesSection(List<FavoriteQuote> favorites) {
    if (favorites.isEmpty) {
      return const Card(child: ListTile(title: Text('还没有收藏任何句子...')));
    }
    // 为了不过多占据屏幕，这里只显示最多3条收藏
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: favorites.length > 3 ? 3 : favorites.length,
      itemBuilder: (context, index) {
        final favorite = favorites[index];
        return Card(
          child: ListTile(
            title: Text(favorite.quote, style: const TextStyle(height: 1.5)),
            subtitle: Text("—— ${favorite.from}", textAlign: TextAlign.right),
          ),
        );
      },
    );
  }
}