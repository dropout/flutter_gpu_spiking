// flutter_scene ShaderMaterial fragment shader for the procedural terrain.
//
// The mesh is built on the CPU (lib/lab/terrain_experiment.dart). Per vertex it
// supplies a smooth normal (central differences of the heightfield) and the
// raw, unclamped height in v_color.r (0..1), so the shader can tell land from
// water even though the mesh itself is flattened at the water level.
//
// Everything the shader needs arrives in the Terrain block, rewritten every
// frame by the experiment. The varyings below are flutter_scene's engine
// contract (see scene_toon.frag). Output is linear HDR; the scene tone-maps.
uniform Terrain {
  vec4 shape;      // x: water level, y: snow line, z: rock slope, w: contour strength
  vec4 light_dir;  // xyz: unit vector toward the sun
  vec4 camera_pos; // xyz: world-space camera position
  vec4 water_col;  // linear
  vec4 grass_col;  // linear
  vec4 snow_col;   // linear
} u_terrain;

in highp vec3 v_position;
in vec3 v_normal;
in highp vec3 v_viewvector;
in highp vec2 v_texture_coords;
in highp vec2 v_texture_coords_1;
in vec4 v_color;
in vec4 v_tangent;

out vec4 frag_color;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
             mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x),
             f.y);
}

void main() {
  float water_level = u_terrain.shape.x;
  float snow_line = u_terrain.shape.y;
  float rock_slope = u_terrain.shape.z;
  float contour = u_terrain.shape.w;

  vec3 l = normalize(u_terrain.light_dir.xyz);
  vec3 v = normalize(u_terrain.camera_pos.xyz - v_position);
  float h = v_color.r;

  vec3 sky = vec3(0.35, 0.50, 0.85);
  vec3 sun = vec3(3.0, 2.7, 2.3);
  vec3 color;

  if (h < water_level) {
    // Water: flat surface, darker and bluer with depth, with a sun glint.
    vec3 n = normalize(vec3(
      (vnoise(v_position.xz * 9.0) - 0.5) * 0.06, 1.0,
      (vnoise(v_position.xz * 9.0 + 7.0) - 0.5) * 0.06));
    float depth = clamp((water_level - h) / max(water_level, 0.001), 0.0, 1.0);
    vec3 shallow = u_terrain.water_col.rgb * 1.6;
    vec3 deep = u_terrain.water_col.rgb * 0.35;
    vec3 base = mix(shallow, deep, sqrt(depth));
    float fresnel = pow(1.0 - max(dot(n, v), 0.0), 4.0);
    vec3 r = reflect(-l, n);
    float glint = pow(max(dot(r, v), 0.0), 90.0);
    color = base * (0.5 + 0.5 * max(dot(n, l), 0.0)) + sky * fresnel * 0.5 + sun * glint * 0.6;
  } else {
    vec3 n = normalize(v_normal);
    float slope = 1.0 - n.y;

    // Land color by height, slope and snow line, with a little noise so the
    // bands are not ruler-straight.
    float grain = vnoise(v_position.xz * 14.0);
    vec3 sand = vec3(0.55, 0.45, 0.25);
    vec3 rock = vec3(0.20, 0.17, 0.15) * (0.8 + 0.4 * grain);

    float shore = smoothstep(water_level, water_level + 0.025, h + (grain - 0.5) * 0.01);
    vec3 base = mix(sand, u_terrain.grass_col.rgb * (0.7 + 0.5 * grain), shore);

    float rock_mix = smoothstep(rock_slope, rock_slope + 0.12, slope);
    base = mix(base, rock, rock_mix);

    float snow_mix = smoothstep(snow_line, snow_line + 0.08, h + (grain - 0.5) * 0.05)
                   * (1.0 - rock_mix * 0.8);
    base = mix(base, u_terrain.snow_col.rgb, snow_mix);

    float diffuse = max(dot(n, l), 0.0);
    vec3 ambient = mix(vec3(0.05, 0.045, 0.04), sky * 0.25, n.y * 0.5 + 0.5);
    color = base * (sun * diffuse * 0.6 + ambient);

    // Optional elevation contour lines.
    float line = abs(fract(h * 24.0) - 0.5);
    color *= 1.0 - contour * (1.0 - smoothstep(0.43, 0.5, line)) * 0.6;
  }

  // Distance haze toward the sky color.
  float dist = length(u_terrain.camera_pos.xyz - v_position);
  float haze = 1.0 - exp(-dist * 0.04);
  color = mix(color, sky * 0.6, haze * 0.35);

  frag_color = vec4(color, 1.0);
}
