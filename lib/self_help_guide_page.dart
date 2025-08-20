// 文件: lib/self_help_guide_page.dart (最终完整版)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'diary_model.dart';
import 'diary_service.dart';
import 'diary_view_page.dart';

class SelfHelpGuidePage extends StatelessWidget {
  const SelfHelpGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的自救锦囊'),
      ),
      body: FutureBuilder<List<DiaryEntry>>(
        future: context.read<DiaryService>().getSelfHelpEntries(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  '你的锦囊还是空的。\n\n去回顾日记，把那些在困境中给你带来力量的思考，点击顶部的💡图标收藏进来吧。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.6),
                ),
              ),
            );
          }
          final entries = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              // 现在这里调用的是我们实现了的 _buildGuideCard 方法
              return _buildGuideCard(context, entries[index]);
            },
          );
        },
      ),
    );
  }

  // VVVV  这就是为你设计的、完整的“锦囊”卡片 VVVV
  Widget _buildGuideCard(BuildContext context, DiaryEntry entry) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shadowColor: Colors.amber.withOpacity(0.2),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.amber.shade300, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry)),
          );
        },
        borderRadius: BorderRadius.circular(15.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 顶部的标题行，包含图标和日期
              Row(
                children: [
                  Icon(Icons.lightbulb_circle, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Text(
                    '一份来自 ${DateFormat('yyyy年M月d日').format(entry.date)} 的智慧',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const Divider(height: 24),
              // 2. 日记正文摘录
              Text(
                entry.text,
                maxLines: 10, // 最多显示10行，方便阅读
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6, // 更大的行高，提升阅读舒适度
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}