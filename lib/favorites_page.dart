// file: libs/favorites_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'favorites_provider.dart';
import 'package:intl/intl.dart';
// VVV 1. 导入 intl 包用于格式化日期 VVV

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('我的收藏'),
          ),
          body: provider.favorites.isEmpty
              ? const Center(
            child: Text(
              '还没有收藏的句子哦～',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: provider.favorites.length,
            itemBuilder: (context, index) {
              final favorite = provider.favorites[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  title: Text(favorite.quote, style: const TextStyle(fontSize: 16, height: 1.5)),
                  // VVV 2. 修改 subtitle，让它显示来源和时间 VVV
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("—— ${favorite.from}"),
                        const SizedBox(height: 4),
                        Text(
                          "收藏于 ${DateFormat('yyyy-MM-dd HH:mm').format(favorite.creationTime)}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.favorite, color: Colors.red),
                    tooltip: '取消收藏',
                    onPressed: () {
                      provider.removeFavorite(favorite.quote, favorite.from);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}