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
* Hot reload rebuilds and reloads shader bundles only if the build hook
  declares the shader sources as `buildOutput.dependencies`
* It's not possible to set anisotropic filtering level on textures
## Executables
Two entrypoints, selected with `-t`:

* `flutter run -t lib/basic_examples.dart` - basic Flutter GPU examples (no flutter_scene)
* `flutter run -t lib/ideas.dart` - larger experiments built on flutter_scene
* `flutter run -t lib/lab.dart` - shader research lab (see below)


## Shader lab
`flutter run -t lib/lab.dart --enable-flutter-gpu` (a "Shader Lab" launch config
is in `.vscode/launch.json`).

* Experiments live in `lib/lab/experiments.dart`. A `FragmentExperiment` draws
  one fragment shader from `shaders/lab.shaderbundle.json` on a fullscreen quad;
  its `params` become controls in the right-hand panel.
* Shader uniform contract (see `shaders/lab/plasma.frag`): `Globals`
  (time, resolution, mouse) and `Params` (`p0`..`p5`, packed in declaration
  order; the panel shows each control's GLSL slot). Textures bind in order as
  `u_texture0`, `u_texture1`, ...
* `ToonSceneExperiment` (`lib/lab/scene_toon_experiment.dart`) shows the
  flutter_scene path: a `ShaderMaterial` whose fragment shader declares the
  engine's standard varyings itself (no includes needed) and gets time, camera
  position and light direction from a `SceneInfo` block rewritten every frame.
  Its output is linear HDR, so sRGB textures are linearized in the shader.
* `Transition` sweeps from the first image to the second, top to bottom.
  `Sweep length` sets the gradient height as a fraction of the viewport height;
  zero gives a sharp edge. Progress can be set manually or auto-played.
* `Parchment` is a cheap procedural paper background meant to sit behind scrolling
  content. Inputs: `scroll` (in viewport heights, i.e. scroll offset / viewport
  height) and `seed` (same seed, same paper; no time input). The mouse wheel or
  trackpad over the viewport drives `scroll`. `FragmentExperiment.renderScale`
  renders at a fraction of the resolution (0.5 for Parchment) to save fill
  rate. Start the lab on an experiment with
  `--dart-define=LAB_EXPERIMENT=Parchment`.
* Drop images into `assets/lab/textures/`; they show up in the texture picker.
* Edit a shader and hot reload (`r`). The build hook declares the shader files
  as dependencies so the bundle is rebuilt. Compile errors print in the
  `flutter run` console; runtime errors (missing shader, bad uniform name) show
  in the in-app banner. The refresh button re-fetches the bundle asset.
