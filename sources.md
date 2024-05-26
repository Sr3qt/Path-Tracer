
# Sources

This is a list of resources I used to make this project. I thought it might be useful for anyone else wanting to learn more about raytracing, to have all the resources ready and available.

## General reading resources

One of the best places to start with raytracing is the [_Ray Tracing in One Weekend_](https://raytracing.github.io/) series by Peter Shirley et al. There are three books in total, but you only need the first to get started.

Another great resource is the PBR book. It's great if you are not already familiar with 3D rendering and need a helper. 

Free to use book: [Raytracing gems](https://link.springer.com/book/10.1007/978-1-4842-4427-2)

A cool website I did not see until recently is [Scratchapixel.com](https://www.scratchapixel.com/index.html). It seems to have a lot of beginner friendly learning resources on both traditional rasterizing and ray-tracing/path-tracing.


## General CG Math

When I looked at the way [_Ray Tracing The Next Week_](https://raytracing.github.io/books/RayTracingTheNextWeek.html#instances) implements Instancing, I realized I wanted in addition to have scaling as an option, specifically non-uniform scaling. I also wanted it to be in matrix form for its simplicity and speed, you can learn more [here](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/matrices.html). As for the scaling problem, [this](https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/transforming-normals.html) Scratchapixel article explains why normals need special care when transformed using a matrix and how you can transform it correctly. And finally a wiki page on [how to apply matrix transformations](https://en.wikibooks.org/wiki/GLSL_Programming/Applying_Matrix_Transformations) in glsl.


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