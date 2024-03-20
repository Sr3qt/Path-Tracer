
# Sources

This is a list of resources I used to make this project. I thought it might be useful for anyone else wanting to learn more about raytracing, to have all the resources ready and available.

## General reading resources

One of the best places to start with raytracing is the [_Ray Tracing in One Weekend_](https://raytracing.github.io/) series by Peter Shirley et al. There are three books in total, but you only need the first to get started.

Another great resource is the PBR book. It's great if you are not already familiar with 3D rendering and need a helper. 

Free to use book: [Ratracing gems](https://link.springer.com/book/10.1007/978-1-4842-4427-2)

## Camera / Color theory

Unironically one of the deepest fields out of everything required to build a ray tracer. Luckily only surface level knowledge is required for most use cases, but if you want to learn more, here are some useful resources:

- Why use gamma: [Understanding Gamma Correction](https://www.cambridgeincolour.com/tutorials/gamma-correction.htm). Cambridge in Colour
- Common color conversion forumlas, used by OpneCV - [Color conversions](https://docs.opencv.org/3.1.0/de/d25/imgproc_color_conversions.html) 


[Back to the top](#sources)😭

## Bounding Volume Hierarchy (BVH)

There are many considerations for choosing specific BVH algorithms over another.

- *A Survey on Bounding Volume Hierarchies for Ray Tracing* by Daniel Meister et al. is an in depth overview of BVH algorithms and can be found [here](https://meistdan.github.io/publications/bvh_star/paper.pdf). It explains the basics problems for why BVHs are needed in the first place and gives examples of some common generation algorithms and some very useful ones.

  Some notable examples include:
  - "Chitalu et al. [CDK20] combine LBVH with an ostensibly-implicit layout... [ ] ... This algorithm is the fastest construction algorithm to date."
  - "[Talking about 2015 Bittner algorithm]  This algorithm produces BVHs of the highest possible quality at the cost of higher build times."

- If you need help implementing a certain algorithm, [this](https://github.com/madmann91/bvh) is a c++ library of different BVH creation algorithms by madmann91.