// One Gray-Scott reaction-diffusion step. Reads the previous state texture and
// writes the next one, so the host ping-pongs two textures (A in .r, B in .g).
//
//   A' = A + (Da * lap(A) - A*B*B + feed*(1 - A)) * dt
//   B' = B + (Db * lap(B) + A*B*B - (kill + feed) * B) * dt
//
// Globals.time_res = (time, sim width px, sim height px, reset 0/1). With
// reset set, the output is a fresh state (A = 1, scattered seeds of B) instead
// of a step. Globals.mouse = (u, v, pressed, seed); pressing paints B.
//
// See plasma.frag for the Params packing. Parameters, in order:
//   p0 = (feed, kill, diffusion A, diffusion B)
//   p1 = (dt, steps per frame, brush radius, preset)
// The remaining params only matter to rd_display.frag.
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

uniform sampler2D u_state;

in vec2 v_uv;
out vec4 frag_color;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// (feed, kill) of well-known Gray-Scott regimes; index 0 = use the sliders.
vec2 preset_fk(int preset, vec2 custom) {
  if (preset == 1) return vec2(0.0545, 0.0620); // coral
  if (preset == 2) return vec2(0.0367, 0.0649); // mitosis
  if (preset == 3) return vec2(0.0290, 0.0570); // maze
  if (preset == 4) return vec2(0.0780, 0.0610); // worms
  if (preset == 5) return vec2(0.0300, 0.0620); // spots
  if (preset == 6) return vec2(0.0620, 0.0609); // u-skate
  return custom;
}

void main() {
  vec2 res = u_globals.time_res.yz;
  float aspect = res.x / max(res.y, 1.0);
  float seed = u_globals.mouse.w;

  if (u_globals.time_res.w > 0.5) {
    // Fresh state: A = 1 everywhere, B seeded in scattered blocks and a patch
    // in the middle, so something grows from the first frame.
    vec2 cell = floor(v_uv * res / 10.0);
    float scatter = step(0.985, hash12(cell + seed * 17.0));
    vec2 d = (v_uv - 0.5) * vec2(aspect, 1.0);
    float center = step(max(abs(d.x), abs(d.y)), 0.04);
    float b = max(scatter, center);
    frag_color = vec4(1.0 - 0.5 * b, b, 0.0, 1.0);
    return;
  }

  vec2 px = 1.0 / res;
  vec2 c = texture(u_state, v_uv).rg;

  // 3x3 Laplacian: center -1, edge neighbors 0.2, corners 0.05.
  vec2 lap = -c;
  lap += 0.2 * (texture(u_state, v_uv + vec2(px.x, 0.0)).rg
              + texture(u_state, v_uv - vec2(px.x, 0.0)).rg
              + texture(u_state, v_uv + vec2(0.0, px.y)).rg
              + texture(u_state, v_uv - vec2(0.0, px.y)).rg);
  lap += 0.05 * (texture(u_state, v_uv + px).rg
               + texture(u_state, v_uv - px).rg
               + texture(u_state, v_uv + vec2(px.x, -px.y)).rg
               + texture(u_state, v_uv + vec2(-px.x, px.y)).rg);

  vec2 fk = preset_fk(int(u_params.p1.w + 0.5), u_params.p0.xy);
  float feed = fk.x;
  float kill = fk.y;
  float da = u_params.p0.z;
  float db = u_params.p0.w;
  float dt = u_params.p1.x;

  float reaction = c.x * c.y * c.y;
  float a = c.x + (da * lap.x - reaction + feed * (1.0 - c.x)) * dt;
  float b = c.y + (db * lap.y + reaction - (kill + feed) * c.y) * dt;

  // Painting: drop B under the pointer while pressed.
  if (u_globals.mouse.z > 0.5) {
    vec2 d = (v_uv - u_globals.mouse.xy) * vec2(aspect, 1.0);
    if (length(d) < u_params.p1.z) {
      b = 1.0;
      a = min(a, 0.5);
    }
  }

  frag_color = vec4(clamp(a, 0.0, 1.0), clamp(b, 0.0, 1.0), 0.0, 1.0);
}
