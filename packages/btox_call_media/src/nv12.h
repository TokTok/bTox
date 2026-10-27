#ifndef BTOX_NV12_H
#define BTOX_NV12_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* A [width] by [height] NV12 picture, its planes' rows [luma_stride] and
 * [chroma_stride] bytes apart, as an I420 frame from malloc. NULL without
 * memory. */
uint8_t *btox_nv12_to_i420(const uint8_t *luma, size_t luma_stride,
                           const uint8_t *chroma, size_t chroma_stride,
                           size_t width, size_t height);

#ifdef __cplusplus
}
#endif

#endif
