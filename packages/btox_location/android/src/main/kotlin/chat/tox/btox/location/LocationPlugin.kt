package chat.tox.btox.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Where the device is, from Android's own location services rather than
 * Google Play services.
 */
class LocationPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var locations: LocationManager
    private lateinit var methods: MethodChannel
    private val main = Handler(Looper.getMainLooper())
    private var activity: ActivityPluginBinding? = null
    private var asking: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        locations = context.getSystemService(LocationManager::class.java)
        methods = MethodChannel(binding.binaryMessenger, "btox_location")
        methods.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isLocationServiceEnabled" -> result.success(enabled())
            "checkPermission" -> result.success(if (granted()) GRANTED else DENIED)
            "requestPermission" -> requestPermission(result)
            "getCurrentPosition" -> getCurrentPosition(result)
            "openAppSettings" -> result.success(
                open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))),
            )
            "openLocationSettings" -> result.success(open(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)))
            else -> result.notImplemented()
        }
    }

    private fun enabled() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) locations.isLocationEnabled else providers().isNotEmpty()

    private fun granted() = context.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        val activity = activity?.activity
        if (granted() || activity == null) {
            result.success(if (granted()) GRANTED else DENIED)
            return
        }
        asking?.success(DENIED)
        asking = result
        activity.requestPermissions(arrayOf(PERMISSION), REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST) {
            return false
        }
        // Where Android no longer explains why to allow it, it won't ask again.
        asking?.success(
            when {
                granted() -> GRANTED
                activity?.activity?.shouldShowRequestPermissionRationale(PERMISSION) == true -> DENIED
                else -> DENIED_FOREVER
            },
        )
        asking = null
        return true
    }

    /** The location providers on, the fused one first where there is one. */
    private fun providers(): List<String> {
        val on = locations.getProviders(true)
        return listOfNotNull(
            LocationManager.FUSED_PROVIDER.takeIf { Build.VERSION.SDK_INT >= Build.VERSION_CODES.S },
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
        ).filter { it in on }
    }

    /** Answers with the first fix any provider gets, as GPS gets none indoors. */
    @SuppressLint("MissingPermission")
    private fun getCurrentPosition(result: MethodChannel.Result) {
        val providers = providers()
        if (!granted() || providers.isEmpty()) {
            result.error(UNAVAILABLE, "No location permission or provider", null)
            return
        }
        val fix =
            object : LocationListener, Runnable {
                var done = false

                fun finish(location: Location?) {
                    if (done) {
                        return
                    }
                    done = true
                    locations.removeUpdates(this)
                    main.removeCallbacks(this)
                    if (location == null) {
                        result.error(UNAVAILABLE, "No location fix", null)
                    } else {
                        result.success(position(location))
                    }
                }

                override fun onLocationChanged(location: Location) = finish(location)

                override fun run() = finish(null)

                // Abstract before Android 11, which calls them.
                @Suppress("OVERRIDE_DEPRECATION")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

                override fun onProviderEnabled(provider: String) {}

                override fun onProviderDisabled(provider: String) {}
            }
        for (provider in providers) {
            locations.requestLocationUpdates(provider, 0, 0f, fix, Looper.getMainLooper())
        }
        main.postDelayed(fix, TIMEOUT_MS)
    }

    private fun position(location: Location): Map<String, Any> {
        val oreo = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "timestamp" to location.time,
            "accuracy" to location.accuracy.toDouble(),
            "altitude" to location.altitude,
            "altitudeAccuracy" to if (oreo) location.verticalAccuracyMeters.toDouble() else 0.0,
            "heading" to location.bearing.toDouble(),
            "headingAccuracy" to if (oreo) location.bearingAccuracyDegrees.toDouble() else 0.0,
            "speed" to location.speed.toDouble(),
            "speedAccuracy" to if (oreo) location.speedAccuracyMetersPerSecond.toDouble() else 0.0,
            "isMocked" to
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    location.isMock
                } else {
                    @Suppress("DEPRECATION")
                    location.isFromMockProvider
                },
        )
    }

    private fun open(intent: Intent): Boolean {
        val activity = activity?.activity
        return try {
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
    }

    private companion object {
        const val PERMISSION = Manifest.permission.ACCESS_FINE_LOCATION
        const val REQUEST = 0x10ca
        const val TIMEOUT_MS = 30_000L
        const val UNAVAILABLE = "unavailable"

        // LocationPermission's names in geolocator_platform_interface.
        const val GRANTED = "whileInUse"
        const val DENIED = "denied"
        const val DENIED_FOREVER = "deniedForever"
    }
}
