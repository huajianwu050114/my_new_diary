// file: lib/location_memories_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'diary_view_page.dart';
import 'dart:io';

class LocationMemoriesPage extends StatefulWidget {
  const LocationMemoriesPage({super.key});

  @override
  State<LocationMemoriesPage> createState() => _LocationMemoriesPageState();
}

class _LocationMemoriesPageState extends State<LocationMemoriesPage> {
  Future<List<List<DiaryEntry>>>? _groupedEntriesFuture;

  @override
  void initState() {
    super.initState();
    // 使用 read 是因为我们只在 initState 中加载一次数据
    _groupedEntriesFuture = context.read<DiaryService>().getGroupedEntriesByLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的足迹'),
      ),
      body: FutureBuilder<List<List<DiaryEntry>>>(
        future: _groupedEntriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('还没有带地理位置的日记哦'));
          }

          final groupedEntries = snapshot.data!;

          return Column(
            children: [
              // --- 地图展示 ---
              _buildMapView(groupedEntries),

              // --- 列表展示 ---
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.location_city, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('地点故事集', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: _buildLocationListView(groupedEntries),
              ),
            ],
          );
        },
      ),
    );
  }

  // 构建顶部的地图
  Widget _buildMapView(List<List<DiaryEntry>> groupedEntries) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.4,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(
            groupedEntries.first.first.latitude!,
            groupedEntries.first.first.longitude!,
          ),
          initialZoom: 10,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers: groupedEntries.map((cluster) {
              final firstEntry = cluster.first;
              return Marker(
                point: LatLng(firstEntry.latitude!, firstEntry.longitude!),
                width: 80,
                height: 80,
                child: GestureDetector(
                  onTap: () => _showEntriesForCluster(context, cluster),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(2,2))]
                        ),
                        child: Text(
                          cluster.length.toString(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        firstEntry.address?.split(',').first ?? '未知地点',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            shadows: const [Shadow(color: Colors.white, blurRadius: 2)]
                        ),
                        textAlign: TextAlign.center,
                      )
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 构建下方的列表
  Widget _buildLocationListView(List<List<DiaryEntry>> groupedEntries) {
    return ListView.builder(
      itemCount: groupedEntries.length,
      itemBuilder: (context, index) {
        final cluster = groupedEntries[index];
        final firstEntry = cluster.first;
        final imagePath = cluster.expand((e) => e.imagePaths).firstWhere((p) => p.isNotEmpty, orElse: () => '');

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: imagePath.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(imagePath),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            )
                : Container(width: 56, height: 56, color: Colors.grey.shade200, child: Icon(Icons.location_on)),
            title: Text(firstEntry.address ?? '未知地点'),
            subtitle: Text('在这里有 ${cluster.length} 篇日记'),
            onTap: () => _showEntriesForCluster(context, cluster),
          ),
        );
      },
    );
  }

  // 点击后，显示该地点的所有日记
  void _showEntriesForCluster(BuildContext context, List<DiaryEntry> cluster) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(cluster.first.address ?? '日记列表')),
        body: ListView.builder(
          itemCount: cluster.length,
          itemBuilder: (context, index) {
            final entry = cluster[index];
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text(entry.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.creationTime.toString()),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DiaryViewPage(entry: entry))),
              ),
            );
          },
        ),
      ),
    ));
  }
}