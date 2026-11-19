// Colors the reaction-diffusion state (B concentration) with a three-stop
// palette, optionally lit as a relief. Reads the texture rd_step.frag writes.
//
// See plasma.frag for the lab uniform contract. Parameters, in order (the
// first eight belong to rd_step.frag):
//   p2.x = relief 0/1
//   p3 = background color   p4 = mid color   p5 = high color
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

float height(vec2 uv) {
  return clamp(texture(u_state, uv).g * 2.4, 0.0, 1.0);
}

void main() {
  vec2 res = u_globals.time_res.yz;
  vec2 px = 1.0 / res;
  float h = height(v_uv);

  vec3 bg = u_params.p3.rgb;
  vec3 mid = u_params.p4.rgb;
  vec3 hi = u_params.p5.rgb;

  vec3 col = mix(bg, mid, smoothstep(0.0, 0.5, h));
  col = mix(col, hi, smoothstep(0.5, 1.0, h));

  if (u_params.p2.x > 0.5) {
    vec2 grad = vec2(
      height(v_uv + vec2(px.x, 0.0)) - height(v_uv - vec2(px.x, 0.0)),
      height(v_uv + vec2(0.0, px.y)) - height(v_uv - vec2(0.0, px.y))
    );
    float light = dot(grad, normalize(vec2(-1.0, -1.0)));
    col *= 1.0 + light * 3.0;
    col += pow(clamp(light * 2.0, 0.0, 1.0), 2.0) * 0.2;
  }

  frag_color = vec4(col, 1.0);
}
