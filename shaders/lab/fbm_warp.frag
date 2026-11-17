// Domain-warped fractal Brownian motion (after Inigo Quilez, "warp").
//
//   f(p)             plain fBm
//   f(p + w*q)       single warp, q = fbm field(s)
//   f(p + w*r)       double warp, r = fbm(p + w*q)
//
// fBm = sum of gradient-noise octaves, each rotated, scaled by `lacunarity`
// in frequency and by `gain` in amplitude. `octaves` is a float: the last
// octave fades in, so sliding it doesn't pop. Time slides each warp layer at a
// different speed, so the field folds into itself instead of just scrolling.
//
// Cost: up to 5 fbm evaluations x 8 octaves per pixel. The experiment renders
// at reduced scale; the field is smooth so upscaling is barely visible.
//
// See plasma.frag for the lab uniform contract. Parameters, in order:
//   p0 = (scale, octaves, lacunarity, gain)
//   p1 = (warp amount, speed, warp depth 0/1/2, relief 0/1)
//   p2..p5 = colors A..D
precision highp float;

uniform Globals {
  vec4 time_res;
  vec4 mouse;
} u_globals;

uniform Params {
  vec4 p0;
  vec4 p1;
  vec4 p2;
  vec4 p3;
  vec4 p4;
  vec4 p5;
} u_params;

in vec2 v_uv;
out vec4 frag_color;

const int kMaxOctaves = 8;

// Sin-free hash (Dave Hoskins' hash22): stable across GPUs.
vec2 hash22(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

// Gradient (Perlin-style) noise, roughly in -0.7..0.7.
float gnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float a = dot(hash22(i) * 2.0 - 1.0, f);
  float b = dot(hash22(i + vec2(1.0, 0.0)) * 2.0 - 1.0, f - vec2(1.0, 0.0));
  float c = dot(hash22(i + vec2(0.0, 1.0)) * 2.0 - 1.0, f - vec2(0.0, 1.0));
  float d = dot(hash22(i + vec2(1.0, 1.0)) * 2.0 - 1.0, f - vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

const mat2 kRot = mat2(0.8, 0.6, -0.6, 0.8);

float g_octaves;
float g_lacunarity;
float g_gain;

// fBm normalized to roughly -1..1.
float fbm(vec2 p) {
  float sum = 0.0;
  float norm = 0.0;
  float amp = 1.0;
  for (int i = 0; i < kMaxOctaves; i++) {
    float w = clamp(g_octaves - float(i), 0.0, 1.0);
    if (w <= 0.0) break;
    sum += amp * w * gnoise(p);
    norm += amp * w;
    p = kRot * p * g_lacunarity + vec2(17.3, 9.1);
    amp *= g_gain;
  }
  return sum / max(norm, 1e-4) * 1.4;
}

// The two-component warp field: each component is an fBm sampled at a
// different offset and drifting in a different direction over time.
vec2 field(vec2 p, vec2 seed, float t) {
  return vec2(
    fbm(p + seed + vec2(t, -t * 0.7)),
    fbm(p + seed.yx * 1.3 + vec2(3.7, 8.1) + vec2(-t * 0.8, t))
  );
}

void main() {
  float time = u_globals.time_res.x;
  float aspect = u_globals.time_res.y / max(u_globals.time_res.z, 1.0);

  float scale = u_params.p0.x;
  g_octaves = u_params.p0.y;
  g_lacunarity = u_params.p0.z;
  g_gain = u_params.p0.w;
  float warp = u_params.p1.x;
  float speed = u_params.p1.y;
  float depth = u_params.p1.z;
  float relief = u_params.p1.w;
  vec3 col_a = u_params.p2.rgb;
  vec3 col_b = u_params.p3.rgb;
  vec3 col_c = u_params.p4.rgb;
  vec3 col_d = u_params.p5.rgb;

  float t = time * speed * 0.1;
  vec2 p = (v_uv - 0.5) * vec2(aspect, 1.0) * scale;

  vec2 q = vec2(0.0);
  vec2 r = vec2(0.0);
  float f;
  if (depth < 0.5) {
    f = fbm(p + vec2(t));
  } else if (depth < 1.5) {
    q = field(p, vec2(0.0), t);
    f = fbm(p + warp * q);
  } else {
    q = field(p, vec2(0.0), t);
    r = field(p + warp * q, vec2(1.7, 9.2), t * 1.2);
    f = fbm(p + warp * r);
  }

  float v = clamp(f * 0.5 + 0.5, 0.0, 1.0);

  // Palette in the spirit of the original: A->B by height, then C where the
  // first warp layer is strong, then D where the second layer leans right.
  vec3 col = mix(col_a, col_b, clamp(v * v * 2.0, 0.0, 1.0));
  col = mix(col, col_c, clamp(length(q) * 0.8, 0.0, 1.0));
  col = mix(col, col_d, clamp(r.x * 0.5 + 0.1, 0.0, 1.0) * smoothstep(0.3, 0.9, v));

  if (relief > 0.5) {
    // Fake directional light from the screen-space gradient of the field.
    vec2 grad = vec2(dFdx(v), dFdy(v)) * u_globals.time_res.y * 0.08;
    float light = dot(grad, normalize(vec2(-1.0, -1.0)));
    col *= 1.0 + light * 2.5;
    col += pow(clamp(light, 0.0, 1.0), 2.0) * 0.25;
  } else {
    col *= 0.75 + 0.5 * v;
  }

  frag_color = vec4(col, 1.0);
}
