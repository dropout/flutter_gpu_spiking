// Lab uniform contract (shared by all lab fragment experiments):
//   Globals.time_res = (time seconds, width px, height px, 0)
//   Globals.mouse    = (mouse u, mouse v, pressed 0/1, 0)   uv in 0..1, origin top-left
//   Params.p0..p5    = control panel values, packed in declaration order
//                      (floats/bools/choices take one float, colors take a whole vec4)
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

void main() {
  float time = u_globals.time_res.x;
  float aspect = u_globals.time_res.y / max(u_globals.time_res.z, 1.0);

  float scale = u_params.p0.x;
  float speed = u_params.p0.y;
  float mouse_influence = u_params.p0.z;
  float invert = u_params.p0.w;
  vec4 color_a = u_params.p1;
  vec4 color_b = u_params.p2;

  float t = time * speed;
  vec2 p = (v_uv - 0.5) * vec2(aspect, 1.0) * scale;
  p += (u_globals.mouse.xy - 0.5) * mouse_influence * 4.0;

  float v = sin(p.x + t)
          + sin((p.y + t) * 0.7)
          + sin((p.x + p.y + t) * 0.5)
          + sin(length(p) + t * 1.3);
  v = v * 0.25 + 0.5;
  v = mix(v, 1.0 - v, invert);

  frag_color = vec4(mix(color_a.rgb, color_b.rgb, v), 1.0);
}
