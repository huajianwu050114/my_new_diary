// file: lib/location_service.dart
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 我们将POI数据模型移到这里，因为它现在被多个地方共享
class Poi {
  final String name;
  final String address;
  final LatLng location;
  // 添加一个唯一的ID，方便管理收藏
  final String? id;

  Poi({required this.name, required this.address, required this.location, this.id});

  // 用于比较两个Poi对象是否相同
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Poi &&
              runtimeType == other.runtimeType &&
              (id != null && other.id != null ? id == other.id : name == other.name && address == other.address);

  @override
  int get hashCode => id != null ? id.hashCode : name.hashCode ^ address.hashCode;

  factory Poi.fromJson(Map<String, dynamic> json) {
    final locationStr = json['location'] as String? ?? '0,0';
    final parts = locationStr.split(',');
    return Poi(
      id: json['id'],
      name: json['name'] ?? '',
      address: json['address'] is String ? json['address'] : '地址未知',
      location: LatLng(double.tryParse(parts[1]) ?? 0, double.tryParse(parts[0]) ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'location': '${location.longitude},${location.latitude}',
  };
}

// 搜索历史服务
class SearchHistoryService {
  static const _historyKey = 'search_history';
  static const _maxHistory = 10;

  Future<List<String>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? [];
  }

  Future<void> addSearchTerm(String term) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_historyKey) ?? [];

    // 移除已存在的，避免重复
    history.remove(term);
    // 加到最前面
    history.insert(0, term);

    // 保持列表长度
    if (history.length > _maxHistory) {
      history = history.sublist(0, _maxHistory);
    }

    await prefs.setStringList(_historyKey, history);
  }
}

// 收藏地点服务
class FavoritePlaceService {
  static const _favoritesKey = 'favorite_places';

  Future<List<Poi>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favoritesJson = prefs.getStringList(_favoritesKey) ?? [];
    return favoritesJson.map((s) => Poi.fromJson(jsonDecode(s))).toList();
  }

  Future<void> addFavorite(Poi place) async {
    final prefs = await SharedPreferences.getInstance();
    List<Poi> favorites = await getFavorites();
    if (!favorites.contains(place)) {
      favorites.add(place);
      await _saveFavorites(prefs, favorites);
    }
  }

  Future<void> removeFavorite(Poi place) async {
    final prefs = await SharedPreferences.getInstance();
    List<Poi> favorites = await getFavorites();
    favorites.remove(place);
    await _saveFavorites(prefs, favorites);
  }

  Future<bool> isFavorite(Poi place) async {
    final favorites = await getFavorites();
    return favorites.contains(place);
  }

  Future<void> _saveFavorites(SharedPreferences prefs, List<Poi> favorites) async {
    final List<String> favoritesJson =
    favorites.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_favoritesKey, favoritesJson);
  }
}