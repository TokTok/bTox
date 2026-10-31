#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <speex/speex_echo.h>
#include <speex/speex_preprocess.h>

#include "btox_call_media.h"
#include "miniaudio.h"
#include "session.h"

/* How long after a sound the echo canceller still looks for its echo. */
#define ECHO_TAIL_MS 250

/* How much of the friend's audio may wait to be played. */
#define PLAYBACK_MS 80

/* The echo canceller works on blocks this long. */
#define BLOCK_MS 10

#define PI 3.14159265358979323846

/* A tone of two frequencies, on and off in turns, in milliseconds. */
typedef struct Tone {
  double frequencies[2];
  double volume;
  uint32_t cadence[4];
} Tone;

/* Of a call ringing at the friend's, as phones play it. */
static const Tone ring_back_tone = {{440, 480}, 0.1, {2000, 4000, 0, 0}};

/* Of a call ringing here. */
static const Tone ringing_tone = {{400, 450}, 0.25, {400, 200, 400, 2000}};

static int16_t tone_sample(const Tone *tone, uint64_t n, uint32_t sample_rate) {
  const uint32_t period =
      tone->cadence[0] + tone->cadence[1] + tone->cadence[2] + tone->cadence[3];
  const uint32_t at = (uint32_t)(n * 1000 / sample_rate % period);
  if (at >= tone->cadence[0] &&
      (at < tone->cadence[0] + tone->cadence[1] ||
       at >= tone->cadence[0] + tone->cadence[1] + tone->cadence[2])) {
    return 0;
  }
  const double t = (double)n / sample_rate;
  return (int16_t)(32767 * tone->volume / 2 *
                   (sin(2 * PI * tone->frequencies[0] * t) +
                    sin(2 * PI * tone->frequencies[1] * t)));
}

static struct {
  bool running;
  ma_context context;
  ma_device device;
  uint32_t sample_rate;
  ma_pcm_rb playback;
  SpeexEchoState *echo;
  SpeexPreprocessState *preprocess;
  /* The block the echo canceller works on next: what the microphone heard,
   * and what the speaker played meanwhile. */
  int16_t *heard;
  int16_t *played;
  int16_t *clean;
  uint32_t block;
  uint32_t block_fill;
  /* The frame the microphone's clean sound goes to next. */
  int16_t *frame;
  uint32_t frame_samples;
  uint32_t frame_fill;
  btox_audio_frame_cb *on_frame;
  volatile bool ring_back;
  uint64_t ring_back_at;
} call;

static struct {
  bool running;
  ma_context context;
  ma_device device;
  uint64_t at;
} ringing;

static void deliver(const int16_t *clean, uint32_t samples) {
  while (samples > 0) {
    uint32_t n = call.frame_samples - call.frame_fill;
    if (n > samples) {
      n = samples;
    }
    memcpy(call.frame + call.frame_fill, clean, n * sizeof(int16_t));
    call.frame_fill += n;
    clean += n;
    samples -= n;
    if (call.frame_fill == call.frame_samples) {
      int16_t *frame = malloc(call.frame_samples * sizeof(int16_t));
      if (frame != NULL) {
        memcpy(frame, call.frame, call.frame_samples * sizeof(int16_t));
        call.on_frame(frame, (int32_t)call.frame_samples);
      }
      call.frame_fill = 0;
    }
  }
}

static void on_call_audio(ma_device *device, void *output, const void *input,
                          ma_uint32 frames) {
  (void)device;
  int16_t *out = output;
  ma_uint32 played = 0;
  while (played < frames) {
    ma_uint32 n = frames - played;
    void *buffer;
    if (ma_pcm_rb_acquire_read(&call.playback, &n, &buffer) != MA_SUCCESS ||
        n == 0) {
      break;
    }
    memcpy(out + played, buffer, n * sizeof(int16_t));
    ma_pcm_rb_commit_read(&call.playback, n);
    played += n;
  }
  memset(out + played, 0, (frames - played) * sizeof(int16_t));
  if (call.ring_back) {
    for (ma_uint32 i = 0; i < frames; ++i) {
      out[i] =
          tone_sample(&ring_back_tone, call.ring_back_at++, call.sample_rate);
    }
  }

  const int16_t *in = input;
  for (ma_uint32 i = 0; i < frames;) {
    ma_uint32 n = call.block - call.block_fill;
    if (n > frames - i) {
      n = frames - i;
    }
    memcpy(call.heard + call.block_fill, in + i, n * sizeof(int16_t));
    memcpy(call.played + call.block_fill, out + i, n * sizeof(int16_t));
    call.block_fill += n;
    i += n;
    if (call.block_fill == call.block) {
      speex_echo_cancellation(call.echo, call.heard, call.played, call.clean);
      speex_preprocess_run(call.preprocess, call.clean);
      deliver(call.clean, call.block);
      call.block_fill = 0;
    }
  }
}

