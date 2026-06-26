#include <metal_stdlib>
using namespace metal;

// ===============================
// vector_add
// ===============================
kernel void vector_add(const device float *input_a [[buffer(0)]],
const device float *input_b [[buffer(1)]],
device float *output [[buffer(2)]],
uint id [[thread_position_in_grid]]) {
  output[id] = input_a[id] + input_b[id];
}

// ===============================
// matrix_multiply (2x2 × 2x2 for demo)
// ===============================
kernel void matrix_multiply(const device float *matrix_a [[buffer(0)]],
const device float *matrix_b [[buffer(1)]],
device float *result [[buffer(2)]],
uint id [[thread_position_in_grid]]) {
  // Hardcoded 2x2 matrix multiplication
  if (id == 0)
  result[0] = matrix_a[0] * matrix_b[0] + matrix_a[1] * matrix_b[2];
  if (id == 1)
  result[1] = matrix_a[0] * matrix_b[1] + matrix_a[1] * matrix_b[3];
  if (id == 2)
  result[2] = matrix_a[2] * matrix_b[0] + matrix_a[3] * matrix_b[2];
  if (id == 3)
  result[3] = matrix_a[2] * matrix_b[1] + matrix_a[3] * matrix_b[3];
}

// ===============================
// safe_divide
// ===============================
kernel void safe_divide(const device float *numerator [[buffer(0)]],
const device float *denominator [[buffer(1)]],
device float *result [[buffer(2)]],
uint id [[thread_position_in_grid]]) {
  float denom = denominator[id];
  if (denom == 0.0) {
    result[id] = 999999.0; // magic fallback value to avoid NaN/inf
  } else {
    result[id] = numerator[id] / denom;
  }
}

// ===============================
// memory_test
// ===============================
kernel void memory_test(const device float *large_buffer [[buffer(0)]],
device float *output [[buffer(1)]],
uint id [[thread_position_in_grid]]) {
  // Dummy heavy computation for memory stress
  float val = large_buffer[id];
  for (int i = 0; i < 100; ++i) {
    val = sin(val) + cos(val);
  }
  output[id] = val;
}

// ===============================
// precision_test
// ===============================
kernel void precision_test(const device float *input [[buffer(0)]],
device float *output [[buffer(1)]],
uint id [[thread_position_in_grid]]) {
  if (id == 0) {
    output[0] = input[0] + input[1]; // should be 0.3
  } else if (id == 1) {
    output[1] = input[2] * input[3] + input[4]; // 0.3 * 0.4 + 0.5 = 0.62
  }
}

// ===============================
// texture_invert — example texture kernel
// ===============================
// Reads RGBA8 from input texture at [[texture(0)]], inverts, writes to output at [[texture(1)]].
// Uses float access (RGBA8Unorm) — matches the common pixel format for demo textures.
kernel void texture_invert(texture2d<float, access::read> input [[texture(0)]],
texture2d<float, access::write> output [[texture(1)]],
uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;
  float4 pixel = input.read(gid);
  pixel.r = 1.0 - pixel.r;
  pixel.g = 1.0 - pixel.g;
  pixel.b = 1.0 - pixel.b;
  output.write(pixel, gid);
}

// ===============================
// texture_invert_uint — for RGBA8Uint textures
// ===============================
kernel void texture_invert_uint(texture2d<uint, access::read> input [[texture(0)]],
texture2d<uint, access::write> output [[texture(1)]],
uint2 gid [[thread_position_in_grid]]) {
  if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;
  uint4 pixel = input.read(gid);
  pixel.r = 255 - pixel.r;
  pixel.g = 255 - pixel.g;
  pixel.b = 255 - pixel.b;
  output.write(pixel, gid);
}

// ===============================
// texture_grayscale — sampled texture kernel
// ===============================
// Uses a sampler to read from input texture, converts to grayscale, writes to output.
kernel void texture_grayscale(texture2d<float, access::sample> input [[texture(0)]],
texture2d<float, access::write> output [[texture(1)]],
uint2 gid [[thread_position_in_grid]]) {
  constexpr sampler s(coord::pixel, filter::linear, address::clamp_to_edge);
  if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;
  float4 pixel = input.sample(s, float2(gid));
  float gray = dot(pixel.rgb, float3(0.299, 0.587, 0.114));
  output.write(float4(gray, gray, gray, pixel.a), gid);
}


kernel void compute_shader(const device float *input [[buffer(0)]],
device float *output [[buffer(1)]],
uint index [[thread_position_in_grid]]) {
  output[index] = input[index] * 2.0;
}
