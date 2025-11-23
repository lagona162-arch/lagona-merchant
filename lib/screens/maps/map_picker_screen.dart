import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/colors.dart';
import '../../services/google_places_service.dart';

class MapPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const MapPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng _selectedLocation = const LatLng(14.5995, 120.9842); // Default to Manila, Philippines
  String? _selectedAddress;
  bool _isLoadingAddress = false;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _requestLocationPermissionAndInitialize();
  }

  Future<void> _requestLocationPermissionAndInitialize() async {
    // Request location permission first
    await _requestLocationPermission();
    // Then initialize location
    await _initializeLocation();
  }

  Future<void> _requestLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them in settings.'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission is required to select your business location.'),
                backgroundColor: AppColors.error,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied. Please enable them in app settings.'),
              backgroundColor: AppColors.error,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
    }
  }

  Future<void> _initializeLocation() async {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      setState(() {
        _selectedLocation = LatLng(widget.initialLatitude!, widget.initialLongitude!);
        _selectedAddress = widget.initialAddress;
        _isInitializing = false;
      });
      // Move camera to initial location
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_selectedLocation, 15),
        );
      }
      // Get address for initial location
      await _getAddressForLocation(_selectedLocation);
    } else {
      // Set a default location immediately so map shows
      setState(() {
        _isInitializing = false;
      });
      // Then try to get current location
      await _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        // Default to Manila, Philippines
        setState(() {
          _selectedLocation = const LatLng(14.5995, 120.9842);
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are denied.'),
                backgroundColor: AppColors.error,
              ),
            );
          }
          // Default to Manila, Philippines
          setState(() {
            _selectedLocation = const LatLng(14.5995, 120.9842);
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied. Please enable them in settings.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        // Default to Manila, Philippines
        setState(() {
          _selectedLocation = const LatLng(14.5995, 120.9842);
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      final newLocation = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _selectedLocation = newLocation;
      });

      // Move camera to current location
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(newLocation, 15),
        );
      }

      // Get address for current location
      await _getAddressForLocation(newLocation);
    } catch (e) {
      // Default to Manila, Philippines on error
      final defaultLocation = const LatLng(14.5995, 120.9842);
      setState(() {
        _selectedLocation = defaultLocation;
      });
      
      // Move camera to default location
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(defaultLocation, 15),
        );
      }
    }
  }

  Future<void> _onMapTap(LatLng location) async {
    setState(() {
      _selectedLocation = location;
    });
    await _getAddressForLocation(location);
  }

  Future<void> _getAddressForLocation(LatLng location) async {
    setState(() => _isLoadingAddress = true);

    final placeDetails = await GooglePlacesService.reverseGeocode(
      location.latitude,
      location.longitude,
    );

    if (placeDetails != null && mounted) {
      setState(() {
        _selectedAddress = placeDetails.formattedAddress;
        _isLoadingAddress = false;
      });
    } else {
      setState(() {
        _selectedAddress = '${location.latitude}, ${location.longitude}';
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _onMyLocationPressed() async {
    await _getCurrentLocation();
    if (_mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_selectedLocation, 15),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Ensure camera is positioned correctly when map is created
    Future.delayed(const Duration(milliseconds: 100), () async {
      if (_mapController != null && mounted) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_selectedLocation, 15),
        );
      }
    });
  }

  void _confirmSelection() {
    Navigator.pop(context, {
      'latitude': _selectedLocation.latitude,
      'longitude': _selectedLocation.longitude,
      'address': _selectedAddress ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Business Location'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _selectedLocation,
              zoom: 15,
            ),
            onTap: _onMapTap,
            markers: {
              Marker(
                markerId: const MarkerId('selected_location'),
                position: _selectedLocation,
                draggable: true,
                onDragEnd: (LatLng newPosition) {
                  _onMapTap(newPosition);
                },
              ),
            },
            myLocationButtonEnabled: false,
            myLocationEnabled: true,
            mapType: MapType.normal,
            zoomControlsEnabled: false,
            compassEnabled: true,
          ),
          
          if (_isInitializing)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          
          // Current Location Button
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              onPressed: _onMyLocationPressed,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.my_location,
                color: AppColors.primary,
              ),
            ),
          ),

          // Address Display
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Selected Address:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isLoadingAddress)
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Getting address...',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      _selectedAddress ?? 'Tap on map to select location',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Confirm Button
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: _confirmSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: const Text(
                'Confirm Location',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

