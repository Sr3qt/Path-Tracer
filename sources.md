
# Sources

This is a compendium of resources I used to make this project. I thought it might be useful for anyone else wanting to learn more about raytracing, to have all the resources ready and available.

## General reading resources

One of the best places to start with raytracing is the [_Ray Tracing in One Weekend_](https://raytracing.github.io/) series by Peter Shirley et al. There are three books in total, but you only need the first to get started.

Another great resource is the PBR book. It's great if you are not already familiar with 3D rendering and need a helper.

Free to use book: [Raytracing gems](https://link.springer.com/book/10.1007/978-1-4842-4427-2)

A cool website I did not see until recently is [Scratchapixel.com](https://www.scratchapixel.com/index.html). It seems to have a lot of beginner friendly learning resources on both traditional rasterizing and ray-tracing/path-tracing.

IDK this dude built smthjn cool https://github.com/TomClabault/HIPRT-Path-Tracer/

Cool test scenes https://benedikt-bitterli.me/resources/


## General CG Math

### Transforming vectors
When I looked at the way [_Ray Tracing The Next Week_](https://raytracing.github.io/books/RayTracingTheNextWeek.html#instances) implements Instancing, I realized I wanted in addition to have scaling as an option, specifically non-uniform scaling. I also wanted it to be in matrix form for its simplicity and speed, you can learn more [here](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/matrices.html). As for the scaling problem, [this](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/transforming-normals.html) Scratchapixel article explains why normals need special care when transformed using a matrix and how you can transform it correctly. And finally a wiki page on [how to apply matrix transformations](https://en.wikibooks.org/wiki/GLSL_Programming/Applying_Matrix_Transformations) in glsl.

### Random point on a sphere
When first faced with the problem of finding a random point *inside* a circle, the solution might seem obvious. However, finding a random distribution is not the same as finding an uniform random distribution. For more details see [this](https://www.youtube.com/watch?v=4y_nmpv-9lI&list=PL6C1-O-nCAAN3fc-7SoWnqdNaXvezvUBu&index=29) video by
nubDotDev (The performance of each algorithm may not be accurate as it was tested in python on a CPU. Try testing it for yourself!). Computing random uniform points *on* a circle is trivial, simply choose an angle and calculate the cos and sin of said angle.

Anyways, we are actually more interested in how to compute an uniform distribution of points on a sphere instead of points in a circle. For a quick [visual explanation](https://www.jasondavies.com/maps/random-points/) by Jason Davies. An overview of different methods with can be found [here](https://mathworld.wolfram.com/SpherePointPicking.html) on WolframAlpha. I tested rejection sampling, picking Gaussian random numbers (method was taken from Lauge's [video](https://youtu.be/Qz0KTGYJtUk?t=776)), and the two first methods in the WolframAlpha article. In my testing I found that the two WolframAlpha methods were consistently ever-so-slightly faster than the other two methods, and for simplicity I stuck with the random angle one. For converting the spherical coordinates to cartesian coordinates I used [this](https://raytracing.github.io/books/RayTracingTheNextWeek.html#texturemapping/texturecoordinatesforspheres) method found in Ray Tracing: The Next Week.


Sidenote: I am confident, but without proof that (random + random) * pi / 2 <=> cos⁻¹(2 * random - 1)

## GPU limitations

### General tip
I will say that from experience, when i have implemented an algorithm and it performs much worse than expected, it is often caused by an out of bounds index or undefined number. GPUs don't fail as easily as CPUs, they will run the full program even with improper data. So make sure to test the performance of your program when you implement a new algorithm!

### Texture storage
For sampled textures I wanted to be able to add arbitrary textures to an array and simply index the array. This would be preferable over TextureArrays since they have to have tha same size and type, whereas this would not. However, for this I would require to use the Vulkan [descriptor index extension](https://docs.vulkan.org/samples/latest/samples/extensions/descriptor_indexing/README.html). Still I made it work, with the only caveat being that the maximum number of textures have to be set. It might be theoretically possible to have a variable size texture array, but godot throws an error thinking the array size is 1. DethRaid also seem to enconter this issue in their [Vulkan engine implementation](https://gist.github.com/DethRaid/0171f3cfcce51950ee4ef96c64f59617).

Also, at the time of writing, it is not well documented how to give arrays of textures/buffers to the shaderpipeline in godot, even though it's very easy. Simply add more buffer ids to the RDShaderUniform.

This [blogpost](http://chunkstories.xyz/blog/a-note-on-descriptor-indexing/) for Chunk Stories helped explain array texture vs array of textures, as well as what _dynamic non-uniform_ means.

A nice [video](https://www.youtube.com/watch?v=YTfdBSjitd8) by
Aurailus related to the same problem of needing to bind many textures, although it is in OpenGL not Vulkan (Would still advise looking at the comments, especially by @fabiangiesen306).

More about dynamic uniform indexing https://stackoverflow.com/questions/67056068/arrays-in-uniform-blocks-cannot-be-indexed-with-vertex-attributes-right


### GPU precision considerations

Much smarter people than me, mention edge cases were simple functions are prone to errors due to floating point imprecision. Because of this some nice people on stack overflow have written those simple functions accounting for edge cases, so we can just copy-paste.

- More robust atan by HuaTham [link](https://stackoverflow.com/questions/26070410/robust-atany-x-on-glsl-for-converting-xy-coordinate-to-angle)

- How to do floating point comparison by P-Gn [link](https://stackoverflow.com/questions/4915462/how-should-i-do-floating-point-comparison)
-

## Camera / Color theory

Unironically one of the deepest fields out of everything required to build a ray tracer. Luckily only surface level knowledge is required for most use cases, but if you want to learn more, here are some useful resources:

- Why use gamma: [Understanding Gamma Correction](https://www.cambridgeincolour.com/tutorials/gamma-correction.htm). Cambridge in Colour
- Common color conversion forumlas, used by OpenCV - [Color conversions](https://docs.opencv.org/3.1.0/de/d25/imgproc_color_conversions.html)


[Back to the top](#sources)😭

## Bounding Volume Hierarchy (BVH)

There are many considerations for choosing specific BVH algorithms over another.

- *A Survey on Bounding Volume Hierarchies for Ray Tracing* by Daniel Meister et al. is an in depth overview of BVH algorithms and can be found [here](https://meistdan.github.io/publications/bvh_star/paper.pdf). It explains the basics problems for why BVHs are needed in the first place and gives examples of some common generation algorithms and some very useful ones.

  Some notable examples include:
  - "Chitalu et al. [CDK20] combine LBVH with an ostensibly-implicit layout... [ ] ... This algorithm is the fastest construction algorithm to date."
  - "[Talking about 2015 Bittner algorithm]  This algorithm produces BVHs of the highest possible quality at the cost of higher build times."

- If you need help implementing a certain algorithm, [here](https://github.com/madmann91/bvh) is a c++ library of different BVH creation algorithms by madmann91.

- Sebastian Lague has a [video](https://www.youtube.com/watch?v=C1H4zIiCOaI&) on BVHs and it is a nice introduction to creation and traversal. It helped me figure out box distance ordering in traversal.

## Fast Ray-Triangle Intersection

For complex scenes a fast ray-triangle intersection test is crucial for maintaining passable performance.

- The most known and one of the best performing intersection algorithms is the Möller-Trumbore algorithm. The original paper is freely available and can be found [here](http://www.graphics.cornell.edu/pubs/1997/MT97.pdf) and a branchless glsl implementation by BrunoLevy can be found [here](https://stackoverflow.com/questions/42740765/intersection-between-line-and-triangle-in-3d/42752998#42752998)

- According to some guy on StackOverflow (Gaslight Deceive Subvert), the fastest algorithm they tested was made by Havel and Herout, claiming it to be twice as fast as the tried and true Möller-trumbore algorithm. [Here](https://stackoverflow.com/a/44837726) is a implemntation in C.

## Asset Sources
The first model I used for testing was a GrimChild model by Andre Dudka, reposted by SuicideSquid on [TurboSquid](https://www.turbosquid.com/3d-models/3d-hollow-knight-grimmchild-animated-model-2074482). The original can be found [here](https://sketchfab.com/3d-models/hollow-knight-grimmchild-animation-a3c2474c002f4da78cf6e60288f59ab1)

UV image was from [PostImage](https://postimg.cc/HrxvBss3), but I couldn't find any author.

### Code Assets

Random functions have been taken from:
  - [Ray Tracer Demo](https://github.com/HK-SHAO/Godot-RayTracing-Demo) by HK-SHAO
  - [Hash Functions for GPU Rendering](https://www.shadertoy.com/view/XlGcRh) by Mark Jarzynski and Marc Olano


## Further reading (for me)

- THe ray tracing for the rest of your life book mentions [Stratification](https://raytracing.github.io/books/RayTracingTheRestOfYourLife.html#asimplemontecarloprogram/stratifiedsamples(jittering)). A technique where you sample from a grid instead of random sampling. We already do this for initial rays, however the book mentions that tecniques for secondary rays exist, but are more complicated.

- How to order [descriptor sets](https://stackoverflow.com/questions/76654239/do-we-and-why-do-we-need-to-arrange-descriptor-sets-slots-in-an-ascending-order)

- Do aabb test before all sphere hit test [because](https://computergraphics.stackexchange.com/questions/10396/bvh-uses-aabb-for-a-sphere-in-ray-tracing-the-next-week?rq=1)

- More info on [animations ](https://computergraphics.stackexchange.com/questions/4441/storing-3d-animations-for-ray-tracing?rq=1)

- Add smooth shading (interpolating normals), but there is a [problem](https://computergraphics.stackexchange.com/questions/4986/ray-tracing-shadows-the-shadow-line-artifact?rq=1)

- 3D textures for smoke

- Implement lod variable. Goes down after ray bounce

- Possible bvh optimization from bvh survey: "When traversing a wide BVH, in
most cases, the number of intersecting child nodes will be as few
as 0 to 3, regardless of k. Therefore, one can speed up execution by
adding a code path to sort a small number of nodes and performing
full sort only if there are 4 or more hits"

- Double my buffers, let the cpu and gpu work on seperate buffers, then swap https://community.khronos.org/t/dynamic-memory-allocation-at-runtime/105347/4

- Use blue noise for converging earlier
https://blogs.autodesk.com/media-and-entertainment/wp-content/uploads/sites/162/dither_abstract.pdf

- Spir-V Branching has adjustable weights. See if i can manually optimize them.
https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html#OpBranchConditional

- These cool dithering algorithms are way too good
https://en.wikipedia.org/wiki/Dither#Algorithms
