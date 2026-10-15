package chat.tox.btox.call_media

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryCodec
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.nio.ByteBuffer

/**
 * Call audio and video for bTox. Each Flutter engine has its own: the background
 * service's runs the audio and rings, the UI's shows the call over the lock
 * screen and asks for the permissions calls need.
 */
class CallMediaPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var frames: EventChannel
    private lateinit var routes: EventChannel
    private lateinit var cameraFrames: EventChannel
    private lateinit var ringer: Ringer
    private lateinit var playback: BasicMessageChannel<ByteBuffer>
    private val main = Handler(Looper.getMainLooper())
    private val frameSink = Sink()
    private val routeSink = Sink()
    private val cameraSink = Sink()
    private var activity: ActivityPluginBinding? = null
    private var asking: MethodChannel.Result? = null
    private var audio: CallAudio? = null
    private var camera: Camera? = null
    // The call's foreground service notification, to start it again for the camera.
    private var service: Pair<String, String>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "btox_call_media")
        methods.setMethodCallHandler(this)
        frames = EventChannel(binding.binaryMessenger, "btox_call_media/frames")
        frames.setStreamHandler(frameSink)
        routes = EventChannel(binding.binaryMessenger, "btox_call_media/routes")
        routes.setStreamHandler(routeSink)
        cameraFrames = EventChannel(binding.binaryMessenger, "btox_call_media/camera")
        cameraFrames.setStreamHandler(cameraSink)
        ringer = Ringer(context)
        playback = BasicMessageChannel(binding.binaryMessenger, "btox_call_media/play", BinaryCodec.INSTANCE)
        playback.setMessageHandler { pcm, reply ->
            pcm?.let { audio?.play(it) }
            reply.reply(null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        ringer.stop()
        methods.setMethodCallHandler(null)
        frames.setStreamHandler(null)
        routes.setStreamHandler(null)
        cameraFrames.setStreamHandler(null)
        playback.setMessageHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (!has(Manifest.permission.RECORD_AUDIO)) {
                    result.error("permission", "No microphone permission", null)
                    return
                }
                stop()
                try {
                    val service = Pair<String, String>(call.argument("title")!!, call.argument("channel")!!)
                    this.service = service
                    CallService.start(context, service.first, service.second, camera = false)
                    audio =
                        CallAudio(
                                context,
                                call.argument("sampleRate")!!,
                                call.argument("frameSamples")!!,
                                speaker = call.argument("speaker")!!,
                                onFrame = { frame -> main.post { frameSink.events?.success(frame) } },
                                onRoutes = { route, available ->
                                    routeSink.events?.success(
                                        listOf(route.ordinal, available.map { it.ordinal }),
                                    )
                                },
                                onFailed = {
                                    main.post { frameSink.events?.error("microphone", "The microphone stopped", null) }
                                },
                            )
                            .also { it.start() }
                    result.success(null)
                } catch (e: Exception) {
                    // No microphone, or one another app holds.
                    stop()
                    result.error("audio", e.message, null)
                }
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            "setRoute" -> {
                audio?.choose(Route.entries[call.argument("route")!!])
                result.success(null)
            }
            "setRingBack" -> {
                audio?.ringBack(call.argument("on")!!)
                result.success(null)
            }
            "setRinging" -> {
                if (call.argument<Boolean>("on")!!) ringer.start() else ringer.stop()
                result.success(null)
            }
            "startCamera" -> {
                if (!has(Manifest.permission.CAMERA)) {
                    result.error("permission", "No camera permission", null)
                    return
                }
                stopCamera()
                try {
                    service?.let { CallService.start(context, it.first, it.second, camera = true) }
                    camera =
                        Camera(
                                context,
                                call.argument("front")!!,
                                onFrame = { frame ->
                                    main.post {
                                        cameraSink.events?.success(listOf(frame.width, frame.height, frame.data))
                                    }
                                },
                                onFailed = {
                                    main.post {
                                        stopCamera()
                                        cameraSink.events?.error("camera", "The camera stopped", null)
                                    }
                                },
                            )
                            .also { it.start() }
                    result.success(null)
                } catch (e: Exception) {
                    // No camera, or one another app holds.
                    camera = null
                    if (audio != null) {
                        service?.let { CallService.start(context, it.first, it.second, camera = false) }
                    }
                    result.error("camera", e.message, null)
                }
            }
            "stopCamera" -> {
                stopCamera()
                result.success(null)
            }
            "canRingOverLockScreen" -> result.success(canRingOverLockScreen())
            "allowRingingOverLockScreen" -> {
                allowRingingOverLockScreen()
                result.success(null)
            }
            "showOverLockScreen" -> {
                showOverLockScreen(call.argument("on")!!)
                result.success(null)
            }
            "requestPermissions" -> requestPermissions(call.argument("camera")!!, result)
            else -> result.notImplemented()
        }
    }

    private fun stopCamera() {
        camera?.stop()
        if (camera != null && audio != null) {
            service?.let { CallService.start(context, it.first, it.second, camera = false) }
        }
        camera = null
    }

    /** Ends the call's media, and its service if this engine started it. */
    private fun stop() {
        camera?.stop()
        camera = null
        audio?.stop()
        audio = null
        if (service != null) {
            CallService.stop(context)
            service = null
        }
    }

    private fun has(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** The microphone, and the [camera] too, asking for what bTox may not use yet. */
    private fun requestPermissions(camera: Boolean, result: MethodChannel.Result) {
        val needed =
            listOfNotNull(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA.takeIf { camera })
                .filterNot(::has)
        val activity = activity?.activity
        if (needed.isEmpty() || activity == null) {
            result.success(needed.isEmpty())
            return
        }
        asking?.success(false)
        asking = result
        activity.requestPermissions(needed.toTypedArray(), REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST) {
            return false
        }
        asking?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        asking = null
        return true
    }

    private fun showOverLockScreen(on: Boolean) {
        val activity = activity?.activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(on)
            activity.setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags =
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) activity.window.addFlags(flags) else activity.window.clearFlags(flags)
        }
    }

    /** Since Android 14, the user may not let an app ring full screen. */
    private fun canRingOverLockScreen() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    private fun allowRingingOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private class Sink : EventChannel.StreamHandler {
        var events: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            this.events = events
        }

        override fun onCancel(arguments: Any?) {
            events = null
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
        const val REQUEST = 0xca11
    }
}
