
# Sources

This is a list of resources I used to make this project. I thought it might be useful for anyone else wanting to learn more about raytracing, to have all the resources ready and available.

## General reading resources

One of the best places to start with raytracing is the [_Ray Tracing in One Weekend_](https://raytracing.github.io/) series by Peter Shirley et al. There are three books in total, but you only need the first to get started.

Another great resource is the PBR book. It's great if you are not already familiar with 3D rendering and need a helper. 

Free to use book: [Raytracing gems](https://link.springer.com/book/10.1007/978-1-4842-4427-2)

A cool website I did not see until recently is [Scratchapixel.com](https://www.scratchapixel.com/index.html). It seems to have a lot of beginner friendly learning resources on both traditional rasterizing and ray-tracing/path-tracing.

IDK this dude built smthjn cool https://github.com/TomClabault/HIPRT-Path-Tracer/

Cool test scenes https://benedikt-bitterli.me/resources/


## General CG Math

When I looked at the way [_Ray Tracing The Next Week_](https://raytracing.github.io/books/RayTracingTheNextWeek.html#instances) implements Instancing, I realized I wanted in addition to have scaling as an option, specifically non-uniform scaling. I also wanted it to be in matrix form for its simplicity and speed, you can learn more [here](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/matrices.html). As for the scaling problem, [this](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/transforming-normals.html) Scratchapixel article explains why normals need special care when transformed using a matrix and how you can transform it correctly. And finally a wiki page on [how to apply matrix transformations](https://en.wikibooks.org/wiki/GLSL_Programming/Applying_Matrix_Transformations) in glsl.


## GPU limitations
For sampled textures I wanted to be able to add arbitrary textures to an array and simply index the array. This would be preferable over TextureArrays since they have to have tha same size and type, whereas this would not. However, for this I would require to use the Vulkan [descriptor index extension](https://docs.vulkan.org/samples/latest/samples/extensions/descriptor_indexing/README.html). Still I made it work, with the only caveat being that the maximum number of textures have to be set. It might be theoretically possible to have a variable size texture array, but godot throws an error thinking the array size is 1. DethRaid also seem to enconter this issue in their [Vulkan engine implementation](https://gist.github.com/DethRaid/0171f3cfcce51950ee4ef96c64f59617).

Also, at the time of writing, it is not well documented how to give arrays of textures/buffers to the shaderpipeline in godot, even though it's very easy. Simply add more buffer ids to the RDShaderUniform.

This [blogpost](http://chunkstories.xyz/blog/a-note-on-descriptor-indexing/) for Chunk Stories helped explain array texture vs array of textures, as well as what _dynamic non-uniform_ means.

A nice [video](https://www.youtube.com/watch?v=YTfdBSjitd8) by 
Aurailus related to the same problem of needing to bind many textures, although it is in OpenGL not Vulkan (Would still advise looking at the comments, especially by @fabiangiesen306).


## GPU precision considerations

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

## Fast Ray-Triangle Intersection

For complex scenes a fast ray-triangle intersection test is crucial for maintaining passable performance.

- The most known and one of the best performing intersection algorithms is the Möller-Trumbore algorithm. The original paper is freely available and can be found [here](http://www.graphics.cornell.edu/pubs/1997/MT97.pdf) and a branchless glsl implementation by BrunoLevy can be found [here](https://stackoverflow.com/questions/42740765/intersection-between-line-and-triangle-in-3d/42752998#42752998)

- According to some guy on StackOverflow (Gaslight Deceive Subvert), the fastest algorithm they tested was made by Havel and Herout, claiming it to be twice as fast as the tried and true Möller-trumbore algorithm. [Here](https://stackoverflow.com/a/44837726) is a implemntation in C.

## Asset Sources
The first model I used for testing was a GrimChild model by Andre Dudka, reposted by SuicideSquid on [TurboSquid](https://www.turbosquid.com/3d-models/3d-hollow-knight-grimmchild-animated-model-2074482). The original can be found [here](https://sketchfab.com/3d-models/hollow-knight-grimmchild-animation-a3c2474c002f4da78cf6e60288f59ab1)

UV image was from [PostImage](https://postimg.cc/HrxvBss3), but I couldn't find any author.

## Further reading (for me)
- THe ray tracing for the rest of your life book mentions [Stratification](https://raytracing.github.io/books/RayTracingTheRestOfYourLife.html#asimplemontecarloprogram/stratifiedsamples(jittering)). A technique where you sample from a grid instead of random sampling. We already do this for initial rays, however the book mentions that tecniques for secondary rays exist, but are more complicated.

- How to order [descriptor sets](https://stackoverflow.com/questions/76654239/do-we-and-why-do-we-need-to-arrange-descriptor-sets-slots-in-an-ascending-order)