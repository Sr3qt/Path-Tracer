#[compute]
#version 450

// Made by following the "Ray Tracing in One Weekend Series"
//  by Peter Shirley, Trevor David Black, Steve Hollasch 
//  https://raytracing.github.io/books/RayTracingInOneWeekend.html

// Currnently following "Ray Tracing The Next Week"

/*
POLICIES
========

The camera points in the negative z direction with positive y being up and positive x being right.

The render image's origin is in the top left. u direction is right and v is down.


RayHit structs don't determine normals and intersection points on-hit. They 
have to have determine_rayhit called on them afterwards to have valid values.

Normals always point outwards from surfaces and are always normalized on creation.

Ray depth starts at 0 and goes up as depth increases.

Materials have something called refraction_depth. When two objects intersect and at least one of them
are translucent, their refraction_depth will be compared. Whicher object which has the lowest 
depth value will have their material represented in the intersection.
Basically it determines if a translucent object cuts into another object or not.

mtl_index and object_index refer to the an material and object in the global material list and 
object list respectively. There may be multiple object lists in which case an object_type enum
will determine which object list object_index points to.
 

LONG TERM GOALS
===============

    - Add detail when standing still

    - Add skybox

    - Add surface textures

    - Make set theory functions possible with objects like add and subtract 
        (can see insides of objects)

    - Subfurface scattering

    - Add lighting

    - Make a real time ray tracer with triangle geometry (will be scuffed)

    - Implement meshlets for more dynamic materials and better culling (for traingles)

*/


// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;


// CONSTANTS
// =========

const float infinity = 1. / 0.;
const double pi_double = 3.1415926535897932385;
const float pi = 3.1415926535897932385;
const float eps = 0.00001;

// object_type enumerator
const int is_not_obj = 0;
const int is_sphere = 1;
const int is_plane = 2;

// BVH child_index enum
const int is_BVHNode = 1;

// The program will keep track of which objects a ray is inside of to do correct calculations
//  i.e. IOR tracking
const int max_depth_inside = 8;
int inside_of_count = 0; // Keeps track of first vacant index in stack
// Holds the object_index, obejct_type and refraction_depth of and object
ivec3 inside_of[max_depth_inside];

// IORs
const float IOR_air = 1.0;
float current_IOR = IOR_air;

// TODO: Move to uniform
const float gammma = 1 / 2.2;

const vec4 default_color = vec4(0.7, 0.7, 0.9, 1);
const int max_depth = 64; // How many bounces is sampled at the most, preferrably multiple of 64

int refraction_bounces = 0; // Counts the number of times a ray has refracted

// Maximum number of children a BVHNode can have
const int max_children = 16;
const int filler_const = int(mod(max_children, 2) + 2.) * 2; 

float random_number;

// DATATYPES
// =========
struct Ray {
    vec3 origin;
    vec3 direction;
};

struct Material {
    // How much of the light between zero and one is reflected for each color, 
    // zero being black
    vec3 albedo; 
    // How much the reflections scatter 
    float roughness; 
    // IDK what this means, metal n stuff, 1 is metal, 0 is dielectric
    float metallic;

    // Value between 0 and 1 where 0 is fully opaque and 1 is fully transparent.
    // Values inbetween determine the energy loss per unit length. 
    // Non-opaque materials can refract.
    float opacity; 
    // Index of refraction
    float IOR;
    // In cases where a translusent object intersects other objects or contains other translusent 
    //  objects, the refraction_depth will determine which object's material will take precedence 
    //  in the intersection
    int refraction_depth;
};

// The materials stored in objects are indices to a global material array
struct Plane {
    vec3 normal;
    float d;
    int mtl_index;
    int filler1; // Not needed since i dont pass in planes, YET
    int filler2;
    int filler3;
};

struct Sphere {
    vec3 center;
    float radius;
    int mtl_index;
    int filler[3];
};

struct RayHit {
    bool hit; // Whether the ray actually hit something
    bool is_initialized; // Whether values like point and normal are determined

    // Stored on-hit
    Ray ray;
    float t; // Paramater value for ray
    int object_type; // enum for what type of object was hit
    int object_index; // The index of object hit in their respective object list, provided by object_type

