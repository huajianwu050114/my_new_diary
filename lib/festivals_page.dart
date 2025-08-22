// file: libs/festivals_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'festival_service.dart';
import 'custom_festivals_page.dart';

class FestivalsPage extends StatelessWidget {
  const FestivalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FestivalProvider>();
    final festivals = context.watch<FestivalProvider>().allFestivals;

    return Scaffold(
      appBar: AppBar(
        title: const Text('年度节日'),
        actions: [
          IconButton(
            icon: const Icon(Icons.celebration_outlined),
            tooltip: '新增节日',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomFestivalsPage()));
            },
          ),
        ],
      ),

      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: provider.allFestivals.length,
        itemBuilder: (context, index) {
          final festival = provider.allFestivals[index];
          final String dateFormatted = DateFormat('M月d日 EEEE', 'zh_CN').format(festival['date']);
          final int daysUntil = festival['daysUntil'];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text(festival['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(dateFormatted),
              trailing: Text(
                daysUntil == 0 ? '就是今天！' : '$daysUntil 天后',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}