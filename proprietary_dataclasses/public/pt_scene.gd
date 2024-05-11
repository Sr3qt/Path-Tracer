@tool
class_name PTScene
extends Node

"""This class is to hold PTObjects, PTMaterials, PTCamera and PTBVH for a scene.

It's responsibility is to keep track of objects and materials, as well as any
changes to them or the BVH. The camera is self sufficient.

"""

# Enum for different custom 3D object types
const ObjectType = PTObject.ObjectType

# Semi-Temp
enum CameraSetting {none, top_down, corner, book_ex, center, left, right, middle}

var camera_settings_values = {
	CameraSetting.top_down : [Vector3(0, 8, -15), Vector3(0,0,-6), 106.],
	CameraSetting.corner : [Vector3(-11, 3, -11), Vector3(0,0,0), 106.],
	CameraSetting.book_ex : [Vector3(13, 2, 3), Vector3(0,0,0), 20 * 16 / 9.],
	CameraSetting.center : [Vector3(0, 0, 1), Vector3(0,0,0), 106.],
	CameraSetting.left : [Vector3(0, 0, 1), Vector3(-1,0,1), 106.],
	CameraSetting.right : [Vector3(0, 0, 1), Vector3(1,0,1), 106.],
	CameraSetting.middle : [Vector3(13, 2, 3), Vector3(0,0,0), 20 * 16 / 9.]
}

## Overrides starting camera values with predefined sets of values
@export var starting_camera := CameraSetting.none

@export var default_bvh := PTBVHTree.BVHType.X_SORTED

@export var create_random_scene_ := false:
	set(value):
		create_random_scene(0)
		print("Created random scene")

# Object lists
var spheres : Array[PTSphere]
var planes : Array[PTPlane]
var triangles : Array[PTTriangle]

# Simple dict to choose the right list
var objects = {
	ObjectType.SPHERE : spheres,
	ObjectType.PLANE : planes,
	ObjectType.TRIANGLE : triangles,
}

# materials should hold no duplicate materials
var materials : Array[PTMaterial]
# Inverse of materials
var material_to_index = {}

# Current BVH that would be used by the Renderer
var bvh : PTBVHTree
# Array of created and unused BVHs
var cached_bvhs : Array[PTBVHTree]

# Whether any objects either moved, got added or removed. 
#  Camera is controlled seperately
var scene_changed := false

var camera : PTCamera

var object_count : int = 0

var added_object := false # Whether an object (or material) was added this frame
var added_types = {
	ObjectType.NOT_OBJECT : false, # Interpreted as a material
	ObjectType.SPHERE : false,
	ObjectType.PLANE : false,
	ObjectType.TRIANGLE : false,
}


func _ready():
	# TODO GODOT seems to delete a gdscene's objects when that scene has not 
	#  been in use for a long time. This makes reloading that scene really 
	#  expensive (time consuming) for us. Fix
	if not Engine.is_editor_hint() or PTRendererAuto._is_plugin_hint:
		
		get_size()
		
		if camera == null:
			for child in get_children():
				if child is PTCamera:
					camera = child
					break
			pass
	
	if not Engine.is_editor_hint():
		if starting_camera != CameraSetting.none:
			set_camera_setting(starting_camera)
	
	# Scene will probably trigger this when objects add themselves to the scene
	added_object = false
	for key in added_types.keys():
		added_types[key] = false
	
	PTRendererAuto.add_scene(self)


# TODO Update material when its removed and a new one is added
func update_material(material):
	PTRendererAuto.update_material(self, material)
	
	scene_changed = true


func update_object(object : PTObject):
	## Called by an object when its properties changed
	# Send request to update bvh if object is in it
	if bvh and PTBVHTree.objects_to_include.has(object.get_type()):
		bvh.update_aabb(object)
	
	# Send request to update buffer
	PTRendererAuto.update_object(self, object)
	
	scene_changed = true