    // Retrieved later
    int mtl_index; // Material of the object hit
    vec3 point; // Intersection point between sphere and ray
    vec3 normal;
    vec4 color; // Whatever color the rayhit is determined to be 

};

struct Range {
    float start; 
    float end;
};

struct AABB {
    // only xyz used, they are vec4 to fit memory allocation
    // minimum.x < maximum.x etc. should always be true, use create_AABB function to be safe
    vec4 minimum;
    vec4 maximum;
};

struct ChildIndex {
    // Small struct to add labels to child indices in a BVHNode
    int index; // Points to a child BVHNode if object_type is 0, else it points to an object 
    int object_type; // Specifies the object_type index points to. If object_type is 0, it points to
    // another BVHNode
};

// BVH should be shared across all groups, how doe? Might make compute shader to make BVH
struct BVHNode {
    // A BVHNode is an node in a n-ary tree. They are stored in a global BVH buffer. Every node 
    //  points to its parents, its own and its childrens indicies in the list. 
    //  Instead of pointing to a child node it might point to an object in specified object list
    
    // TODO: compact BVHNode struct, its a little to big.
    ChildIndex children[max_children]; // List of children, see ChildIndex
    int temp_fill[filler_const];
    AABB bbox; // Bounding box that encompasses all children 
    int child_count; // Says how many ChildIndixes actually exist and are valid
    int parent; // Index to parent in BVH list. This value is currently unused.
    int self; // Index to self in the BVH list, -1 means the node position is not finalized
    // -2 means BVHNode doesn't exist. This value is currently unused.
    int filler;

};


// BUFFERS
// =======
layout(r32f, set = 0, binding = 0) uniform restrict image2D output_image;

layout(set = 0, binding = 1, std430) restrict buffer ImageSize {
    int width;
    int height;
}
image;

// Camera
layout(set = 1, binding = 0, std430) restrict buffer CameraBuffer {
    vec3 pos;
    float focal_length;
    vec3 right;
    float viewport_width;
    vec3 up;
    float viewport_height;
    vec3 forward;
    float filler1;
}
camera;

layout(set = 1, binding = 1, std430) restrict buffer LODBuffer {
    int samples_per_pixel; // How many rays are sent per pixel
    int max_default_depth; // How many bounces is sampled, for normal rays
    int max_refraction_bounces; // How many total extra bounces can occur on refraction
}
LOD;

// Materials to index
layout(set = 2, binding = 0, std430) restrict buffer MaterialBuffer {
    Material data[];
}
materials;

// Objects
layout(set = 2, binding = 1, std430) restrict buffer SpheresBuffer {
    Sphere data[];
}
spheres;

layout(set = 2, binding = 2, std430) restrict buffer PlanesBuffer {
    Plane data[];
}
planes;

// BVH tree in list form
layout(set = 3, binding = 0, std430) restrict buffer BVH_List {
    BVHNode list[];
}
BVH;

layout(set = 4, binding = 0, std430) restrict buffer FlagBuffer {
    bool use_bvh;
    bool show_bvh_depth;
    bool scene_changed;
}
flags;

layout(set = 4, binding = 1, std430) restrict buffer RandomBuffer {
    float time;
}
random;

// UTILITY FUNCTIONS
// =================

Ray empty_ray() {
    return Ray(vec3(0,0,0), vec3(0,0,0));
}

Material empty_material() {
    return Material(vec3(0,0,0), 0., 0., 1., IOR_air, 0);
}

Sphere empty_sphere() {
    return Sphere(vec3(0,0,0), 0., 0, int[](0,0,0));
}

Plane empty_plane() {
    return Plane(vec3(0,0,0), 0., 0, 0,0,0);
}

RayHit empty_rayhit() {
    return RayHit(false, false, empty_ray(), infinity, 0, 0, 0,
                  vec3(0,0,0), vec3(0,0,0), vec4(0,0,0,0));
}

ChildIndex empty_child_index() {
    return ChildIndex(0, 0);
}

// BVHNode empty_BVHNode() {
//     ChildIndex children[max_children];
//     for (int i = 0; i < max_children + filler_const / 2; i++) {
//         children[i] = empty_child_index();
//     }
//     AABB bbox = AABB(vec4(0), vec4(0));
//     return BVHNode(children, int[filler_const](0, 0), bbox, 0, 0, 0, 0);
// }

