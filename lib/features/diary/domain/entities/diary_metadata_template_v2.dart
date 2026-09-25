import 'diary_entry.dart';

class DiaryMetadataTemplateV2 {
  const DiaryMetadataTemplateV2({
    required this.id,
    required this.name,
    this.mood,
    this.tags = const [],
    this.location,
  });

  final String id;
  final String name;
  final String? mood;
  final List<String> tags;
  final DiaryLocation? location;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'mood': mood,
    'tags': tags,
    'location': location == null
        ? null
        : {
            'latitude': location!.latitude,
            'longitude': location!.longitude,
            'address': location!.address,
          },
  };

  factory DiaryMetadataTemplateV2.fromJson(Map<String, Object?> json) {
    final locationJson = json['location'];
    return DiaryMetadataTemplateV2(
      id: json['id'] as String,
      name: json['name'] as String,
      mood: json['mood'] as String?,
      tags: (json['tags'] as List? ?? const []).whereType<String>().toList(
        growable: false,
      ),
      location: locationJson is Map
          ? DiaryLocation(
              latitude: (locationJson['latitude'] as num).toDouble(),
              longitude: (locationJson['longitude'] as num).toDouble(),
              address: locationJson['address'] as String?,
            )
          : null,
    );
  }
}
