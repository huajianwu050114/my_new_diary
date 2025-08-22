// file: libs/custom_festivals_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'festival_service.dart';
import 'add_festival_page.dart'; // 导入新页面

class CustomFestivalsPage extends StatelessWidget {
  const CustomFestivalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FestivalProvider>();
    final customFestivals = provider.customFestivals;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的纪念日'),
      ),
      body: customFestivals.isEmpty
          ? const Center(child: Text('还没有添加任何纪念日'))
          : ListView.builder(
        itemCount: customFestivals.length,
        itemBuilder: (context, index) {
          final festival = customFestivals[index];
          return ListTile(
            title: Text(festival.name),
            subtitle: Text(DateFormat('M月d日').format(festival.date)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () {
                provider.deleteCustomFestival(festival.name, festival.date);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddFestivalPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}