AABB create_AABB(vec3 point1, vec3 point2) {
    return AABB(vec4(min(point1, point2), 0), vec4(max(point1, point2), 0));
}

AABB sphere_AABB(Sphere sphere) {
    // Calculate AABB for a sphere
    vec3 radius_vec = vec3(sphere.radius);
    return AABB(vec4(sphere.center - radius_vec, 0), vec4(sphere.center + radius_vec, 0));
}

AABB merge_AABB(AABB box1, AABB box2) {
    // Make a new AABB tow fit two other AABBs
    AABB out_AABB;
    out_AABB.minimum = min(box1.minimum, box2.minimum);
    out_AABB.maximum = min(box1.maximum, box2.maximum);
    return out_AABB;
}

void expand_AABB(inout AABB bbox, float delta) {
    float padding = delta / 2.;
    bbox.minimum -= padding;
    bbox.maximum += padding;
}

bool intersect_AABB(AABB bbox1, AABB bbox2) {
    // Returns whether two AABB intersect
    for (int i = 0; i < 3; i++) {
        if (bbox1.minimum[i] > bbox2.maximum[i] || bbox1.maximum[i] < bbox2.minimum[i]) {
            return false;
        }
    }
    return true;
}

float rand(float seed) {
    return fract((seed * 23489.52364) / 0.0836);
}

float rand2(vec2 co) { 
  return fract(sin(dot(co.xy, vec2(12.9898,78.233))) * 43758.5453);
}

vec3 rand_vec3(vec3 point) {
    // Creates a normalized vector in a random direction from a point 
    float i = 0;
    while (true) {
        vec3 n = vec3(rand2(point.xy + i), rand2(point.xz + i), rand2(point.yz + i));
        if (dot(n, n) < 1.) {
            return normalize(n);
        }
        i++;
    }
}

void swap(inout float a, inout float b) {
    // Swap the values of two floats
    a = a + b;
    b = a - b;
    a = a - b;
}


bool is_close(float value1, float value2) {
    // Whether a value is within an epsilon of value2
    return (value2 + eps > value1 && value1 > value2 - eps);
}

bool near_zero(vec3 vec) {
    // Whether a vec3 is close to zero in all fields
    return (vec.x < eps && vec.y < eps && vec.z < eps);
}

bool in_range(float value, Range range) {
    // In range inclusively start and stop values
    return (range.start <= value && range.end >= value);
}

bool xin_range(float value, Range range) {
    // In range exclusively start and stop values
    return (range.start < value && range.end > value);
}

vec3 ray_at(Ray ray, float t) {
    return ray.origin + ray.direction * t;
}


// BVH FUNCTIONS
// =============

void create_BVH_list() {

    int sphere_array_length = spheres.data.length();
    int other_array_length = 0;

    int total_length = sphere_array_length + other_array_length;

    // Create a Node for every object in all object lists
    // int running_length = 0;
    // for (int i = 0; i < sphere_array_length; i++) {
    //     BVHNode temp = empty_BVHNode();
    //     temp.children[0] = ChildIndex(i, is_sphere);
    //     temp.bbox = sphere_AABB(spheres.data[i]);
    //     temp.self = -1;
    //     BVH.list[i] = temp;
    // }
    // running_length += sphere_array_length;

    // pseudo code for other object lists
    // for (int i = 0; i < other_array_length; i++) {
    //     BVHNode temp = empty_BVHNode();
    //     temp.children[0] = ChildIndex(-1, object_type, i, 0);
    //     temp.bbox = AABB_of_obj(obj_list.data[i]);
    //     temp.self = -1;
    //     BVH.list[i + running_length] = temp;
    // }
    // running_length += other_array_length;

    // Simple, naive merge method
    // for (int i = 0; i < running_length - 1; i++) {
    //     if (BVH.list[i].self != -2) {
    //         continue;
    //     }
    //     for (int j = i + 1; j < running_length; j++) {
    //         // If node doesn't exist, continue
    //         if (BVH.list[j].self != -2) {continue;}
    //         // If nodes don't intersect, continue
    //         if (!intersect_AABB(BVH.list[i], BVH.list[j])) {continue;}

    //     }
    // }

    // Merge intersecting nodes
    // for (int i = 0; i < running_length - 1; i++) {
    //     BVHNode node1 = BVH.list[i];
    //     if (node1.self != -2) {
    //         continue;
    //     }
    //     for (int j = i + 1; j < running_length; j++) {
    //         BVHNode node2 = BVH.list[j];
    //         // If node doesn't exist, continue
    //         if (node2.self != -2) {continue;}
    //         // If nodes don't intersect, continue
    //         if (!intersect_AABB(node1.bbox, node2.bbox)) {continue;}

    //         // if ()

    //     }
    // }

}




