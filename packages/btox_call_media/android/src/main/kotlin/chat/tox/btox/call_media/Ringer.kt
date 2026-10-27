package chat.tox.btox.call_media

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** As the ringer mode allows, for when bTox shows the call itself rather than its notification. */
internal class Ringer(private val context: Context) {
    private val attributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    private val vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
    private var ringtone: Ringtone? = null
    private var ringing = false

    fun start() {
        if (ringing) {
            return
        }
        ringing = true
        val mode = context.getSystemService(AudioManager::class.java).ringerMode
        if (mode == AudioManager.RINGER_MODE_NORMAL) {
            ringtone =
                RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                    ?.apply {
                        audioAttributes = attributes
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            isLooping = true
                        }
                        play()
                    }
        }
        if (mode != AudioManager.RINGER_MODE_SILENT) {
            @Suppress("DEPRECATION")
            vibrator.vibrate(VibrationEffect.createWaveform(VIBRATION, 0), attributes)
        }
    }

    fun stop() {
        if (!ringing) {
            return
        }
        ringing = false
        ringtone?.stop()
        ringtone = null
        vibrator.cancel()
    }

    private companion object {
        // Off, on, off, and over again, in milliseconds.
        val VIBRATION = longArrayOf(0, 1000, 1000)
    }
}
