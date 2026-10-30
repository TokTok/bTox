/* Call audio and video on iOS, macOS, Linux and Windows, for Dart's FFI. */
#ifndef BTOX_CALL_MEDIA_H
#define BTOX_CALL_MEDIA_H

#include <stdbool.h>
#include <stdint.h>

#if defined(_WIN32)
#define BTOX_EXPORT __declspec(dllexport)
#else
#define BTOX_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* As AudioRoute in Dart. */
typedef enum Btox_Route {
  BTOX_ROUTE_EARPIECE,
  BTOX_ROUTE_SPEAKER,
  BTOX_ROUTE_WIRED,
  BTOX_ROUTE_BLUETOOTH,
} Btox_Route;

/* Each callback that gets a buffer owns it, and frees it with btox_free. */

/* 16-bit mono PCM, 20 ms of it at the call's sample rate. */
typedef void btox_audio_frame_cb(int16_t *pcm, int32_t samples);

/* The route the audio takes, and a bit for each route it could take. */
typedef void btox_routes_cb(int32_t route, int32_t available);

/* An I420 frame, its planes one after the other without padding, upright. */
typedef void btox_video_frame_cb(uint8_t *i420, int32_t width, int32_t height);

typedef void btox_camera_stopped_cb(void);

typedef void btox_permissions_cb(bool granted);

/*
 * Cancels the speaker's echo from the microphone's sound. The audio goes to
 * the loudspeaker if [speaker] and there's no headset. Null once started, else
 * what failed.
 */
BTOX_EXPORT const char *btox_audio_start(int32_t sample_rate,
                                         int32_t frame_samples, bool speaker,
                                         btox_audio_frame_cb *on_frame,
                                         btox_routes_cb *on_routes);

/* Plays as much of [pcm] as there's room for, as a call can't wait. */
BTOX_EXPORT void btox_audio_play(const int16_t *pcm, int32_t samples);

BTOX_EXPORT void btox_audio_set_route(int32_t route);

/* Once the audio started. */
BTOX_EXPORT void btox_audio_set_ring_back(bool on);

BTOX_EXPORT void btox_audio_set_ringing(bool on);

BTOX_EXPORT void btox_audio_stop(void);

/* [front] where there's a choice. */
BTOX_EXPORT bool btox_camera_start(bool front, btox_video_frame_cb *on_frame,
                                   btox_camera_stopped_cb *on_stopped);

BTOX_EXPORT void btox_camera_stop(void);

/* Where the system asks the user. */
BTOX_EXPORT void btox_request_permissions(bool camera,
                                          btox_permissions_cb *done);

BTOX_EXPORT void btox_free(void *buffer);

#ifdef __cplusplus
}
#endif

#endif /* BTOX_CALL_MEDIA_H */
