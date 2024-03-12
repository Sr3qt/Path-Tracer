
# Sources

This is a list of resources I used to make this project. I thought it might be useful for anyone else wanting to learn more about raytracing, to have all the resources ready and available.

## General reading resources

One of the best places to start with raytracing is the [_Ray Tracing in One Weekend_](https://raytracing.github.io/) series by Peter Shirley et al. There are three books in total, but you only need the first to get started.

Another great resource is the PBR book. It's great if you are not already familiar with 3D rendering and need a helper. 


## Camera / Color theory

Unironically one of the deepest fields out of everything required to build a ray tracer. Luckily only surface level knowledge is required for most use cases, but if you want to learn more, here are some useful resources:

- Why use gamma: [Understanding Gamma Correction](https://www.cambridgeincolour.com/tutorials/gamma-correction.htm). Cambridge in Colour
- Common color conversion forumlas, used by OpneCV - [Color conversions](https://docs.opencv.org/3.1.0/de/d25/imgproc_color_conversions.html)


[Back to the top](#sources)😭

## Bounding Volume Hierarchy (BVH)

There are many considerations for choosing specific BVH algorithms over another.

- If you need help implementing a certain algorithm, [this](https://github.com/madmann91/bvh) is a c++ library of different BVH creation algorithms by madmann91.