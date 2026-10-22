package com.example.testflutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class LocationChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val activityProvider: () -> Activity?
) : MethodChannel.MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

    private val channel = MethodChannel(messenger, "nubibill/location")
    private val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermission" -> {
                val fine = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                val coarse = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                result.success(mapOf("hasFineLocation" to fine, "hasCoarseLocation" to coarse))
            }
            "requestPermission" -> {
                val activity = activityProvider()
                if (activity == null) {
                    result.error("NO_ACTIVITY", "Activity is not available to request permissions.", null)
                    return
                }
                val fine = ContextCompat.checkSelfPermission(
                    activity,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                if (fine) {
                    result.success(mapOf("hasFineLocation" to true, "hasCoarseLocation" to true))
                    return
                }
                pendingPermissionResult = result
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                    ),
                    REQUEST_CODE_LOCATION_PERMISSION
                )
            }
            "getCurrentLocation" -> {
                val fine = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                val coarse = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                if (!fine && !coarse) {
                    result.error("PERMISSION_DENIED", "Location permission is not granted.", null)
                    return
                }
                val forceFresh = call.argument<Boolean>("forceFresh") ?: false
                fetchLocation(forceFresh, result)
            }
            "calculateDistance" -> {
                val lat1 = call.argument<Double>("lat1")
                val lon1 = call.argument<Double>("lon1")
                val lat2 = call.argument<Double>("lat2")
                val lon2 = call.argument<Double>("lon2")
                if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
                    result.error("INVALID_ARGUMENTS", "Latitude and longitude for both points are required.", null)
                    return
                }
                val results = FloatArray(1)
                Location.distanceBetween(lat1, lon1, lat2, lon2, results)
                result.success(results[0].toDouble())
            }
            "isLocationServiceEnabled" -> {
                val gps = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
                val network = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
                result.success(gps || network)
            }
            else -> result.notImplemented()
        }
    }

    private fun fetchLocation(forceFresh: Boolean, result: MethodChannel.Result) {
        val now = System.currentTimeMillis()
        var bestLocation: Location? = null

        // 1. Check last known location from providers
        try {
            val gpsLoc = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val netLoc = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            val candidates = listOfNotNull(gpsLoc, netLoc)
            for (loc in candidates) {
                if (bestLocation == null || loc.time > bestLocation.time) {
                    bestLocation = loc
                }
            }
        } catch (e: SecurityException) {
            result.error("SECURITY_EXCEPTION", "Permission lost while querying last known location: ${e.message}", null)
            return
        }

        // If not forceFresh and last known location is fresh (< 2 minutes old), return it immediately
        if (!forceFresh && bestLocation != null && (now - bestLocation.time) < 120_000L) {
            result.success(locationToMap(bestLocation))
            return
        }

        // 2. Request fresh location update with timeout
        val listener = object : LocationListener {
            private var completed = false

            fun finish(loc: Location?) {
                if (completed) return
                completed = true
                try {
                    locationManager.removeUpdates(this)
                } catch (_: Exception) {}

                if (loc != null) {
                    result.success(locationToMap(loc))
                } else if (bestLocation != null) {
                    // Fall back to best known location even if older than 2 minutes
                    result.success(locationToMap(bestLocation))
                } else {
                    result.error("LOCATION_UNAVAILABLE", "Unable to obtain fresh GPS location. Ensure location is enabled with clear sky view.", null)
                }
            }

            override fun onLocationChanged(location: Location) {
                finish(location)
            }

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }

        var requested = false
        try {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    0L,
                    0f,
                    listener,
                    Looper.getMainLooper()
                )
                requested = true
            }
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    0L,
                    0f,
                    listener,
                    Looper.getMainLooper()
                )
                requested = true
            }
        } catch (e: SecurityException) {
            result.error("SECURITY_EXCEPTION", "Permission lost while requesting location updates: ${e.message}", null)
            return
        }

        if (!requested) {
            if (bestLocation != null) {
                result.success(locationToMap(bestLocation))
            } else {
                result.error("LOCATION_DISABLED", "Location services are disabled on this device.", null)
            }
            return
        }

        // Timeout fallback after 10 seconds
        mainHandler.postDelayed({
            listener.finish(null)
        }, 10_000L)
    }

    private fun locationToMap(location: Location): Map<String, Any> {
        val isMock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            location.isMock
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            @Suppress("DEPRECATION")
            location.isFromMockProvider
        } else {
            false
        }

        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracy" to location.accuracy.toDouble(),
            "time" to location.time,
            "isMock" to isMock,
            "provider" to (location.provider ?: "unknown"),
            "elapsedRealtimeNanos" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                location.elapsedRealtimeNanos
            } else {
                0L
            })
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == REQUEST_CODE_LOCATION_PERMISSION) {
            val callback = pendingPermissionResult
            pendingPermissionResult = null
            if (callback != null) {
                val fine = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                val coarse = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                callback.success(mapOf("hasFineLocation" to fine, "hasCoarseLocation" to coarse))
            }
            return true
        }
        return false
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pendingPermissionResult = null
    }

    companion object {
        const val REQUEST_CODE_LOCATION_PERMISSION = 2001
    }
}
