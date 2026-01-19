// From vertex buffer
in vec3 position;
in vec2 texture_coords;
in vec4 color;

// To fragment shader
out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  // Forward attributes to fragment shader
  v_texture_coords = texture_coords;
  v_color = color;

  // Set vertex position
  gl_Position = vec4(position, 1.0);
}
