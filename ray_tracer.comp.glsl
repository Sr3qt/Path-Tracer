#[compute]
#version 450

// Made by following the "Ray Tracing in One Weekend Series"
//  by Peter Shirley, Trevor David Black, Steve Hollasch 
//  https://raytracing.github.io/books/RayTracingInOneWeekend.html#antialiasing 

// Currnently following "Ray Tracing The Next Week"

/*
POLICIES
========

The camera points in the negative z direction with y being up and x being right.

The render image's origin is in the top left. u direction is right and v is down.


RayHit structs don't determine normals and intersection points on-hit. They 
have to have determine_rayhit called on them afterwards to have valid values.

Normals always point outwards from surfaces and are always normalized on creation.

Ray depth starts at 0 and goes up as depth increases

mtl_index and obj_index refer to the an material and object in the global material list and 
object list respectively. There may be multiple object lists in which case an object_type enum
will determine which  


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

// obj_type enumerator
const int is_not_obj = 0;
const int is_sphere = 1;
const int is_plane = 2;

// BVH child_index enum
const int is_BVHNode = 1;

// IORs
const float IOR_air = 1.0;
float current_IOR = IOR_air;

const vec4 default_color = vec4(0.7, 0.7, 0.9, 1);
const int samples_per_pixel = 1; // How many rays are sent per pixel
const int max_depth = 8; // How many bounces is sampled at the most

// Maximum number of children a BVHNode can have
const int max_children = 2;

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
    bool is_inside; // Whether ray is traveling inside an object
    float current_IOR; // IOR of the material the ray is currently travelling through; 
    // Bad implementation ^^ use global variable to track current IOR of ray

    // Stored on-hit
    Ray ray;
    float t; // Paramater value for ray
    int obj_type; // enum for what type of object was hit
    int obj_index; // The index of object hit in their respective object list, provided by obj_type

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
    int child_node; // Points to a child BVHNode, if is_BVHNode is 1, -1 otherwise
    int obj_type; // Specifies the object type obj_index points to, if is_BVHNode is 0, 0 otherwise
    int obj_index; // Points to an object in an object list specified by obj_type, 
    // if is_BVHNode is 0, -1 otherwise

    int is_BVHNode; // Is 1 if this points to a BVHNode, 0 otherwise
};

// BVH should be shared across all groups, how doe? Might make compute shader to make BVH
struct BVHNode {
    // A BVHNode is an node in a n-ary tree. They are stored in a global BVH buffer. Every node 
    //  points to its parents, its own and its childrens indicies in the list. 
    //  Instead of pointing to a child node it might point to an object in specified object list
    
    ChildIndex children[max_children]; // List of children, see ChildIndex
    AABB bbox; // Bounding box that encompasses all children 
    int child_count;
    int parent; // Index to parent in BVH list
    int self; // Index to self in the BVH list, -1 means the node position is not finalized
    // -2 means BVHNode doesn't exist
    int filler;

};


// BUFFERS
// =======
layout(r32f, set = 0, binding = 0) uniform restrict writeonly image2D output_image;

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

// Materials to index
// layout(set = 2, binding = 0, std430) restrict buffer MaterialBuffer {
//     Material data[];
// }
// materials;
// Will start to pass in materials later

// Objects
layout(set = 2, binding = 1, std430) restrict buffer SpheresBuffer {
    Sphere data[];
}
spheres;

layout(set = 4, binding = 0, std430) restrict buffer BVH_List {
    BVHNode list[];
}
BVH;




// TEMP STRUCT CREATION
// ====================
Material empty_mat = Material(vec3(0,0,0), 0., 0., 1., IOR_air);
Material mat = Material(vec3(0,0.7,1), 0., 0., 1., 1.);
Material mat1 = Material(vec3(0.1, 0.75, 0.1), 0., 0., 1., 1.);
Material metal = Material(vec3(0.5,0.8,0.96), 0., 1., 1., 1.);
Material glass = Material(vec3(0.5,0.8,0.96), 0., .0, 0., 1.6);

Material mtls[5] = Material[](
    empty_mat,
    mat, 
    mat1, 
    metal,
    glass
);

Plane plane = Plane(vec3(0,1,0), -1., 2, 0,0,0);
Plane planes[1] = Plane[](
    Plane(vec3(0,1,0), -1., 2, 0,0,0)
);


// UTILITY FUNCTIONS
// =================

Ray empty_ray() {
    return Ray(vec3(0,0,0), vec3(0,0,0));
}

Material empty_material() {
    return Material(vec3(0,0,0), 0., 0., 1., IOR_air);
}

Sphere empty_sphere() {
    return Sphere(vec3(0,0,0), 0., 0, int[](0,0,0));
}

Plane empty_plane() {
    return Plane(vec3(0,0,0), 0., 0, 0,0,0);
}

RayHit empty_rayhit() {
    return RayHit(false, false, false, IOR_air, empty_ray(), infinity, 0, 0, 0,
                  vec3(0,0,0), vec3(0,0,0), vec4(0,0,0,0));
}

ChildIndex empty_child_index() {
    return ChildIndex(-1, 0, -1, 0);
}

BVHNode empty_BVHNode() {
    ChildIndex children[max_children];
    for (int i = 0; i < max_children; i++) {
        children[i] = empty_child_index();
    }
    AABB bbox = AABB(vec4(0), vec4(0));
    return BVHNode(children, bbox, 0, 0, 0, 0);
}

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
    while (true) {
        vec3 n = vec3(rand2(point.xy), rand2(point.xz), rand2(point.yz));
        if (dot(n, n) < 1.) {
            return normalize(n);
        }
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
    int running_length = 0;
    for (int i = 0; i < sphere_array_length; i++) {
        BVHNode temp = empty_BVHNode();
        temp.children[0] = ChildIndex(-1, is_sphere, i, 0);
        temp.bbox = sphere_AABB(spheres.data[i]);
        temp.self = -1;
        BVH.list[i] = temp;
    }
    running_length += sphere_array_length;

    // pseudo code for other object lists
    // for (int i = 0; i < other_array_length; i++) {
    //     BVHNode temp = empty_BVHNode();
    //     temp.children[0] = ChildIndex(-1, obj_type, i, 0);
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
    for (int i = 0; i < running_length - 1; i++) {
        BVHNode node1 = BVH.list[i];
        if (node1.self != -2) {
            continue;
        }
        for (int j = i + 1; j < running_length; j++) {
            BVHNode node2 = BVH.list[j];
            // If node doesn't exist, continue
            if (node2.self != -2) {continue;}
            // If nodes don't intersect, continue
            if (!intersect_AABB(node1.bbox, node2.bbox)) {continue;}

            // if ()

        }
    }

}




// RAY-HIT FUNCTIONS
// =============


void set_rayhit(inout RayHit rayhit, float t, Ray ray, int object_type, int object_index) {
    rayhit.hit = true;
    rayhit.t = t;
    rayhit.ray = ray;
    rayhit.obj_type = object_type;
    rayhit.obj_index = object_index;
}

bool hit_AABB(Ray ray, AABB bbox, Range range) {
    // Returns true if ray hits aabb within given range
    for (int i = 0; i < 3; i++) {
        float inv_ray_x = 1. / ray.direction[i];
        float orig = ray.origin[i]; // This is an optimazation. Source: Trust me (real)
        float t0 = ((bbox.minimum[i] - orig) * inv_ray_x);
        float t1 = ((bbox.maximum[i] - orig) * inv_ray_x);

        // Make sure t0 is smallest
        if (inv_ray_x < 0.) {swap(t0, t1);}

        if (t0 > range.start) {range.start = t0;}
        if (t1 > range.end) {range.end = t1;}

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

RayHit hit_plane(Ray ray, Plane plane, Range t_range, inout RayHit rayhit) {
    
    // Early return if plane is paralell, even if the ray is contained in the plane
    // May not be needed
    // bool is_paralell = is_close(dot(ray.direction, plane.normal), 0.);
    // if (is_paralell) {
    //     return rayhit;
    // }

    float intersection_t = plane.d / dot(plane.normal, ray.origin + ray.direction);

    // Early return if t is not in range or further away than previous t
    if (!in_range(intersection_t, t_range) || intersection_t > rayhit.t) {
        return rayhit;
    }

    // Set rayhit variables
    set_rayhit(rayhit, intersection_t, ray, is_plane, 0); // 0 is TEMP as I only have one plane

    return rayhit;
}

RayHit determine_rayhit(inout RayHit rayhit) {
    // Resolves intersextion point, normal and other information from rayhit 
    rayhit.point = ray_at(rayhit.ray, rayhit.t);

    // Procedure for hitting sphere
    if (rayhit.obj_type == is_sphere) {
        Sphere sphere = spheres.data[rayhit.obj_index];
        rayhit.mtl_index = sphere.mtl_index;
        rayhit.normal = (rayhit.point - sphere.center) / sphere.radius;
        rayhit.color = vec4(mtls[rayhit.mtl_index].albedo, 1);
    
    // Procedure for hitting plane
    } else if (rayhit.obj_type == is_plane) {
        Plane plane = planes[rayhit.obj_index];
        rayhit.mtl_index = plane.mtl_index;
        rayhit.normal = plane.normal;
        rayhit.color = vec4(mtls[rayhit.mtl_index].albedo, 1);
    }

    rayhit.is_initialized = true;
    return rayhit;
}

RayHit check_ray_hit(Ray ray, Range range) {
    
    RayHit rayhit = empty_rayhit();
    hit_spheres(ray, range, rayhit);
    hit_plane(ray, plane, range, rayhit);

    // TODO ADD intersection with skybox, would still count as not hit
    if (!rayhit.hit) {
        rayhit.color = default_color;
    }

    return rayhit;
}


RayHit check_ray_hit_BVH(Ray ray, Range range) {
    // Like check_ray_hit but it checks against a BVH tree instead of each object_list individually
    RayHit rayhit = empty_rayhit();

    BVHNode root_node;
    

    // while (true) {

    // }


    // TODO ADD intersection with skybox, would still count as not hit
    if (!rayhit.hit) {
        rayhit.color = default_color;
    }

    return rayhit;
}

// RAY-BOUNCE FUNCTIONS
// ====================
Ray reflect_ray(Ray ray_in, RayHit rayhit) {
    // Returns a new reflected ray based on ray_in and rayhit
    vec3 reflected_dir = reflect(ray_in.direction, rayhit.normal);
    vec3 dir_offset = rand_vec3(rayhit.point) * (1. - mtls[rayhit.mtl_index].metallic);

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
    rayhit.is_inside = bool(dot(rayhit.normal, ray_in.direction) > 0.);
    float eta_in = current_IOR;
    float eta_out = (rayhit.is_inside) ? IOR_air : mtls[rayhit.mtl_index].IOR;
    float eta;
    
    // TODO fix support for refraction between different materials
    // eta = (rayhit.is_inside) ? eta_out / eta_in : eta_in / eta_out;
    if (!is_close(current_IOR, 1.)) {
        eta = (rayhit.is_inside) ? eta_out / eta_in : eta_in / eta_out;
    } else {
        eta = (rayhit.is_inside) ? rayhit.current_IOR / mtls[rayhit.mtl_index].IOR : 
        mtls[rayhit.mtl_index].IOR / rayhit.current_IOR;
    }
    eta = (rayhit.is_inside) ? eta_out / eta_in : eta_in / eta_out;
    eta = eta_out / eta_in;
    eta = (!rayhit.is_inside) ? 1. / mtls[rayhit.mtl_index].IOR : mtls[rayhit.mtl_index].IOR / 1.;
    // eta = current_IOR / eta_out;
    current_IOR = (rayhit.is_inside) ? mtls[rayhit.mtl_index].IOR : IOR_air;

    vec3 normalized_direction = normalize(ray_in.direction);
    vec3 normal = (rayhit.is_inside) ? -rayhit.normal : rayhit.normal;

    // Calculate whether angle is shallow enough to disallow refraction
    float cos_theta = min(dot(-normalized_direction, normal), 1.);
    float sin_theta = sqrt(1. - cos_theta * cos_theta);

    // Schlick's approximation for reflectivety
    float r0 = (1. - eta) / (1. + eta);
    r0 = r0 * r0;
    float reflect_chance = r0 + (1. - r0) * pow(1. - cos_theta, 5.);

    if (eta * sin_theta > 1. || reflect_chance > rand2(vec2(cos_theta, eta))) {
        rayhit.normal *= -1.;
        return reflect_ray(ray_in, rayhit);
    }

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

    if (mtls[rayhit.mtl_index].metallic > 0.) {
        return reflect_ray(ray_in, rayhit);
    }

    if (mtls[rayhit.mtl_index].opacity < 1.) {
        return refract_ray(ray_in, rayhit);
    }

    return scatter_ray(ray_in, rayhit);
}

// MAIN FUNCTIONS
// ==============
vec4 cast_ray(Ray ray, Range range) {
    // Casts a ray with bounces and returns the color of the ray

    vec4 out_col = default_color;

    // Rayhit's color should determined in reverse order, so we to store them for later
    RayHit rayhits[max_depth];

    // Calculate rayhits
    Ray new_ray = ray;
    RayHit prev_rayhit = empty_rayhit();
    RayHit rayhit;
    int i = 0;

    for (;i < max_depth; i++) {
        rayhit = check_ray_hit(new_ray, range);
        
        // Early break if no hit
        if (!rayhit.hit) {
            // Adds sky color as the last rayhit when miss
            rayhits[i] = rayhit;
            i++; // Breaking doesn't increment therefore we have to correct for it
            break;
        }

        determine_rayhit(rayhit);

        // if (!is_close(prev_rayhit.current_IOR, 1.)) {
        //     rayhit.color = vec4(1,0,0,1);
        // }
        // rayhit.current_IOR = prev_rayhit.current_IOR;
        new_ray = bounce_ray(new_ray, rayhit);
        
        rayhits[i] = rayhit;
        prev_rayhit = rayhit;     
    } 

    if (i == 0) {return out_col;} // Early return if no rays were hit

    i--; // Correct i to be last index of rayhits

    // Determine each ray color in reverse order
    vec4 new_color = rayhits[i].color;
    for (int j = i; j > 0; j--) {
        new_color = new_color * rayhits[j - 1].color; // temp
    }

    out_col = new_color;

    return out_col;
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
    const int image_index = int(UV.x + UV.y * width);

    // CODE
    // ====
    vec3 pixel_center = pixel00_loc + (UV.x * pixel_delta_u) + (UV.y * pixel_delta_v);

    vec4 new_color = vec4(0,0,0,1);
    float circle_step = 2 * pi / float(samples_per_pixel);
    for (int i = 0; i < samples_per_pixel; ++i) {
        float temp = fract(float(i) / float(samples_per_pixel)) ;
        vec3 circular_offset = pixel_delta_u / 2 * cos(float(i) * circle_step) * rand(temp) + 
                               pixel_delta_v / 2 * sin(float(i) * circle_step) * rand(temp);
        vec3 ray_direction = pixel_center - camera.pos + circular_offset;
        Ray ray = Ray(camera.pos, ray_direction);

        new_color += cast_ray(ray, Range(0.001, infinity));
    }
    new_color = new_color / samples_per_pixel;

    // new_color = vec4(1., 0.5, 0.25, 1.);
    float gammma_factor =  2.2;
    new_color.rgb = pow(new_color.rgb, vec3(gammma_factor, gammma_factor, gammma_factor));

    imageStore(output_image, UVi.xy, new_color);
}