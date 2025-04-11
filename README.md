![Dark scene showcase](renders/dim%20scene%20showcase.png "A scene showcase nested dielectrics as well as emissive rendering.")

## Welcome to my Godot path tracer plugin for godot 4.3

I intentioned this plugin to be an alternative renderer for Godot, plug-and-play style. Support for using Godot meshes is in development, but some large performance optimizations have to be done before using it in real project is feasable.

At its inception, the renderer was created as an plugin on top of the existing Godot rendering system, but i think going forward i would like it to be closer integrated with Godot, by utilizing some of the lower level c++ classes in Godot. For this i might need to create a gdextension, which i am planning to do.

NOTE: As this is a prerelease, some objects won't dynamically update correctly in the editor. However, restarting or running the project should always load things correctly.

### List of features:
  - Supported objects:
      - 3D primitives:
          - spheres

      - 2D primitives:
          - triangles
          - planes

      - Meshes (Collection of primitives)

  - Instancing of meshes with transformations (not memory conservative yet)

  - Importing meshes (partially)

  - Material types:
      - Diffuse
      - Metallic
      - Transparent/glass

  - Procedural and sampled textures

  - Simple multisampling

  - Nested Dielectrics - transparent objects within transparent objects

    This allows for set operations on objects with relative ease, like:
      - Union
      - Difference

Additionally there is sources.md which details useful information i found regarding path tracing and rendering in general and is intended for someone starting out.

Also check out the renders folder for more renders like the one above.

## Download
The project isn't ready to be used as a plugin, but it can be downloaded and run as a project. No setup should be required and it should work for all desktop platforms with Vulkan API support.

Currently the project is updated to Godot 4.3.


## Usage guide
To start rendering you need to create a PTScene Node. Then you can add any subtype of PTObject, PTObject itself will not work, as a descendant of that scene node. You can also add an PTMesh node. Any PTObject under a PTMesh will be a part of that mesh. The PTMesh allows for more efficient transformations of objects within it.

In the PathTracer tab there are two sub-tabs that control editor and runtime settings separetaly.

Some rendering parameters have not been implented in the editor interface but can be found in shaders/ray_tracer.comp, most notably the option to toggle emissive rendering. You might need to restart the editor.


### Long term goals

  - Add detail when standing still -- DONE --

  - Add skybox

  - Add surface textures -- ALMOST --

  - Make set theory functions possible with objects like add and subtract
      (can see insides of objects) -- DONE --

  - Add subfurface scattering

  - Add lighting -- DONE --

  - Make a real time ray tracer with triangle geometry (will be scuffed) -- ALMOST --

  - Simulate glass of beer

  - Add support for bump maps

  - Add rounding effect for 3d primitives

  - Add importance sampling


### Other notes:
  - The editor camera uses layer 20 to hide the path traced render.
  - Using preview world environment in the editor might turn on tonamapping which will make the colors look incorrect.
