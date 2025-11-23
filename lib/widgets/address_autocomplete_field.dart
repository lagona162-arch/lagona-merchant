import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/colors.dart';
import '../services/google_places_service.dart';
import '../screens/maps/map_picker_screen.dart';

class AddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final Function(PlaceDetails)? onPlaceSelected;
  final int maxLines;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.validator,
    this.onPlaceSelected,
    this.maxLines = 2,
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  List<PlacePrediction> _predictions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    final query = widget.controller.text;
    if (query.length > 2) {
      _searchPlaces(query);
    } else {
      _removeOverlay();
      setState(() {
        _predictions = [];
        _showSuggestions = false;
      });
    }
  }

  Future<void> _searchPlaces(String query) async {
    setState(() => _isLoading = true);

    final predictions = await GooglePlacesService.getPlacePredictions(query);

    if (mounted) {
      setState(() {
        _predictions = predictions;
        _isLoading = false;
        _showSuggestions = predictions.isNotEmpty;
      });

      if (_showSuggestions) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    }
  }

  Future<void> _selectPlace(PlacePrediction prediction) async {
    widget.controller.text = prediction.description;
    _removeOverlay();

    setState(() {
      _predictions = [];
      _showSuggestions = false;
    });

    // Get place details
    final details = await GooglePlacesService.getPlaceDetails(prediction.placeId);
    if (details != null && widget.onPlaceSelected != null) {
      widget.onPlaceSelected!(details);
    }
  }

  void _showOverlay() {
    _removeOverlay();

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 4,
        width: size.width,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _predictions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'No results found',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _predictions.length,
                        itemBuilder: (context, index) {
                          final prediction = _predictions[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.location_on,
                              color: AppColors.primary,
                            ),
                            title: Text(
                              prediction.description,
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: () => _selectPlace(prediction),
                          );
                        },
                      ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _openMapPicker(BuildContext context) async {
    // Get current coordinates from controller if available
    double? initialLat;
    double? initialLng;
    String? initialAddress;

    // Try to extract coordinates from current address if it's already selected
    if (widget.controller.text.isNotEmpty) {
      initialAddress = widget.controller.text;
    }

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(
          initialLatitude: initialLat,
          initialLongitude: initialLng,
          initialAddress: initialAddress,
        ),
      ),
    );

    if (result != null && mounted) {
      final address = result['address'] as String?;
      final latitude = result['latitude'] as double?;
      final longitude = result['longitude'] as double?;

      if (address != null) {
        widget.controller.text = address;
      }

      // Get place details for the selected location
      if (latitude != null && longitude != null) {
        PlaceDetails? placeDetails;
        
        // Try to get place details via reverse geocoding
        try {
          placeDetails = await GooglePlacesService.reverseGeocode(
            latitude,
            longitude,
          );
        } catch (e) {
          // If reverse geocoding fails, create a PlaceDetails from the coordinates and address
          debugPrint('Reverse geocoding failed: $e');
        }

        // If we have place details, use them; otherwise create from coordinates
        if (placeDetails != null && widget.onPlaceSelected != null) {
          widget.onPlaceSelected!(placeDetails);
        } else if (widget.onPlaceSelected != null) {
          // Create a minimal PlaceDetails with just coordinates and address
          final fallbackDetails = PlaceDetails(
            formattedAddress: address ?? '',
            placeId: null,
            latitude: latitude,
            longitude: longitude,
            addressComponents: [],
          );
          widget.onPlaceSelected!(fallbackDetails);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: widget.controller,
        maxLines: widget.maxLines,
        validator: widget.validator,
        onTap: () {
          if (widget.controller.text.length > 2 && _predictions.isNotEmpty) {
            _showOverlay();
          }
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon, color: AppColors.primary),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    Icons.map_outlined,
                    color: AppColors.primary,
                  ),
                  tooltip: 'Select on Map',
                  onPressed: () => _openMapPicker(context),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

