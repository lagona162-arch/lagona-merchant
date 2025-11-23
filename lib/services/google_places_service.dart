import 'dart:convert';
import 'package:http/http.dart' as http;

class GooglePlacesService {
  static const String _apiKey = 'AIzaSyC4EMDLfV7JG21k6yvAu_uRriVQadyIEGg';
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api';

  // Get place autocomplete predictions
  static Future<List<PlacePrediction>> getPlacePredictions(String input) async {
    try {
      final encodedInput = Uri.encodeComponent(input);
      final url = Uri.parse(
        '$_baseUrl/place/autocomplete/json?input=$encodedInput&key=$_apiKey&components=country:ph',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final predictions = data['predictions'] as List?;
          if (predictions != null) {
            return predictions
                .map((p) => PlacePrediction.fromJson(p))
                .toList();
          }
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Get place details by place_id
  static Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/place/details/json?place_id=$placeId&key=$_apiKey&fields=formatted_address,geometry,place_id,name,address_components',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return PlaceDetails.fromJson(data['result']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Reverse geocoding - get address from coordinates
  static Future<PlaceDetails?> reverseGeocode(double latitude, double longitude) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/geocode/json?latlng=$latitude,$longitude&key=$_apiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'] != null) {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            final result = results[0];
            return PlaceDetails.fromJson(result);
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

class PlacePrediction {
  final String description;
  final String placeId;
  final List<String> types;

  PlacePrediction({
    required this.description,
    required this.placeId,
    required this.types,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      description: json['description'] as String,
      placeId: json['place_id'] as String,
      types: (json['types'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class PlaceDetails {
  final String formattedAddress;
  final String? placeId;
  final String? name;
  final double latitude;
  final double longitude;
  final List<AddressComponent> addressComponents;

  PlaceDetails({
    required this.formattedAddress,
    this.placeId,
    this.name,
    required this.latitude,
    required this.longitude,
    required this.addressComponents,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;

    return PlaceDetails(
      formattedAddress: json['formatted_address'] as String? ?? '',
      placeId: json['place_id'] as String?,
      name: json['name'] as String?,
      latitude: (location['lat'] as num).toDouble(),
      longitude: (location['lng'] as num).toDouble(),
      addressComponents: (json['address_components'] as List<dynamic>?)
              ?.map((e) => AddressComponent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  // Extract municipality/city from address components
  String? getMunicipality() {
    // Priority order for Philippine addresses:
    // 1. locality (city/municipality) - highest priority
    // 2. administrative_area_level_2 (city/municipality in some regions)
    // 3. sublocality_level_1 (some Philippine addresses use this)
    // 4. administrative_area_level_1 (province) - last resort fallback
    
    String? municipality;
    
    for (var component in addressComponents) {
      // Types are already strings, just convert to lowercase for comparison
      final types = component.types.map((e) => e.toLowerCase()).toList();
      
      // Check for city/municipality (highest priority)
      if (types.contains('locality')) {
        municipality = component.longName;
        break; // Found the best match, stop searching
      }
      
      // Check for administrative area level 2 (city/municipality in some regions)
      if (types.contains('administrative_area_level_2') && municipality == null) {
        municipality = component.longName;
      }
      
      // Check for sublocality_level_1 (some Philippine addresses use this)
      if (types.contains('sublocality_level_1') && municipality == null) {
        municipality = component.longName;
      }
    }
    
    // If still no municipality found, try administrative_area_level_1 (province) as last resort
    if (municipality == null) {
      for (var component in addressComponents) {
        final types = component.types.map((e) => e.toLowerCase()).toList();
        if (types.contains('administrative_area_level_1')) {
          municipality = component.longName;
          break;
        }
      }
    }
    
    return municipality;
  }
}

class AddressComponent {
  final String longName;
  final String shortName;
  final List<String> types;

  AddressComponent({
    required this.longName,
    required this.shortName,
    required this.types,
  });

  factory AddressComponent.fromJson(Map<String, dynamic> json) {
    // Parse types - they come as List<String> from Google Places API
    List<String> typesList = [];
    if (json['types'] != null) {
      final types = json['types'] as List<dynamic>;
      for (var type in types) {
        if (type is String) {
          typesList.add(type);
        } else {
          typesList.add(type.toString());
        }
      }
    }
    
    return AddressComponent(
      longName: json['long_name'] as String,
      shortName: json['short_name'] as String,
      types: typesList,
    );
  }
}