# TODO add method to remove object
# TODO Add and remove objects from bvh
func add_object(object : PTObject):
	"""Adds an object to """
	var type = object.get_type()
	object.object_index = objects[type].size()
	objects[type].append(object)
	
	if not object.get_parent():
		print("Added child")
		add_child(object)
		
		# TEMP seems dangerous to keep
		#object.owner = self
	
	# Increment counters
	object_count += 1
	
	added_object = true
	added_types[type] = true
	
	if not object.material and not Engine.is_editor_hint():
		object.material = PTMaterial.new()
	
	# Check for object reference in array
	var material_index = materials.find(object.material)
	if material_index == -1:
		# DEPRECATED check for equal properties
		# Add to list if not alreadt in it
		object.material_index = materials.size()
		material_to_index[object.material] = materials.size()
		materials.append(object.material)
		object.material.connect("material_changed", update_material)
		
		added_types[PTObject.ObjectType.NOT_OBJECT] = true
	else:
		object.material_index = material_index
		
	scene_changed = true
	


static func array2vec(a):
	return Vector3(a[0], a[1], a[2])


func get_size():
	"""Calculates the number of primitives stored in the scene"""
	object_count = 0
	
	for _objects in objects.values():
		object_count += _objects.size()
	
	return object_count


func create_BVH(max_children : int, function_name : String):
	# TODO add check to reuse BVH if it is in cached_bvhs
	
	if bvh:
		cached_bvhs.append(bvh)
	
	bvh = PTBVHTree.create_bvh_with_function_name(self, max_children, function_name)


func set_camera_setting(cam : CameraSetting):
	if camera:
		var temp = camera_settings_values[cam]
		
		camera.position = temp[0]
		
		camera.look_at(temp[1])
		
		camera.fov = temp[2] / camera.aspect_ratio
		camera.set_viewport_size()
	else:
		push_warning("PT: Cannot set camera settings when no camera has been attached \
to the scene")


func create_random_scene(_seed):
	var rng = RandomNumberGenerator.new()
	rng.seed = _seed
	
	# Ground
	var ground_mat = PTMaterial.new()
	ground_mat.albedo = Color(0.5, 0.5, 0.5)
	
	add_object(PTPlane.new(Vector3(0, 1, 0), -1., ground_mat, 0))
	#add_object(PTSphere.new(Vector3(0, -1000, 0), 1000, ground_mat, 0))
	
	# Glass
	var mat1 = PTMaterial.new()
	mat1.IOR = 1.5
	mat1.opacity = 0.
	add_object(PTSphere.new(Vector3(0, 1, 0), 1, mat1, 0))
	
	# Diffuse
	var mat2 = PTMaterial.new()
	mat2.albedo = Color(0.4, 0.2, 0.1)
	add_object(PTSphere.new(Vector3(-4, 1, 0), 1, mat2, 0))
	
	# Metallic
	var mat3 = PTMaterial.new()
	mat3.albedo = Color(0.7, 0.6, 0.5)
	mat3.metallic = 1.
	add_object(PTSphere.new(Vector3(4, 1, 0), 1, mat3, 0))
	
	for i in range(22):
		for j in range(22):
			var center = Vector3((i - 11) + 0.9 * rng.randf(),
								 0.2,
								 (j - 11) + 0.9 * rng.randf())
			var radius = 0.2
			
			var choose_material = rng.randf()
			var material = PTMaterial.new()
			
			var color = Color(rng.randf(), rng.randf(), rng.randf())
			
			if choose_material < 0.8:
				pass
			elif choose_material < 0.95:
				# Metal
				color = Color(rng.randf_range(0.5, 1.), 
								rng.randf_range(0.5, 1.),
								rng.randf_range(0.5, 1.))
				material.metallic = choose_material + 0.05
			else:
				# Glass
				color = Color(rng.randf_range(0.88, 1.), 
								rng.randf_range(0.88, 1.),
								rng.randf_range(0.88, 1.))
				material.opacity = 0.
				material.IOR = 1.6
			
			material.albedo = color
			var new_sphere = PTSphere.new(center, radius, material, 0)
			add_object(new_sphere)
	