// RAY-HIT FUNCTIONS
// =============

vec4 hit_skybox(Ray ray, inout RayHit rayhit) {
    // TODO: Implement skybox texture and hit detection
    return default_color;
}

void set_rayhit(inout RayHit rayhit, float t, Ray ray, int object_type, int object_index) {
    rayhit.hit = true;
    rayhit.t = t;
    rayhit.ray = ray;
    rayhit.object_type = object_type;
    rayhit.object_index = object_index;
}

bool hit_AABB(Ray ray, AABB bbox, Range range, vec3 inv_dir, bvec3 is_dir_neg) {
    // Returns true if ray hits aabb within given range
    for (int i = 0; i < 3; i++) {
        float orig = ray.origin[i]; // This is an optimazation. Source: Trust me (real)
        float t0 = ((bbox.minimum[i] - orig) * inv_dir[i]);
        float t1 = ((bbox.maximum[i] - orig) * inv_dir[i]);

        // Make sure t0 is smallest
        if (is_dir_neg[i]) {swap(t0, t1);}

        if (t0 > range.start) {range.start = t0;}
        if (t1 < range.end) {range.end = t1;}

        if (range.end <= range.start) {return false;}
    }
    return true;
}

RayHit hit_sphere(Ray ray, int sphere_index, Range t_range, inout RayHit rayhit) {

    Sphere sphere = spheres.data[sphere_index];
    // Calculate the determinant of quadratic formula
    vec3 oc = ray.origin - sphere.center;
    float a = dot(ray.direction, ray.direction);
    float half_b = dot(oc, ray.direction);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;

    float discriminant = half_b * half_b - a*c;

    // Early return if ray does not hit
    if (discriminant < 0.) {
        return rayhit;
    } 

    float sqrtd = sqrt(discriminant);
    float root = (-half_b - sqrtd) / a;

    // If root is within a valid t range and less than previous rayhit
    if (!in_range(root, t_range) || root > rayhit.t) {
        root = (-half_b + sqrtd) / a;
        if (!in_range(root, t_range)  || root > rayhit.t) {
            return rayhit;
        }
    }

    // Set rayhit variables
    set_rayhit(rayhit, root, ray, is_sphere, sphere_index);

    return rayhit;
}

RayHit hit_spheres(Ray ray, Range t_range, inout RayHit rayhit) {
    // Uses global scope sphere array to bypass function parameter limitations
    for (int i = 0; i < spheres.data.length(); ++i) {
        hit_sphere(ray, i, t_range, rayhit);
    }
    return rayhit;
}

RayHit hit_plane(Ray ray, int plane_index, Range t_range, inout RayHit rayhit) {
    
    Plane plane = planes.data[plane_index];

    // Early return if plane is paralell, even if the ray is contained in the plane
    // May not be needed
    // bool is_paralell = is_close(dot(ray.direction, plane.normal), 0.);
    // if (is_paralell) {
    //     return rayhit;
    // }

    // float intersection_t = plane.d / dot(plane.normal, ray.origin + ray.direction);
    // float intersection_t = (dot((vec3(0) - ray.origin), plane.normal) /
    //                         dot(plane.normal, ray.direction));
                            
    float intersection_t = ((plane.d - dot(ray.origin, plane.normal)) /
                            dot(plane.normal, ray.direction));

    // Early return if t is not in range or further away than previous t
    if (!in_range(intersection_t, t_range) || intersection_t > rayhit.t) {
        return rayhit;
    }

    // Set rayhit variables
    set_rayhit(rayhit, intersection_t, ray, is_plane, plane_index);

    return rayhit;
}

