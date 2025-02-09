import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show VoidCallback;
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';

import '../classes.dart';

/// Simple class that manages Mapbox creation & annotation logic
class MapManager {
  late MapboxMap _mapboxMap;
  late PointAnnotationManager _pointAnnotationManager;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  //variables for checking status of various items
  final VoidCallback onPlotComplete;
  Timer? _rotationTimer;
  Timer? _interactionTimer;
  bool _userInteracted = false;
  bool _viewingTrip = false;
  double _rotationAngle = 0.0;
  CameraState? _lastCameraState; //state of camera after user interaction
  double _previousZoomLevel = 1.5;

/// Callback for any post-plot logic
  MapManager({required this.onPlotComplete});

  /// Called once MapWidget is created
  void initializeMapManager(MapboxMap map) {
    if (_isInitialized) {
      print("MapManager is already initialized. Skipping re-initialization.");
      return;
    }

    _mapboxMap = map;
    _mapboxMap.annotations.createPointAnnotationManager().then((manager) {
      _pointAnnotationManager = manager;
      _isInitialized = true;
      print("MapManager initialized successfully.");

      //Style options

       // Disable the compass and scale bar
      _mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
      _mapboxMap.logo.updateSettings(LogoSettings(enabled: false));
      _mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));


      // Start rotating the globe
      _startRotatingGlobe();

      // Detect user interactions and stop rotation
      _mapboxMap.setOnMapMoveListener((point) => _handleUserInteraction());
      _mapboxMap.setOnMapTapListener((point) => _handleUserInteraction());

      print("Map interaction listeners added.");
    }).catchError((err) => print("Error creating manager: $err"));
  }

void _startRotatingGlobe() async {
    if (_viewingTrip) {
      print("Currently viewing a trip. Rotation disabled.");
      return;
    }

    _rotationTimer?.cancel(); // Cancel any previous timers
    _lastCameraState = await _mapboxMap.getCameraState();

    double initialLongitude =
        (_lastCameraState?.center?.coordinates.lng ?? 0.0).toDouble();
    double initialLatitude =
        (_lastCameraState?.center?.coordinates.lat ?? 0.0).toDouble();
    double initialZoom = _lastCameraState?.zoom ?? 2.0;

    double rotationSpeed = 0.15; // Adjust rotation speed

    _rotationTimer = Timer.periodic(Duration(milliseconds: 100), (timer) async {
      if (_userInteracted || _viewingTrip) {
        timer.cancel();
        print("User interacted or viewing trip, stopping rotation.");
        return;
      }

      _lastCameraState = await _mapboxMap.getCameraState();
      double currentLongitude =
          _lastCameraState?.center?.coordinates.lng.toDouble() ??
              initialLongitude;
      double currentLatitude =
          _lastCameraState?.center?.coordinates.lat.toDouble() ??
              initialLatitude;
      double currentZoom = _lastCameraState?.zoom ?? initialZoom;

      double newLongitude = currentLongitude + rotationSpeed;
      if (newLongitude > 180) newLongitude -= 360; // Wrap around the globe

      _mapboxMap.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(newLongitude, currentLatitude)),
          zoom: currentZoom, // Keep zoom level fixed to view the whole globe
        ),
      );
    });

    print("Globe rotation started.");
  }

  void _handleUserInteraction() {
    if (_viewingTrip) return; // Don't stop rotation if viewing trip

    _userInteracted = true;
    _rotationTimer?.cancel();
    print("User interaction detected. Stopping rotation.");

    _interactionTimer?.cancel();
    _interactionTimer = Timer(Duration(seconds: 5), () {
      if (!_viewingTrip) {
        print("Resuming globe rotation after inactivity.");
        _userInteracted = false;
        _startRotatingGlobe();
      }
    });
  }


void setViewingTrip(bool isViewing) {
    _viewingTrip = isViewing;
    if (_viewingTrip) {
      print("Viewing trip, stopping auto-rotation.");
      _rotationTimer?.cancel();
    } else {
      print("Exited trip view, resuming auto-rotation.");
      _startRotatingGlobe();
    }
  }

  void resumeAutoRotation() {
    if (!_userInteracted && !_viewingTrip) {
      print("Resuming auto-rotation.");
      _startRotatingGlobe();
    }
  }

  /// Plot a list of photo locations
  Future<void> plotLocationsOnMap(List<Location> locations) async {
    if (!isInitialized) {
      print("MapManager not initialized yet.");
      return;
    }

    try {
      print("Starting to plot ${locations.length} locations...");

      // Clear existing markers
      await _pointAnnotationManager.deleteAll();
      print("Deleted existing markers.");

      List<Location> validLocations = locations
          .where((loc) => loc.latitude != 0.0 && loc.longitude != 0.0)
          .toList();

      if (validLocations.isEmpty) {
        print("No valid locations to plot.");
        return;
      }

      for (var loc in validLocations) {
        try {
          final ByteData bytes = await rootBundle.load('lib/assets/pin.png');
          final Uint8List imageData = bytes.buffer.asUint8List();

          await _pointAnnotationManager.create(
            PointAnnotationOptions(
              geometry:
                  Point(coordinates: Position(loc.longitude, loc.latitude)),
              image: imageData,
              iconSize: 0.05,
            ),
          );

          print("Plotted pin at (${loc.latitude}, ${loc.longitude})");
        } catch (e) {
          print(
              'Error creating marker at (${loc.latitude}, ${loc.longitude}): $e');
        }
      }

      print("Pins plotted successfully.");

      onPlotComplete();
    } catch (e) {
      print("Error plotting locations: $e");
    }
  }



  Future<void> flyToLocation(double latitude, double longitude) async {
    if (!_isInitialized) {
      print("MapManager not initialized yet.");
      return;
    }

    // Store the current zoom level before zooming in
    _previousZoomLevel = _lastCameraState?.zoom ?? 1.5;

    print("Flying to location: Lat $latitude, Lon $longitude");
    _viewingTrip = true;

    await _mapboxMap.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: 8.0, // Zoom in for closer view
        pitch: 45.0,
      ),
      MapAnimationOptions(duration: 3000, startDelay: 0),
    );
  }

  // New function to zoom back out after exiting trip view
  Future<void> zoomBackOut() async {
    if (!_isInitialized) {
      print("MapManager not initialized yet.");
      return;
    }

    print("Zooming back out to previous zoom level: $_previousZoomLevel");
    _viewingTrip = false;

    await _mapboxMap.flyTo(
      CameraOptions(
        zoom: _previousZoomLevel, // Restore previous zoom level
        pitch: 0.0, // Reset tilt
      ),
      MapAnimationOptions(duration: 2000, startDelay: 0),
    );

    _startRotatingGlobe();
  }

}
