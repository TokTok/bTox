package chat.tox.btox.call_media

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import java.nio.ByteBuffer

/** Where a call's audio goes. */
internal enum class Route {
    EARPIECE,
    SPEAKER,
    WIRED,
    BLUETOOTH,
}

/**
 * A call's audio: the microphone through the voice communication source,
 * with the echo canceller where there is one, and the friend's voice on the
 * voice call stream, which the echo canceller hears and the earpiece and the
 * in-call volume apply to.
 */
internal class CallAudio(
    context: Context,
    sampleRate: Int,
    private val frameSamples: Int,
    // Where the call goes without a headset: the loudspeaker for video.
    private val speaker: Boolean,
    private val onFrame: (ByteArray) -> Unit,
    private val onRoutes: (Route, Set<Route>) -> Unit,
    // The microphone stopped, as when Android couldn't restore it.
    private val onFailed: () -> Unit,
) {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val attributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
    private val focus =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attributes)
            .build()
    // The screen goes off at the ear.
    private val proximity =
        context.getSystemService(PowerManager::class.java).let { power ->
            if (power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                power.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "btox:call")
            } else {
                null
            }
        }

    private val frameBytes = frameSamples * 2
    private val record =
        AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(
                AudioRecord.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                ),
                frameBytes * 4,
            ),
        )
    // Each releases those before it when it can't be made.
    private val track =
        try {
            AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(
                    maxOf(
                        AudioTrack.getMinBufferSize(
                            sampleRate,
                            AudioFormat.CHANNEL_OUT_MONO,
                            AudioFormat.ENCODING_PCM_16BIT,
                        ),
                        frameBytes * 4,
                    ),
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            record.release()
            throw e
        }
    private val effects = mutableListOf<AudioEffect>()
    private val ringback =
        try {
            ToneGenerator(AudioManager.STREAM_VOICE_CALL, RINGBACK_VOLUME)
        } catch (e: Exception) {
            record.release()
            track.release()
            throw e
        }

    @Volatile private var running = false
    private var reader: Thread? = null

    // The route asked for, until a headset connects.
    private var chosen: Route? = null
    private val devices =
        object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) {
                // As phones do, a headset connecting takes the call.
                if (added.any { routeOf(it.type) in HEADSETS }) {
                    chosen = null
                }
                route()
            }

            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = route()
        }

    fun choose(route: Route) {
        chosen = route
        route()
    }

    /** The tone a call makes while it rings at the friend's. */
    fun ringBack(on: Boolean) {
        if (on) {
            ringback.startTone(ToneGenerator.TONE_SUP_RINGTONE)
        } else {
            ringback.stopTone()
        }
    }

    fun start() {
        try {
            begin()
        } catch (e: Exception) {
            stop()
            throw e
        }
    }

    private fun begin() {
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        audio.requestAudioFocus(focus)
        val session = record.audioSessionId
        if (AcousticEchoCanceler.isAvailable()) {
            AcousticEchoCanceler.create(session)?.let { effects.add(it) }
        }
        if (NoiseSuppressor.isAvailable()) {
            NoiseSuppressor.create(session)?.let { effects.add(it) }
        }
        if (AutomaticGainControl.isAvailable()) {
            AutomaticGainControl.create(session)?.let { effects.add(it) }
        }
        effects.forEach { it.enabled = true }
        audio.registerAudioDeviceCallback(devices, Handler(Looper.getMainLooper()))
        route()
        record.startRecording()
        track.play()
        running = true
        reader =
            Thread({
                    while (running) {
                        val frame = ByteArray(frameBytes)
                        var read = 0
                        while (running && read < frameBytes) {
                            val n = record.read(frame, read, frameBytes - read)
                            if (n < 0) {
                                val failed = running
                                running = false
                                if (failed) {
                                    onFailed()
                                }
                            } else {
                                read += n
                            }
                        }
                        if (read == frameBytes) {
                            onFrame(frame)
                        }
                    }
                }, "btox call audio")
                .also { it.start() }
    }

    /** Plays as much of [pcm] as there's room for, as a call can't wait. */
    fun play(pcm: ByteBuffer) {
        track.write(pcm, pcm.remaining(), AudioTrack.WRITE_NON_BLOCKING)
    }

    fun stop() {
        audio.unregisterAudioDeviceCallback(devices)
        ringback.release()
        running = false
        reader?.join()
        // Each whether or not it started, so the rest is released too.
        if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
            record.stop()
        }
        record.release()
        if (track.playState != AudioTrack.PLAYSTATE_STOPPED) {
            track.stop()
        }
        track.release()
        effects.forEach { it.release() }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audio.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = false
        }
        audio.abandonAudioFocusRequest(focus)
        audio.mode = AudioManager.MODE_NORMAL
        proximity?.let { if (it.isHeld) it.release() }
    }

    private fun route() {
        val devices = available()
        val route =
            chosen?.takeIf { it in devices }
                ?: listOf(Route.BLUETOOTH, Route.WIRED, if (speaker) Route.SPEAKER else Route.EARPIECE)
                    .firstOrNull { it in devices }
                ?: Route.SPEAKER
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            devices[route]?.let { audio.setCommunicationDevice(it) }
        } else {
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = route == Route.SPEAKER
        }
        proximity?.let {
            if (route != Route.EARPIECE && it.isHeld) {
                it.release()
            } else if (route == Route.EARPIECE && !it.isHeld) {
                it.acquire()
            }
        }
        onRoutes(route, devices.keys)
    }

    /**
     * The routes there are, each with the device it uses. Before Android 12,
     * only the earpiece and the loudspeaker: a wired headset takes the place
     * of the earpiece by itself.
     */
    private fun available(): Map<Route, AudioDeviceInfo?> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audio.availableCommunicationDevices
                .mapNotNull { device -> routeOf(device.type)?.let { it to device } }
                .distinctBy { it.first }
                .toMap()
        } else {
            mapOf(Route.EARPIECE to null, Route.SPEAKER to null)
        }

    private companion object {
        const val RINGBACK_VOLUME = 80
        val HEADSETS = setOf(Route.WIRED, Route.BLUETOOTH)

        fun routeOf(type: Int): Route? =
            when (type) {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> Route.EARPIECE
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> Route.SPEAKER
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET -> Route.WIRED
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_HEARING_AID -> Route.BLUETOOTH
                else -> null
            }
    }
}