static void free_call(void) {
  if (call.echo != NULL) {
    speex_echo_state_destroy(call.echo);
  }
  if (call.preprocess != NULL) {
    speex_preprocess_state_destroy(call.preprocess);
  }
  free(call.heard);
  free(call.played);
  free(call.clean);
  free(call.frame);
  memset(&call, 0, sizeof(call));
}

/* The first error the sound system told of, which is the most specific. */
static char logged_error[256];

static void on_log(void *user_data, ma_uint32 level, const char *message) {
  (void)user_data;
  if (level == MA_LOG_LEVEL_ERROR && logged_error[0] == '\0') {
    snprintf(logged_error, sizeof(logged_error), "%.*s",
             (int)strcspn(message, "\n"), message);
  }
}

const char *btox_audio_start(int32_t sample_rate, int32_t frame_samples,
                             bool speaker, btox_audio_frame_cb *on_frame,
                             btox_routes_cb *on_routes) {
  static char error[512];
  const char *failed;
  ma_result result = MA_OUT_OF_MEMORY;
  btox_audio_stop();
  logged_error[0] = '\0';
  call.sample_rate = (uint32_t)sample_rate;
  call.block = (uint32_t)sample_rate * BLOCK_MS / 1000;
  call.frame_samples = (uint32_t)frame_samples;
  call.on_frame = on_frame;
  call.heard = malloc(call.block * sizeof(int16_t));
  call.played = malloc(call.block * sizeof(int16_t));
  call.clean = malloc(call.block * sizeof(int16_t));
  call.frame = malloc(call.frame_samples * sizeof(int16_t));
  call.echo =
      speex_echo_state_init((int)call.block, sample_rate * ECHO_TAIL_MS / 1000);
  call.preprocess = speex_preprocess_state_init((int)call.block, sample_rate);
  if (call.heard == NULL || call.played == NULL || call.clean == NULL ||
      call.frame == NULL || call.echo == NULL || call.preprocess == NULL) {
    failed = "echo canceller";
    goto no_playback;
  }
  speex_echo_ctl(call.echo, SPEEX_ECHO_SET_SAMPLING_RATE, &sample_rate);
  speex_preprocess_ctl(call.preprocess, SPEEX_PREPROCESS_SET_ECHO_STATE,
                       call.echo);
  int on = 1;
  speex_preprocess_ctl(call.preprocess, SPEEX_PREPROCESS_SET_DENOISE, &on);
  speex_preprocess_ctl(call.preprocess, SPEEX_PREPROCESS_SET_AGC, &on);

  result = ma_pcm_rb_init(ma_format_s16, 1,
                          (ma_uint32)sample_rate * PLAYBACK_MS / 1000, NULL,
                          NULL, &call.playback);
  if (result != MA_SUCCESS) {
    failed = "playback buffer";
    goto no_playback;
  }
  if (!btox_session_start(speaker, on_routes)) {
    failed = "audio session";
    goto no_session;
  }
  ma_context_config context_config = ma_context_config_init();
  /* The session set it up. */
  context_config.coreaudio.sessionCategory = ma_ios_session_category_none;
  context_config.coreaudio.noAudioSessionActivate = MA_TRUE;
  result = ma_context_init(NULL, 0, &context_config, &call.context);
  if (result != MA_SUCCESS) {
    failed = "audio context";
    goto no_context;
  }
  ma_log_register_callback(ma_context_get_log(&call.context),
                           ma_log_callback_init(on_log, NULL));
  ma_device_config config = ma_device_config_init(ma_device_type_duplex);
  config.sampleRate = (ma_uint32)sample_rate;
  config.capture.format = ma_format_s16;
  config.capture.channels = 1;
  config.playback.format = ma_format_s16;
  config.playback.channels = 1;
  config.periodSizeInMilliseconds = BLOCK_MS;
  config.dataCallback = on_call_audio;
  result = ma_device_init(&call.context, &config, &call.device);
  if (result != MA_SUCCESS) {
    failed = "opening the audio device";
    goto no_device;
  }
  result = ma_device_start(&call.device);
  if (result != MA_SUCCESS) {
    failed = "starting the audio device";
    goto not_started;
  }
  call.running = true;
  return NULL;

not_started:
  ma_device_uninit(&call.device);
no_device:
  ma_context_uninit(&call.context);
no_context:
  btox_session_stop();
no_session:
  ma_pcm_rb_uninit(&call.playback);
no_playback:
  free_call();
  if (result == MA_SUCCESS) {
    return failed;
  }
  snprintf(error, sizeof(error), "%s: %s%s%s", failed,
           ma_result_description(result), logged_error[0] ? ": " : "",
           logged_error);
  return error;
}

