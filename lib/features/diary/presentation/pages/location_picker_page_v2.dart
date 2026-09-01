import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/entities/diary_entry.dart';

class LocationPickerPageV2 extends StatefulWidget {
  const LocationPickerPageV2({this.initialLocation, super.key});

  final DiaryLocation? initialLocation;

  @override
  State<LocationPickerPageV2> createState() => _LocationPickerPageV2State();
}

class _LocationPickerPageV2State extends State<LocationPickerPageV2> {
  final _mapController = MapController();
  DiaryLocation? _selectedLocation;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialLocation;
    final initialCenter = initial == null
        ? const LatLng(22.3193, 114.1694)
        : LatLng(initial.latitude, initial.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择地点'),
        actions: [
          TextButton(
            onPressed: _selectedLocation == null
                ? null
                : () => Navigator.of(context).pop(_selectedLocation),
            child: const Text('确定'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 13,
              onTap: (_, point) => _select(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.my_new_diary',
              ),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _selectedLocation!.latitude,
                        _selectedLocation!.longitude,
                      ),
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.location_pin,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedLocation?.address ?? '点击地图选择地点',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: '使用当前位置',
                        onPressed: _isLocating ? null : _useCurrentLocation,
                        icon: _isLocating
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _select(LatLng point) async {
    setState(() {
      _selectedLocation = DiaryLocation(
        latitude: point.latitude,
        longitude: point.longitude,
        address: '正在获取地址…',
      );
    });
    final address = await _reverseGeocode(point);
    if (mounted &&
        _selectedLocation?.latitude == point.latitude &&
        _selectedLocation?.longitude == point.longitude) {
      setState(() {
        _selectedLocation = DiaryLocation(
          latitude: point.latitude,
          longitude: point.longitude,
          address: address,
        );
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('没有定位权限');
      }
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      _mapController.move(point, 16);
      await _select(point);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法获取当前位置：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<String> _reverseGeocode(LatLng point) async {
    try {
      final places = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (places.isEmpty) {
        return _coordinates(point);
      }
      final place = places.first;
      final parts = [
        place.administrativeArea,
        place.locality,
        place.subLocality,
        place.street,
        place.name,
      ].whereType<String>().where((part) => part.trim().isNotEmpty);
      return parts.toSet().join(' ');
    } catch (_) {
      return _coordinates(point);
    }
  }

  String _coordinates(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)}, '
        '${point.longitude.toStringAsFixed(5)}';
  }
}