RayHit hit_planes(Ray ray, Range t_range, inout RayHit rayhit) {
    // Uses global scope planes array to bypass function parameter limitations
    for (int i = 0; i < planes.data.length(); ++i) {
        hit_plane(ray, i, t_range, rayhit);
    }
    return rayhit;
}

RayHit hit_object(Ray ray, Range range, inout RayHit rayhit, int object_index, int object_type) {
    // Chooses the appropriate hit_ function for given object_type
    if (object_type == is_sphere) {
        return hit_sphere(ray, object_index, range, rayhit);
    }
}

RayHit determine_rayhit(inout RayHit rayhit) {
    // Resolves intersextion point, normal and other information from rayhit 
    rayhit.point = ray_at(rayhit.ray, rayhit.t);

    // Procedure for hitting sphere
    if (rayhit.object_type == is_sphere) {
        Sphere sphere = spheres.data[rayhit.object_index];
        rayhit.mtl_index = sphere.mtl_index;
        rayhit.normal = (rayhit.point - sphere.center) / sphere.radius;
        rayhit.color = vec4(materials.data[rayhit.mtl_index].albedo, 1);
    
    // Procedure for hitting plane
    } else if (rayhit.object_type == is_plane) {
        Plane plane = planes.data[rayhit.object_index];
        rayhit.mtl_index = plane.mtl_index;
        rayhit.normal = plane.normal;
        rayhit.color = vec4(materials.data[rayhit.mtl_index].albedo, 1);
    }

    rayhit.is_initialized = true;
    return rayhit;
}

RayHit check_ray_hit(Ray ray, Range range) {
    
    RayHit rayhit = empty_rayhit();
    hit_spheres(ray, range, rayhit);
    
    // Hit planes if there are any
    if (!near_zero(planes.data[0].normal)) {
        hit_planes(ray, range, rayhit);
    }

    // TODO ADD intersection with skybox, would still count as not hit
    if (!rayhit.hit) {
        rayhit.color = default_color;
    }

    return rayhit;
}


// TODO: THis is slower than normal rendering. Has to change!
RayHit check_ray_hit_BVH(Ray ray, Range range) {
    // Like check_ray_hit but it checks against a BVH tree instead of each object_list individually
    RayHit rayhit = empty_rayhit();

    // Stack of indices of nodes yet to traverse
    // NOTE: might need to be bigger for larger scenes and/or with higher order trees
    int to_visit[512];
    // Index to top of the stack, points to vacant spot ABOVE the stack
    int to_visit_i = 0;

    // Index to current node being processed
    int current_index = 0;

    // Pre-compute values for hit detection
    vec3 inv_direction = vec3(1. / ray.direction.x, 1. / ray.direction.y, 1. / ray.direction.z);
    bvec3 dir_is_negative = bvec3(inv_direction.x < 0., inv_direction.y < 0., inv_direction.z < 0.);

    int hit_check_count = 0;
    while (true) {
        BVHNode node = BVH.list[current_index];

        hit_check_count++;
        if (hit_AABB(ray, node.bbox, range, inv_direction, dir_is_negative)) {
            // Loop over child indices to add them to stack or do hit check
            for (int i = node.child_count; i > 0; i--) {
                ChildIndex tochild = node.children[i - 1];
                // If children[i].index points to inner node, add it to to_visit
                if (tochild.object_type == is_not_obj) {
                    to_visit[to_visit_i++] = tochild.index;
                } 
                // children[i].index points to object_index, do a hit test
                else {
                    hit_object(ray, range, rayhit, tochild.index, tochild.object_type);
                    hit_check_count++;
                }
            }
        } 
        // Break if no more nodes to visit, else go to next node in list
        if (to_visit_i == 0) {break;}
        current_index = to_visit[--to_visit_i];
    }

    // Hit planes if there are any
    if (!near_zero(planes.data[0].normal)) {
        hit_planes(ray, range, rayhit);
    }

    // TODO ADD intersection with skybox, would still count as not hit
    if (!rayhit.hit) {
        rayhit.color = hit_skybox(ray, rayhit);
    }

    if (flags.show_bvh_depth) {
        rayhit.color = vec4(0.04 * float(hit_check_count),0,1,0);
    }

    return rayhit;
}

