// See plasma.frag for the lab uniform contract.
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

// First TextureParam in the experiment.
uniform sampler2D u_texture0;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  float time = u_globals.time_res.x;
  float aspect = u_globals.time_res.y / max(u_globals.time_res.z, 1.0);

  float amount = u_params.p0.x;
  float frequency = u_params.p0.y;
  float speed = u_params.p0.z;
  float mode = u_params.p0.w;   // 0 = ripple, 1 = swirl
  vec4 tint = u_params.p1;

  float t = time * speed;
  vec2 d = (v_uv - u_globals.mouse.xy) * vec2(aspect, 1.0);
  float len = length(d);

  // Ripple: push uv along the radial direction with a travelling sine wave.
  vec2 ripple = (d / (len + 1e-4)) * sin(len * frequency - t) * amount * 0.05;

  // Swirl: rotate uv around the mouse, strongest near it.
  float angle = amount * exp(-len * 3.0) * sin(t);
  vec2 swirl = vec2(cos(angle) * d.x - sin(angle) * d.y,
                    sin(angle) * d.x + cos(angle) * d.y) - d;
  swirl.x /= aspect;

  vec2 uv = v_uv + mix(ripple, swirl, mode);
  frag_color = texture(u_texture0, uv) * tint;
}
