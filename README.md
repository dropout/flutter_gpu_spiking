# flutter_gpu_spiking

How usable it is?

## Getting Started

Start right away!


## Findings
* Dialect of GLSL
* Shader compilation error messages are not very descriptive
* Build asset hook problems
  1. Change shader to invalid shader code
  2. Run project - app crash
  3. Change shader to valid shader code
  4. Run project - app crash again
  5. Use build_runner to run build hook
  6. Run project - app works
