// file: libs/festival_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// --- 数据模型 (保持不变) ---
class Festival {
  final String name;
  final DateTime date;
  final bool isCustom;

  Festival({required this.name, required this.date, this.isCustom = false});

  Map<String, dynamic> toJson() => {
    'name': name,
    'date': date.toIso8601String(),
    'isCustom': isCustom,
  };

  factory Festival.fromJson(Map<String, dynamic> json) => Festival(
    name: json['name'],
    date: DateTime.parse(json['date']),
    isCustom: json['isCustom'] ?? true,
  );
}


// --- 服务类 ---
class FestivalService {

  // VVV 核心修改：重构此方法以实现缓存 VVV
  Future<List<Festival>> _fetchPublicHolidays(int year) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'public_holidays_$year';
    final timestampKey = 'public_holidays_timestamp_$year';
    const cacheDuration = Duration(hours: 24);

    // 1. 检查是否存在有效的、未过期的缓存
    final cachedTimestampString = prefs.getString(timestampKey);
    if (cachedTimestampString != null) {
      final cachedTimestamp = DateTime.parse(cachedTimestampString);
      if (DateTime.now().difference(cachedTimestamp) < cacheDuration) {
        final cachedData = prefs.getString(cacheKey);
        if (cachedData != null) {
          print('为 $year 年从缓存加载公共节假日。');
          final List<dynamic> data = jsonDecode(cachedData);
          return data.map((json) => Festival(
            name: json['localName'],
            date: DateTime.parse(json['date']),
          )).toList();
        }
      }
    }

    // 2. 如果缓存无效或不存在，则从网络获取
    try {
      print('为 $year 年从网络获取公共节假日。');
      final url = Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/CN');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // 3. 获取成功，将新数据和时间戳存入缓存
        await prefs.setString(cacheKey, response.body);
        await prefs.setString(timestampKey, DateTime.now().toIso8601String());

        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Festival(
          name: json['localName'],
          date: DateTime.parse(json['date']),
        )).toList();
      }
    } catch (e) {
      print('获取公共节假日失败: $e');
    }

    // 4. 网络失败后的回退方案：尝试使用任何已存在的（即使是过期的）缓存
    print('网络请求失败，尝试为 $year 年加载旧缓存。');
    final staleData = prefs.getString(cacheKey);
    if (staleData != null) {
      final List<dynamic> data = jsonDecode(staleData);
      return data.map((json) => Festival(
        name: json['localName'],
        date: DateTime.parse(json['date']),
      )).toList();
    }

    // 5. 如果所有方法都失败，返回空列表
    return [];
  }

  // VVV 以下方法保持不变 VVV
  Future<List<Festival>> _loadCustomFestivals() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> festivalStrings = prefs.getStringList('custom_festivals') ?? [];
    return festivalStrings.map((s) => Festival.fromJson(jsonDecode(s))).toList();
  }

  Future<void> _saveCustomFestivals(List<Festival> festivals) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> festivalStrings = festivals.map((f) => jsonEncode(f.toJson())).toList();
    await prefs.setStringList('custom_festivals', festivalStrings);
  }

  Future<void> addCustomFestival(String name, DateTime date) async {
    final customFestivals = await _loadCustomFestivals();
    customFestivals.add(Festival(name: name, date: date, isCustom: true));
    await _saveCustomFestivals(customFestivals);
  }

  Future<void> deleteCustomFestival(String name, DateTime date) async {
    final customFestivals = await _loadCustomFestivals();
    customFestivals.removeWhere((f) => f.name == name && f.date == date);
    await _saveCustomFestivals(customFestivals);
  }

  Future<List<Map<String, dynamic>>> getFestivalInfo() async {
    final List<Map<String, dynamic>> festivalDetails = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final publicHolidaysThisYear = await _fetchPublicHolidays(now.year);
    final publicHolidaysNextYear = await _fetchPublicHolidays(now.year + 1);
    final customFestivals = await _loadCustomFestivals();

    final List<Festival> combinedList = [...publicHolidaysThisYear, ...publicHolidaysNextYear];
    for (var festival in customFestivals) {
      DateTime festivalDate = DateTime(now.year, festival.date.month, festival.date.day);
      if (festivalDate.isBefore(today)) {
        festivalDate = DateTime(now.year + 1, festival.date.month, festival.date.day);
      }
      combinedList.add(Festival(name: festival.name, date: festivalDate, isCustom: true));
    }

    for (var festival in combinedList) {
      if (festival.date.isBefore(today)) continue;
      final daysUntil = festival.date.difference(today).inDays;
      festivalDetails.add({
        'name': festival.name,
        'date': festival.date,
        'daysUntil': daysUntil,
        'isCustom': festival.isCustom,
      });
    }

    final uniqueMap = {for (var f in festivalDetails) '${f['name']}-${f['date']}': f};
    final uniqueFestivals = uniqueMap.values.toList();
    uniqueFestivals.sort((a, b) => a['daysUntil'].compareTo(b['daysUntil']));

    return uniqueFestivals;
  }
}

// --- Provider (保持不变) ---
class FestivalProvider extends ChangeNotifier {
  final FestivalService _service = FestivalService();
  List<Map<String, dynamic>> _allFestivals = [];
  List<Map<String, dynamic>> _upcomingFestivals = [];
  List<Festival> _customFestivals = [];

  List<Map<String, dynamic>> get allFestivals => _allFestivals;
  List<Map<String, dynamic>> get upcomingFestivals => _upcomingFestivals;
  List<Festival> get customFestivals => _customFestivals;

  bool _isLoading = true;
  bool get isLoading => _isLoading;
  FestivalProvider() {
    loadFestivals();
  }

  Future<void> loadFestivals() async {
    _isLoading = true;
    notifyListeners();
    _allFestivals = await _service.getFestivalInfo();
    _customFestivals = await _service._loadCustomFestivals();
    _upcomingFestivals = _allFestivals.where((f) => f['daysUntil'] <= 90).toList();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addCustomFestival(String name, DateTime date) async {
    await _service.addCustomFestival(name, date);
    await loadFestivals();
  }

  Future<void> deleteCustomFestival(String name, DateTime date) async {
    await _service.deleteCustomFestival(name, date);
    await loadFestivals();
  }
}