// RAY-BOUNCE FUNCTIONS
// ====================
Ray reflect_ray(Ray ray_in, RayHit rayhit) {
    // Returns a new reflected ray based on ray_in and rayhit
    vec3 reflected_dir = reflect(ray_in.direction, rayhit.normal) * materials.data[rayhit.mtl_index].metallic;
    vec3 dir_offset = rand_vec3(rayhit.point) * (1. - materials.data[rayhit.mtl_index].metallic);

    Ray ray_out = Ray(rayhit.point, reflected_dir + dir_offset);
    
    // Reflects ray if it points into the object
    if (dot(ray_out.direction, rayhit.normal) < 0.) {
        ray_out.direction = reflect(ray_out.direction, rayhit.normal);
    }

    return ray_out;
}

Ray refract_ray(Ray ray_in, inout RayHit rayhit) {
    // Returns a refracted or reflected ray based on ray_in and rayhit
    Ray ray_out;
    ray_out.origin = rayhit.point;

    // Whether object is inside the current object
    bool is_inside = bool(dot(rayhit.normal, ray_in.direction) > 0.);
    float eta_in = current_IOR;

    // if (inside_of_count == 1) {}

    float eta_out = (is_inside) ? IOR_air : materials.data[rayhit.mtl_index].IOR;

    float eta;
    eta = eta_in / eta_out;

    // TODO: Finish refraction depth thingy, glass inside glass renders wrongly
    // for (int i = 0; i < inside_of_count; i++) {}

    vec3 normalized_direction = normalize(ray_in.direction);
    vec3 normal = (is_inside) ? -rayhit.normal : rayhit.normal;

    // Calculate whether angle is shallow enough to disallow refraction
    float cos_theta = min(dot(-normalized_direction, normal), 1.);
    float sin_theta = sqrt(1. - cos_theta * cos_theta);
    bool cannot_refract = eta * sin_theta > 1.;

    // // Check for internal reflection
    if (cannot_refract) {
        ray_out.direction = reflect(normalized_direction, normal);
        return ray_out;
    } 

    // Schlick's approximation for reflectivety
    float r0 = (1. - eta) / (1. + eta);
    r0 = r0 * r0;
    float reflect_chance = r0 + (1. - r0) * pow(1. - cos_theta, 5.);
    
    // Check for external reflection, TODO can add reflexivety for translucent materials
    if (reflect_chance > rand2(vec2(cos_theta, normal.x))) {
        ray_out.direction = reflect(normalized_direction, normal);
        return ray_out;
    }

    current_IOR = eta_out;

    // If ray was inside and went out, remove from inside_of list
    if (is_inside) {
        inside_of[inside_of_count--] = ivec3(0,0,0);
    } else {
        // If ray was outside and refracted, add to inside_of list
        inside_of[inside_of_count++] = ivec3(rayhit.object_index, rayhit.object_type, 
        materials.data[rayhit.mtl_index].refraction_depth);
    }

    // Add extra available bounces when ray refracts
    if (refraction_bounces < LOD.max_refraction_bounces - 1) {refraction_bounces++;}

    ray_out.direction = refract(normalized_direction, normal, eta);
    return ray_out;
}

Ray scatter_ray(Ray ray_in, inout RayHit rayhit) {
    // TODO Change the way rays are created based on roughness, less/ more scatter
    // Returns a scattered ray based on ray_in and rayhit
    vec3 ray_dir = rand_vec3(rayhit.point) + rayhit.normal;

    // If created ray pointed in opposite direction of normal
    if (near_zero(ray_dir)) {
        ray_dir = rayhit.normal;
    }

    if (dot(ray_dir, rayhit.normal) < 0.) {
        ray_dir *= -1.;
    }

    Ray ray_out = Ray(rayhit.point, ray_dir);
    return ray_out;
}

