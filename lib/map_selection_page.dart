// file: lib/map_selection_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
// VVV 导入我们新创建的服务 VVV
import 'location_service.dart';

class MapSelectionPage extends StatefulWidget {
  final LatLng initialLocation;
  const MapSelectionPage({super.key, required this.initialLocation});

  @override
  State<MapSelectionPage> createState() => _MapSelectionPageState();
}

class _MapSelectionPageState extends State<MapSelectionPage> {
  // --- 配置区域 ---
  final String _amapApiKey = '在此处粘贴你的高德Web服务API Key';
  // VVV 替换为你在高德后台获取的暗黑模式样式ID VVV
  final String _darkStyleId = '在此处粘贴你的暗黑模式样式ID';

  // --- 控制器 ---
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  // --- 状态变量 ---
  LatLng? _currentMapCenter;
  List<Poi> _nearbyPlaces = [];
  bool _isLoadingPlaces = false;
  Timer? _debounce;
  Poi? _selectedPlace;
  List<Marker> _searchResultMarkers = [];

  // VVV 新增的服务和状态 VVV
  final SearchHistoryService _historyService = SearchHistoryService();
  final FavoritePlaceService _favoritePlaceService = FavoritePlaceService();
  List<String> _searchHistory = [];
  List<Poi> _favoritePlaces = [];
  bool _isSearching = false; // 用于显示/隐藏历史和收藏

  @override
  void initState() {
    super.initState();
    _currentMapCenter = widget.initialLocation;
    _loadInitialData();
  }

  void _loadInitialData() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchNearbyPlaces(widget.initialLocation);
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

  // --- 核心API方法 ---
  Future<void> _fetchNearbyPlaces(LatLng location) async {
    setState(() => _isLoadingPlaces = true);
    // ... 此方法不变 ...
  }

  Future<void> _searchLocation(String query) async {
    FocusScope.of(context).unfocus();
    if (query.isEmpty) return;

    await _historyService.addSearchTerm(query);
    _searchHistory = await _historyService.getHistory();

    final url = Uri.parse(
        'https://restapi.amap.com/v3/place/text?key=$_amapApiKey&keywords=$query&offset=20&page=1&extensions=base');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1') {
          final poisJson = data['pois'] as List;
          final results = poisJson.map((p) => Poi.fromJson(p)).toList();

          setState(() {
            _isSearching = false;
            _nearbyPlaces = results;
            _searchResultMarkers = results.map((p) => Marker(
              point: p.location,
              width: 80,
              height: 80,
              child: const Icon(Icons.location_on, color: Colors.blue, size: 30),
            )).toList();
          });

          if (results.isNotEmpty) {
            _mapController.move(results.first.location, 15);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有找到相关的地点')));
          }
        }
      }
    } catch (e) {
      // ... 错误处理 ...
    }
  }

  // --- UI交互方法 ---
  void _onConfirm() { // 不变
    // ...
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      setState(() => _searchResultMarkers = []); // 拖动地图时清除搜索标记
      // ... debounce逻辑不变 ...
    }
  }

  Future<void> _goToMyLocation() async { // 不变
    // ...
  }

  void _onFavoriteToggle(Poi place) async {
    bool isFav = await _favoritePlaceService.isFavorite(place);
    if (isFav) {
      await _favoritePlaceService.removeFavorite(place);
    } else {
      await _favoritePlaceService.addFavorite(place);
    }
    _favoritePlaces = await _favoritePlaceService.getFavorites();
    setState(() {});
  }

  // --- UI构建方法 ---
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final mapStyle = isDarkMode ? "&style=amap://styles/$_darkStyleId" : "";

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择位置'),
        actions: [ IconButton(icon: const Icon(Icons.check), onPressed: _onConfirm) ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialLocation,
              initialZoom: 16,
              onPositionChanged: _onPositionChanged,
              onTap: (_, __) { setState(() => _isSearching = false); FocusScope.of(context).unfocus(); },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://wprd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&x={x}&y={y}&z={z}$mapStyle',
                subdomains: const ['1', '2', '3', '4'],
              ),
              MarkerLayer(markers: _searchResultMarkers),
            ],
          ),

          const Center(child: Icon(Icons.location_pin, size: 50, color: Colors.red)),

          // --- 全新的搜索和建议UI ---
          if (_isSearching)
            _buildSearchSuggestionOverlay(),

          Positioned(
            top: 10,
            left: 15,
            right: 15,
            child: _buildSearchBar(),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildPoiList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToMyLocation,
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
              onTap: () => setState(() => _isSearching = true),
              onSubmitted: _searchLocation,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.star, color: Colors.amber),
            tooltip: '收藏夹',
            onPressed: () {
              setState(() => _isSearching = false);
              FocusScope.of(context).unfocus();
              // 用底部弹窗显示收藏夹
              showModalBottomSheet(
                  context: context,
                  builder: (context) => ListView.builder(
                    itemCount: _favoritePlaces.length,
                    itemBuilder: (context, index) {
                      final place = _favoritePlaces[index];
                      return ListTile(
                        title: Text(place.name),
                        subtitle: Text(place.address),
                        onTap: () {
                          _mapController.move(place.location, 16);
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
                const SizedBox(height: 70), // 为搜索框留出空间
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
            : ListView.builder(
          itemCount: _nearbyPlaces.length,
          itemBuilder: (context, index) {
            final place = _nearbyPlaces[index];
            return FutureBuilder<bool>(
              future: _favoritePlaceService.isFavorite(place),
              builder: (context, snapshot) {
                final isFav = snapshot.data ?? false;
                return ListTile(
                  title: Text(place.name),
                  subtitle: Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: isFav ? Colors.amber : null,
                    ),
                    onPressed: () => _onFavoriteToggle(place),
                  ),
                  onTap: () {
                    setState(() => _selectedPlace = place);
                    _mapController.move(place.location, _mapController.camera.zoom);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}