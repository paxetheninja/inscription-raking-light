import 'package:geolocator/geolocator.dart';

import '../sidecar/sidecar_schema.dart';

/// Result of an attempted location fix.
sealed class LocationResult {
  const LocationResult();
}

class LocationOk extends LocationResult {
  const LocationOk(this.value);
  final SidecarLocation value;
}

class LocationDenied extends LocationResult {
  const LocationDenied(this.message);
  final String message;
}

class LocationDisabled extends LocationResult {
  const LocationDisabled();
}

class LocationTimedOut extends LocationResult {
  const LocationTimedOut();
}

class LocationError extends LocationResult {
  const LocationError(this.message);
  final String message;
}

/// Request a single GPS fix with permission handling. Never throws; returns
/// a typed [LocationResult] so the caller can display a precise reason if
/// the fix didn't come through.
Future<LocationResult> tryFetchLocation({
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationDisabled();
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return const LocationDenied(
          'Location permission denied. Tap the location chip again to retry.');
    }
    if (perm == LocationPermission.deniedForever) {
      return const LocationDenied(
          'Location permission denied permanently. Enable it for Stela in '
          'system Settings to use this feature.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return LocationOk(SidecarLocation(
      lat: pos.latitude,
      lon: pos.longitude,
      timestampMs: pos.timestamp.millisecondsSinceEpoch,
      accuracyM: pos.accuracy,
      altitudeM: pos.altitude,
    ));
  } catch (e) {
    final s = e.toString().toLowerCase();
    if (s.contains('time') && s.contains('exceeded')) {
      return const LocationTimedOut();
    }
    return LocationError(e.toString());
  }
}