Ray bounce_ray(Ray ray_in, RayHit rayhit) {
    // Creates a new ray based material properties from the previous rayhit

    if (materials.data[rayhit.mtl_index].opacity < 1.) {
        return refract_ray(ray_in, rayhit);
    }

    if (materials.data[rayhit.mtl_index].metallic > 0.) {
        return reflect_ray(ray_in, rayhit);
    }

    return scatter_ray(ray_in, rayhit);
}

// MAIN FUNCTIONS
// ==============
vec4 cast_ray(Ray ray, Range range) {
    // Casts a ray with bounces and returns the color of the ray

    vec4 out_col = default_color;

    // Rayhit's color should determined in reverse order, so we to store them for later
    RayHit rayhits[64];

    // Calculate rayhits
    Ray new_ray = ray;
    RayHit rayhit;
    int i = 0;
    refraction_bounces = 0;

    for (;i < LOD.max_default_depth + refraction_bounces; i++) {
        if (flags.use_bvh) {
            rayhit = check_ray_hit_BVH(new_ray, range);

            // Send one ray, skip bouncing
            if (flags.show_bvh_depth) {
                rayhits[i] = rayhit;
                i++; // Breaking doesn't increment therefore we have to correct for it
                break;
            }
        } else {
            rayhit = check_ray_hit(new_ray, range);
        }
        
        // Early break if no hit
        if (!rayhit.hit) {
            // Adds sky color as the last rayhit when miss
            rayhits[i] = rayhit;
            i++; // Breaking doesn't increment therefore we have to correct for it
            break;
        }

        determine_rayhit(rayhit);

        new_ray = bounce_ray(new_ray, rayhit);
        
        rayhits[i] = rayhit;
    } 

    if (i == 0) {return out_col;} // Early return if no rays were hit

    i--; // Correct i to be last index of rayhits

    // Determine each ray color in reverse order
    // TODO: implement attenuation based on incident and exiting angles
    vec4 new_color = rayhits[i].color;
    for (int j = i; j > 0; j--) {
        new_color = new_color * rayhits[j - 1].color; // temp
    }

    return new_color;
}


// The code we want to execute in each invocation
void main() {
    
    // VARIABLE DEFINITIONS
    // ====================
    const float width = float(image.width);
    const float height = float(image.height);

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    const vec3 viewport_u = camera.right * camera.viewport_width;
    const vec3 viewport_v = -camera.up * camera.viewport_height;

    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    const vec3 pixel_delta_u = viewport_u / width;
    const vec3 pixel_delta_v = viewport_v / height;

    // Calculate the location of the upper left pixel.
    const vec3 viewport_upper_left = camera.pos - camera.forward * camera.focal_length -
                                     (viewport_u + viewport_v) / 2.;

    const vec3 pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);

    // gl_GlobalInvocationID uniquely identifies this invocation across all work groups
    const uvec3 UVu = gl_GlobalInvocationID;
    const ivec3 UVi = ivec3(gl_GlobalInvocationID);
    const vec3 UV = vec3(UVi);

    // CODE
    // ====
    vec3 pixel_center = pixel00_loc + (UV.x * pixel_delta_u) + (UV.y * pixel_delta_v);

    vec4 new_color = vec4(0,0,0,1);
    float circle_step = 2 * pi / float(LOD.samples_per_pixel);
    for (int i = 0; i < LOD.samples_per_pixel; ++i) {
        float temp = fract(float(i) / float(LOD.samples_per_pixel));
        vec3 circular_offset = pixel_delta_u / 2 * cos(float(i) * circle_step) * rand(float(random.time)) + 
                               pixel_delta_v / 2 * sin(float(i) * circle_step) * rand(float(random.time));
        vec3 ray_direction = pixel_center - camera.pos + circular_offset;
        Ray ray = Ray(camera.pos, ray_direction);

        new_color += cast_ray(ray, Range(0.001, infinity));
    }
    new_color = new_color / LOD.samples_per_pixel;

    // Apply gamma correction
    new_color.rgb = pow(new_color.rgb, vec3(gammma, gammma, gammma));

    if (flags.scene_changed) {
        imageStore(output_image, UVi.xy, new_color);
    } else {
        vec4 prev_col = imageLoad(output_image, UVi.xy);
        imageStore(output_image, UVi.xy, (new_color + prev_col) / 2.);
    }
}