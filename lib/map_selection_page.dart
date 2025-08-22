// file: libs/map_selection_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'location_service.dart';

class MapSelectionPage extends StatefulWidget {
  final LatLng initialLocation;
  const MapSelectionPage({super.key, required this.initialLocation});

  @override
  State<MapSelectionPage> createState() => _MapSelectionPageState();
}

class _MapSelectionPageState extends State<MapSelectionPage> {
  // --- 配置區域 ---
  // VVV 在此處貼上你的高德Web服務API Key VVV
  final String _amapApiKey = 'efb67b0292824f14fafb71f7f7222330';
  // VVV 在此處貼上你在高德後台獲取的暗黑模式樣式ID VVV

  // --- 控制器 ---
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  // --- 狀態變數 ---
  LatLng? _currentMapCenter;
  List<Poi> _nearbyPlaces = [];
  bool _isLoadingPlaces = true;
  Timer? _debounce;
  Poi? _selectedPlace;
  List<Marker> _searchResultMarkers = [];

  final SearchHistoryService _historyService = SearchHistoryService();
  final FavoritePlaceService _favoritePlaceService = FavoritePlaceService();
  List<String> _searchHistory = [];
  List<Poi> _favoritePlaces = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _currentMapCenter = widget.initialLocation;
    _loadInitialData();
  }

  void _loadInitialData() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentMapCenter != null) {
        _fetchNearbyPlaces(_currentMapCenter!);
      }
    });
    _searchHistory = await _historyService.getHistory();
    _favoritePlaces = await _favoritePlaceService.getFavorites();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// 當用戶點擊確認按鈕時觸發
  void _onConfirm() {
    // 優先使用用戶明確點選的POI
    if (_selectedPlace != null) {
      final result = {
        'latitude': _selectedPlace!.location.latitude,
        'longitude': _selectedPlace!.location.longitude,
        'address': _selectedPlace!.name, // 通常POI名稱比地址更簡潔
      };
      Navigator.of(context).pop(result);
      return;
    }

    // 如果用戶沒有點選，但周邊列表有數據，默認選第一個
    if (_nearbyPlaces.isNotEmpty) {
      final firstPlace = _nearbyPlaces.first;
      final result = {
        'latitude': firstPlace.location.latitude,
        'longitude': firstPlace.location.longitude,
        'address': firstPlace.name,
      };
      Navigator.of(context).pop(result);
      return;
    }

    // 作為備選，如果POI列表為空，則返回地圖中心點的粗略地址
    if (_currentMapCenter != null) {
      final result = {
        'latitude': _currentMapCenter!.latitude,
        'longitude': _currentMapCenter!.longitude,
        'address': "地圖上的選定點",
      };
      Navigator.of(context).pop(result);
    }
  }

  /// 當地圖位置變化時觸發，使用 debounce 防止API頻繁請求
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      _currentMapCenter = camera.center;
      // 拖動地圖時，清除之前的搜索結果標記
      if (_searchResultMarkers.isNotEmpty) {
        setState(() => _searchResultMarkers = []);
      }

      // debounce 邏輯：如果用戶在500毫秒內沒有再次移動地圖，則發起請求
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (_currentMapCenter != null) {
          _fetchNearbyPlaces(_currentMapCenter!);
        }
      });
    }
  }

  /// 獲取指定座標點周邊的POI列表
  Future<void> _fetchNearbyPlaces(LatLng location) async {
    if (!mounted) return;
    setState(() {
      _isLoadingPlaces = true;
      _nearbyPlaces = [];
    });

    // 【修正1】: 使用 place/around (周边搜索) API
    final url = Uri.parse(
        'https://restapi.amap.com/v3/place/around?key=$_amapApiKey&location=${location.longitude},${location.latitude}&radius=3000&offset=25&page=1&extensions=all');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1') {
          // 【修正2】: "周边搜索" API 的返回结构不同，直接从 'pois' 键获取列表
          final poisJson = data['pois'] as List? ?? [];
          if (mounted) {
            setState(() {
              _nearbyPlaces = poisJson.map((p) => Poi.fromJson(p)).toList();
            });
          }
        }
      }
    } catch (e) {
      print("获取周边位置失败: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingPlaces = false);
      }
    }
  }

  /// 搜索地點
  Future<void> _searchLocation(String query) async {
    FocusScope.of(context).unfocus();
    if (query.isEmpty) return;

    await _historyService.addSearchTerm(query);
    _searchHistory = await _historyService.getHistory();

    final url = Uri.parse(
        'https://restapi.amap.com/v3/place/text?key=$_amapApiKey&keywords=$query&offset=20&page=1&extensions=base');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1') {
          final poisJson = data['pois'] as List? ?? [];
          final results = poisJson.map((p) => Poi.fromJson(p)).toList();

          if (results.isNotEmpty) {
            _mapController.move(results.first.location, 15);
            setState(() {
              _isSearching = false;
              _nearbyPlaces = results; // 將搜索結果也顯示在底部列表
              _searchResultMarkers = results.map((p) => Marker(
                point: p.location,
                width: 30,
                height: 30,
                child: Icon(Icons.location_on, color: Theme.of(context).colorScheme.secondary, size: 30),
              )).toList();
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有找到相关的网址')));
          }
        }
      }
    } catch (e) {
      print("搜索地点失败: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('搜索失败，请检查网络')));
    }
  }

  /// 定位到我的當前位置
  Future<void> _goToMyLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      final myLocation = LatLng(position.latitude, position.longitude);
      _mapController.move(myLocation, 16.0);
      _fetchNearbyPlaces(myLocation);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获得当前位置')));
      }
    }
  }

  /// 添加或移除收藏
  void _onFavoriteToggle(Poi place) async {
    bool isFav = await _favoritePlaceService.isFavorite(place);
    if (isFav) {
      await _favoritePlaceService.removeFavorite(place);
    } else {
      await _favoritePlaceService.addFavorite(place);
    }
    _favoritePlaces = await _favoritePlaceService.getFavorites();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final String mapStyle = "";

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择位置'),
        actions: [ IconButton(icon: const Icon(Icons.check), tooltip: '确认选择', onPressed: _onConfirm) ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialLocation,
              initialZoom: 16,
              onPositionChanged: _onPositionChanged,
              onTap: (_, __) { if (_isSearching) { setState(() => _isSearching = false); FocusScope.of(context).unfocus(); } },
            ),
            children: [
              TileLayer(
                // 【修正】: 在URL中添加 &key=... 参数
                urlTemplate: 'https://webst0{s}.is.autonavi.com/appmaptile?style=7&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.example.my_new_diary',
              ),
              MarkerLayer(markers: _searchResultMarkers),
            ],
          ),

          const Center(child: IgnorePointer(child: Icon(Icons.location_pin, size: 50, color: Colors.red))),

          if (_isSearching) _buildSearchSuggestionOverlay(),

          Positioned(top: 10, left: 15, right: 15, child: _buildSearchBar()),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildPoiList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToMyLocation,
        tooltip: '我的位置',
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Card(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索地点...',
                prefixIcon: Icon(Icons.search),
                border: InputBorder.none,
              ),
              onTap: () async {
                _searchHistory = await _historyService.getHistory();
                setState(() => _isSearching = true);
              },
              onSubmitted: _searchLocation,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.star, color: Colors.amber),
            tooltip: '收藏夾',
            onPressed: () async {
              _favoritePlaces = await _favoritePlaceService.getFavorites();
              setState(() => _isSearching = false);
              FocusScope.of(context).unfocus();
              showModalBottomSheet(
                  context: context,
                  builder: (context) => _favoritePlaces.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("還沒有收藏任何地點")))
                      : ListView.builder(
                    itemCount: _favoritePlaces.length,
                    itemBuilder: (context, index) {
                      final place = _favoritePlaces[index];
                      return ListTile(
                        leading: const Icon(Icons.star),
                        title: Text(place.name),
                        subtitle: Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          _mapController.move(place.location, 16);
                          _fetchNearbyPlaces(place.location);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  )
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildSearchSuggestionOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () { setState(() => _isSearching = false); FocusScope.of(context).unfocus(); },
        child: Container(
          color: Colors.black.withOpacity(0.5),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 70),
                if (_searchHistory.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 15),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchHistory.length,
                      itemBuilder: (context, index) {
                        final term = _searchHistory[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(term),
                          onTap: () {
                            _searchController.text = term;
                            _searchLocation(term);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoiList() {
    return Material(
      elevation: 4.0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.3,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _isLoadingPlaces
            ? const Center(child: CircularProgressIndicator())
            : _nearbyPlaces.isEmpty
            ? const Center(child: Text('周邊沒有找到地點'))
            : ListView.builder(
          itemCount: _nearbyPlaces.length,
          itemBuilder: (context, index) {
            final place = _nearbyPlaces[index];
            final isSelected = _selectedPlace == place;
            return ListTile(
              title: Text(place.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              subtitle: Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: FutureBuilder<bool>(
                future: _favoritePlaceService.isFavorite(place),
                builder: (context, snapshot) {
                  final isFav = snapshot.data ?? false;
                  return IconButton(
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: isFav ? Colors.amber : null,
                    ),
                    onPressed: () => _onFavoriteToggle(place),
                  );
                },
              ),
              tileColor: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
              onTap: () => setState(() => _selectedPlace = place),
            );
          },
        ),
      ),
    );
  }
}