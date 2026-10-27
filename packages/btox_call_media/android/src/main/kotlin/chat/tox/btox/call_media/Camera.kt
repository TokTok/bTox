package chat.tox.btox.call_media

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.display.DisplayManager
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.view.Display
import kotlin.math.abs

internal class I420(val width: Int, val height: Int, val data: ByteArray) {
    companion object {
        fun size(width: Int, height: Int) = width * height + 2 * ((width + 1) / 2) * ((height + 1) / 2)
    }
}

/** Upright frames as the screen turns, near [WIDTH] by [HEIGHT], at most [MAX_FPS] a second. */
internal class Camera(
    private val context: Context,
    private val front: Boolean,
    private val onFrame: (I420) -> Unit,
    // When it stops by itself, such as when another app takes it.
    private val onFailed: () -> Unit,
) {
    private val manager = context.getSystemService(CameraManager::class.java)
    private val display = context.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
    private val thread = HandlerThread("btox camera").apply { start() }
    private val handler = Handler(thread.looper)
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var sensorOrientation = 0
    private var lastFrame = 0L
    @Volatile private var stopped = false
    // While the camera opens, its thread waits to hear how it went.
    @Volatile private var opening = false

    fun start() {
        try {
            open()
        } catch (e: Exception) {
            opening = false
            stop()
            throw e
        }
    }

    @SuppressLint("MissingPermission") // The UI asked for it.
    private fun open() {
        val id =
            manager.cameraIdList.firstOrNull { id ->
                val facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
                facing == if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
            } ?: manager.cameraIdList.firstOrNull() ?: throw IllegalStateException("No camera")
        val characteristics = manager.getCameraCharacteristics(id)
        sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val size =
            characteristics
                .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
                .getOutputSizes(ImageFormat.YUV_420_888)
                .minBy { abs(it.width * it.height - WIDTH * HEIGHT) + abs(it.width * HEIGHT - it.height * WIDTH) }
        val fps =
            characteristics
                .get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?.filter { it.upper <= MAX_FPS }
                ?.maxWithOrNull(compareBy<Range<Int>> { it.upper }.thenByDescending { it.lower })
        val reader =
            ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2).also { this.reader = it }
        reader.setOnImageAvailableListener({ it.acquireLatestImage()?.use(::deliver) }, handler)
        opening = true
        manager.openCamera(
            id,
            object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    opening = false
                    if (stopped) {
                        camera.close()
                        release()
                        return
                    }
                    device = camera
                    val request =
                        camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                            addTarget(reader.surface)
                            fps?.let { set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it) }
                        }
                    @Suppress("DEPRECATION") // The replacement needs Android 9.
                    camera.createCaptureSession(
                        listOf(reader.surface),
                        object : CameraCaptureSession.StateCallback() {
                            override fun onConfigured(session: CameraCaptureSession) {
                                if (stopped) {
                                    return
                                }
                                this@Camera.session = session
                                session.setRepeatingRequest(request.build(), null, handler)
                            }

                            override fun onConfigureFailed(session: CameraCaptureSession) {
                                Log.w(TAG, "Camera session not configured")
                                failed()
                            }
                        },
                        handler,
                    )
                }

                override fun onDisconnected(camera: CameraDevice) {
                    opening = false
                    camera.close()
                    failed()
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.w(TAG, "Camera error $error")
                    opening = false
                    camera.close()
                    failed()
                }
            },
            handler,
        )
    }

    private fun failed() {
        if (stopped) {
            release()
        } else {
            onFailed()
        }
    }

    fun stop() {
        stopped = true
        handler.post {
            session?.close()
            device?.close()
            // Else the camera is closed once it has opened.
            if (!opening) {
                release()
            }
        }
    }

    private fun release() {
        reader?.close()
        thread.quitSafely()
    }

    private fun deliver(image: Image) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastFrame < 1000 / MAX_FPS) {
            return
        }
        lastFrame = now
        val turned = display.rotation * 90
        val rotation = if (front) (sensorOrientation + turned) % 360 else (sensorOrientation - turned + 360) % 360
        onFrame(toI420(image, rotation))
    }

    private companion object {
        const val TAG = "btox camera"
        const val WIDTH = 640
        const val HEIGHT = 480
        const val MAX_FPS = 24

        /** [image] turned [rotation] degrees clockwise. */
        fun toI420(image: Image, rotation: Int): I420 {
            val (width, height) = if (rotation % 180 == 0) image.width to image.height else image.height to image.width
            val frame = I420(width, height, ByteArray(I420.size(width, height)))
            var at = 0
            for ((index, plane) in image.planes.withIndex()) {
                val sub = if (index == 0) 1 else 2
                val srcWidth = (image.width + sub - 1) / sub
                val srcHeight = (image.height + sub - 1) / sub
                val buffer = plane.buffer
                val src = ByteArray(buffer.remaining()).also { buffer.get(it) }
                val row = plane.rowStride
                val pixel = plane.pixelStride
                val dstWidth = if (rotation % 180 == 0) srcWidth else srcHeight
                val dstHeight = if (rotation % 180 == 0) srcHeight else srcWidth
                val lastRow = (srcHeight - 1) * row
                val lastPixel = (srcWidth - 1) * pixel
                val (start, dx, dy) =
                    when (rotation) {
                        90 -> Triple(lastRow, -row, pixel)
                        180 -> Triple(lastRow + lastPixel, -pixel, -row)
                        270 -> Triple(lastPixel, row, -pixel)
                        else -> Triple(0, pixel, row)
                    }
                for (y in 0 until dstHeight) {
                    var from = start + y * dy
                    for (x in 0 until dstWidth) {
                        frame.data[at++] = src[from]
                        from += dx
                    }
                }
            }
            return frame
        }
    }
}
