#include "nv12.h"

#include <stdlib.h>
#include <string.h>

uint8_t *btox_nv12_to_i420(const uint8_t *luma, size_t luma_stride,
                           const uint8_t *chroma, size_t chroma_stride,
                           size_t width, size_t height) {
  const size_t cw = (width + 1) / 2;
  const size_t ch = (height + 1) / 2;
  uint8_t *frame = malloc(width * height + 2 * cw * ch);
  if (frame == NULL) {
    return NULL;
  }
  /* The luma as it is, the chroma's halves apart. */
  for (size_t y = 0; y < height; ++y) {
    memcpy(frame + y * width, luma + y * luma_stride, width);
  }
  uint8_t *u = frame + width * height;
  uint8_t *v = u + cw * ch;
  for (size_t y = 0; y < ch; ++y) {
    const uint8_t *row = chroma + y * chroma_stride;
    for (size_t x = 0; x < cw; ++x) {
      u[y * cw + x] = row[x * 2];
      v[y * cw + x] = row[x * 2 + 1];
    }
  }
  return frame;
}
