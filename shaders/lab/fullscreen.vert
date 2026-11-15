// Fullscreen quad for lab fragment experiments.
// position is in NDC; v_uv has (0,0) at the top-left and (1,1) at the bottom-right.
in vec2 position;

out vec2 v_uv;

void main() {
  v_uv = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
  gl_Position = vec4(position, 0.0, 1.0);
}
