// file: lib/map_selection_page.dart (使用 flutter_map 的新版本)
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart'; // flutter_map 使用 latlong2 包来处理坐标
import 'package:geocoding/geocoding.dart';

class MapSelectionPage extends StatefulWidget {
  final LatLng initialLocation;
  const MapSelectionPage({super.key, required this.initialLocation});

  @override
  State<MapSelectionPage> createState() => _MapSelectionPageState();
}

class _MapSelectionPageState extends State<MapSelectionPage> {
  final MapController _mapController = MapController();
  late LatLng _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }

  void _onConfirm() async {
    try {
      final placemarks = await placemarkFromCoordinates(
          _selectedLocation.latitude, _selectedLocation.longitude);
      final place = placemarks.first;
      final address = "${place.locality ?? ''}, ${place.street ?? ''}";

      final result = {
        'latitude': _selectedLocation.latitude,
        'longitude': _selectedLocation.longitude,
        'address': address,
      };
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择位置'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _onConfirm),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation,
              initialZoom: 16,
              onPositionChanged: (position, hasGesture) {
                if (position.center != null) {
                  setState(() {
                    _selectedLocation = position.center!;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                // VVV 换成高德地图的瓦片地址 VVV
                urlTemplate: 'https://wprd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',
                // VVV 添加高德需要的子域名 VVV
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.example.my_new_diary',
              ),
            ],
          ),
          const Center(
            child: Icon(Icons.location_pin, size: 50, color: Colors.red),
          ),
        ],
      ),
    );
  }
}