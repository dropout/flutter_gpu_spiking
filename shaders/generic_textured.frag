// Uniform slot for a 2D texture
uniform sampler2D u_texture;

// Varying inputs from the vertex shader
in vec2 v_texture_coords;
in vec4 v_color;

// Output fragment color
out vec4 frag_color;

void main() {
  frag_color = texture(u_texture, v_texture_coords);
}
