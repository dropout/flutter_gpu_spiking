
uniform FrameInfo {
  mat4 mvp;
  float time;
} u_frameInfo;

in vec3 position;
in vec2 texture_coords;
in vec4 color;

out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  v_texture_coords = texture_coords;
  v_color = color;

  gl_Position = u_frameInfo.mvp * vec4(position, 1.0);
}
