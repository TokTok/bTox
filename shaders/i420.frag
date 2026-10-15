#version 460 core

#include <flutter/runtime_effect.glsl>

// Draws an I420 frame from its bytes, which come four to a texel of an RGBA
// image, row after row of uDataSize.x texels.

uniform vec2 uSize;
uniform vec2 uFrame;
uniform vec2 uDataSize;
uniform sampler2D uData;

out vec4 fragColor;

float byteAt(float i) {
  float texel = floor(i / 4.0);
  float row = floor(texel / uDataSize.x);
  vec4 bytes = texture(
      uData, vec2(texel - row * uDataSize.x + 0.5, row + 0.5) / uDataSize);
  float c = i - texel * 4.0;
  return c < 0.5 ? bytes.r : c < 1.5 ? bytes.g : c < 2.5 ? bytes.b : bytes.a;
}

void main() {
  vec2 p = floor(FlutterFragCoord().xy / uSize * uFrame);
  float w = uFrame.x;
  float h = uFrame.y;
  float cw = floor((w + 1.0) / 2.0);
  float ch = floor((h + 1.0) / 2.0);
  float chroma = floor(p.y / 2.0) * cw + floor(p.x / 2.0);
  float y = 1.164 * (byteAt(p.y * w + p.x) - 0.0625);
  float u = byteAt(w * h + chroma) - 0.5;
  float v = byteAt(w * h + cw * ch + chroma) - 0.5;
  // BT.601, limited range, as toxav's VP8 frames are.
  fragColor = vec4(y + 1.596 * v, y - 0.392 * u - 0.813 * v, y + 2.017 * u, 1.0);
}