void btox_audio_play(const int16_t *pcm, int32_t samples) {
  if (!call.running) {
    return;
  }
  ma_uint32 written = 0;
  while (written < (ma_uint32)samples) {
    ma_uint32 n = (ma_uint32)samples - written;
    void *buffer;
    if (ma_pcm_rb_acquire_write(&call.playback, &n, &buffer) != MA_SUCCESS ||
        n == 0) {
      break;
    }
    memcpy(buffer, pcm + written, n * sizeof(int16_t));
    ma_pcm_rb_commit_write(&call.playback, n);
    written += n;
  }
}

void btox_audio_set_route(int32_t route) {
  if (call.running) {
    btox_session_set_route((Btox_Route)route);
  }
}

void btox_audio_set_ring_back(bool on) {
  call.ring_back_at = 0;
  call.ring_back = on;
}

void btox_audio_stop(void) {
  if (!call.running) {
    return;
  }
  ma_device_uninit(&call.device);
  ma_context_uninit(&call.context);
  btox_session_stop();
  ma_pcm_rb_uninit(&call.playback);
  free_call();
}

static void on_ringing_audio(ma_device *device, void *output, const void *input,
                             ma_uint32 frames) {
  (void)input;
  int16_t *out = output;
  for (ma_uint32 i = 0; i < frames; ++i) {
    out[i] = tone_sample(&ringing_tone, ringing.at++, device->sampleRate);
  }
}

void btox_audio_set_ringing(bool on) {
  if (on == ringing.running) {
    return;
  }
  if (!on) {
    ma_device_uninit(&ringing.device);
    ma_context_uninit(&ringing.context);
    memset(&ringing, 0, sizeof(ringing));
    return;
  }
  ma_context_config context_config = ma_context_config_init();
  /* As the phone's own ringtone, silent when the phone is. */
  context_config.coreaudio.sessionCategory =
      ma_ios_session_category_solo_ambient;
  if (ma_context_init(NULL, 0, &context_config, &ringing.context) !=
      MA_SUCCESS) {
    return;
  }
  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_s16;
  config.playback.channels = 1;
  config.dataCallback = on_ringing_audio;
  if (ma_device_init(&ringing.context, &config, &ringing.device) !=
      MA_SUCCESS) {
    ma_context_uninit(&ringing.context);
    return;
  }
  if (ma_device_start(&ringing.device) != MA_SUCCESS) {
    ma_device_uninit(&ringing.device);
    ma_context_uninit(&ringing.context);
    return;
  }
  ringing.running = true;
}

void btox_free(void *buffer) { free(buffer); }

#if !BTOX_IOS
/* The system chooses where the audio goes, and the user in its settings. */
bool btox_session_start(bool speaker, btox_routes_cb *on_routes) {
  (void)speaker;
  on_routes(BTOX_ROUTE_SPEAKER, 1 << BTOX_ROUTE_SPEAKER);
  return true;
}

void btox_session_set_route(Btox_Route route) { (void)route; }

void btox_session_stop(void) {}
#endif

#if !defined(__APPLE__)
/* Only Apple's systems ask the user. */
void btox_request_permissions(bool camera, btox_permissions_cb *done) {
  (void)camera;
  done(true);
}
#endif
