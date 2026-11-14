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
* It's not possible to set anisotropic filtering level on textures
## Executables
Two entrypoints, selected with `-t`:

* `flutter run -t lib/basic_examples.dart` - basic Flutter GPU examples (no flutter_scene)
* `flutter run -t lib/ideas.dart` - larger experiments built on flutter_scene
