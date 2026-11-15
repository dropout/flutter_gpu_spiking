// flutter_scene ShaderMaterial fragment shader: banded toon lighting with a
// texture, a rim light and an animated stripe pulse.
//
// Scene-driven inputs arrive through the SceneInfo block, which the lab
// rewrites every frame (time, camera position, light direction). Control-panel
// values arrive in Params, packed as described in plasma.frag.
//
// The varyings below are flutter_scene's engine contract: the standard vertex
// shader writes exactly these, in this order, so the declarations must match
// (see shaders/material_varyings.glsl in flutter_scene). Output is linear HDR
// premultiplied by alpha; the scene's resolve pass does tone mapping.
uniform SceneInfo {
  vec4 time_mouse;   // x: seconds, yz: mouse uv, w: pressed
  vec4 camera_pos;   // xyz: world-space camera position
  vec4 light_dir;    // xyz: world-space unit vector toward the light
} u_scene;

uniform Params {
  vec4 p0;
  vec4 p1;
  vec4 p2;
  vec4 p3;
  vec4 p4;
  vec4 p5;
} u_params;

uniform sampler2D u_texture0;

in highp vec3 v_position;
in vec3 v_normal;
in highp vec3 v_viewvector;
in highp vec2 v_texture_coords;
in highp vec2 v_texture_coords_1;
in vec4 v_color;
in vec4 v_tangent;

out vec4 frag_color;

vec3 srgb_to_linear(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void main() {
  float time = u_scene.time_mouse.x;

  float bands = max(u_params.p0.x, 1.0);
  float rim_power = u_params.p0.y;
  float rim_strength = u_params.p0.z;
  float tex_scale = u_params.p0.w;
  float stripes = u_params.p1.x;
  vec4 tint = u_params.p2;
  vec4 rim_color = u_params.p3;

  float face = gl_FrontFacing ? 1.0 : -1.0;
  vec3 n = normalize(v_normal) * face;
  vec3 l = normalize(u_scene.light_dir.xyz);
  vec3 v = normalize(u_scene.camera_pos.xyz - v_position);

  vec3 albedo = srgb_to_linear(texture(u_texture0, v_texture_coords * tex_scale).rgb) * tint.rgb;

  // Banded diffuse.
  float ndl = dot(n, l) * 0.5 + 0.5;
  float banded = floor(ndl * bands) / bands + 0.5 / bands;

  // Specular highlight, thresholded for the toon look.
  vec3 r = reflect(-l, n);
  float spec = step(0.5, pow(max(dot(r, v), 0.0), 32.0));

  // Rim light, from the camera position wired in by the scene.
  float rim = pow(1.0 - max(dot(n, v), 0.0), max(rim_power, 0.01)) * rim_strength;

  // Stripes travelling up the object over time.
  float pulse = sin(v_position.y * 10.0 - time * 3.0) * 0.5 + 0.5;
  vec3 stripe = rim_color.rgb * pulse * pulse * stripes;

  vec3 color = albedo * banded + spec * 0.4 + rim_color.rgb * rim + stripe;
  frag_color = vec4(color, 1.0);
}
