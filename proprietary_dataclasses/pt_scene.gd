@tool
class_name PTScene
extends Node

"""THis class is to hold PTObjects, PTMaterials and PTBVH for a scene

It should be able to save and load from a file

It should interface well with with the rendering class, being able to easily swap
two scenes.

"""

# Enum for different custom 3D object types
static var ObjectType = PTObject.ObjectType

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

@export_file var scene_import

## Overrides starting camera values with predefined sets of values
@export var starting_camera := CameraSetting.none

## Overrides scene_import, Seect one of the built-in scenes
@export_enum("none", "random_scene", "scene1", "scene2", "scene3") 
var starting_scene = "none"

# objects is a dictionary with ObjectTypes as keys. 
#  The values are arrays of PTObjects 
# TODO make into a class? or split into seperate arrays
var objects

# materials should hold no duplicate materials
var materials : Array[PTMaterial]

# Current BVH that would be used by the Renderer
var bvh : PTBVHTree
# Array of created and unused BVHs
var cached_bvhs : Array[PTBVHTree]

# Whether any objects either moved, got added or removed. 
#  Camera is controlled seperately
var scene_changed := false

var camera : PTCamera

var object_count : int = 0


func _init(
		_object_dict = {}, 
		_materials : Array[PTMaterial] = [], 
		_camera : PTCamera = null
	):
	
	# Create objects dict if one was not passed
	if _object_dict:
		objects = _object_dict
		get_size()
	else:
		var sphere_list : Array[PTObject] = []
		var plane_list : Array[PTObject] = []
		objects = {
			ObjectType.SPHERE : sphere_list,
			ObjectType.PLANE : plane_list
		}
	
	materials = _materials
	
	camera = _camera


func _ready():
	# Create default random scene if no imports
	if not Engine.is_editor_hint():
		if starting_scene == "none":
			if scene_import:
				import(scene_import)
			# If starting scene is none and no scene_import given
		elif starting_scene == "random_scene":
			create_random_scene(0)
		else:
			var path = "res://main/sphere_" + starting_scene + ".txt"
			import(path)
			
	if not Engine.is_editor_hint() or get_parent()._is_plugin_hint:
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
	elif get_parent()._is_plugin_hint:
		set_camera_setting(CameraSetting.book_ex)
		create_random_scene(0)
	
# Only relevant for when the structure of the scene changes, 
#  i.e adding / removing objects
#func set_object_indices():
	#"""Sets every object's object index according to this scene's objects"""
#
#func set_material_index():
	#"""Sets every object's material index according to this scene's material list"""
	

func add_object(object : PTObject):
	"""Adds an object to """
	var type = object.get_type()
	object.object_index = objects[type].size()
	objects[type].append(object)
	
	object_count += 1
	
	# TODO: Add hash function to material, and make dict or
	#  Make a global material index that keeps track of all material instances
	# First check for object reference in array
	var material_index = materials.find(object.material)
	if material_index == -1:
		# Second check for equal properties in array
		material_index = object.material.find_in_array(materials)
		if material_index == -1:
			# Add to list
			object.material_index = materials.size()
			materials.append(object.material)
		else:
			object.material_index = material_index
	else:
		object.material_index = material_index
		
		
	scene_changed = true


static func array2vec(a):
	return Vector3(a[0], a[1], a[2])


static func load_scene(path : String):
	""" Returns new scene with data from file """
	var out = _load_scene(path)
	
	return PTScene.new(out[0], out[1])
	

func import(path : String):
	""" Replaces this scenes data with data from file """
	var out = PTScene._load_scene(path)
	
	objects = out[0]
	materials = out[1]
	
	scene_changed = true


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
	ground_mat.albedo = Vector3(0.5, 0.5, 0.5)
	
	add_object(PTPlane.new(Vector3(0, 1, 0), -1., ground_mat, 0))
	#add_object(PTSphere.new(Vector3(0, -1000, 0), 1000, ground_mat, 0))
	
	# Glass
	var mat1 = PTMaterial.new()
	mat1.IOR = 1.5
	mat1.opacity = 0.
	add_object(PTSphere.new(Vector3(0, 1, 0), 1, mat1, 0))
	
	# Diffuse
	var mat2 = PTMaterial.new()
	mat2.albedo = Vector3(0.4, 0.2, 0.1)
	add_object(PTSphere.new(Vector3(-4, 1, 0), 1, mat2, 0))
	
	# Metallic
	var mat3 = PTMaterial.new()
	mat3.albedo = Vector3(0.7, 0.6, 0.5)
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
			
			var color = Vector3(rng.randf(), rng.randf(), rng.randf())
			
			if choose_material < 0.8:
				pass
			elif choose_material < 0.95:
				# Metal
				color = Vector3(rng.randf_range(0.5, 1.), 
								rng.randf_range(0.5, 1.),
								rng.randf_range(0.5, 1.))
				material.metallic = choose_material + 0.05
			else:
				# Glass
				color = Vector3(rng.randf_range(0.88, 1.), 
								rng.randf_range(0.88, 1.),
								rng.randf_range(0.88, 1.))
				material.opacity = 0.
				material.IOR = 1.6
			
			material.albedo = color
			var new_sphere = PTSphere.new(center, radius, material, 0)
			add_object(new_sphere)
	

static func _load_scene(path : String):
	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	
	var mtl_index = {}
	var mtl_list : Array[PTMaterial] = []
	var sphere_list : Array[PTObject] = []
	var plane_list : Array[PTObject] = []
	var objects_dict = {
		ObjectType.SPHERE : sphere_list,
		ObjectType.PLANE : plane_list
	}
	for line in text.split("\n", false):
		if line.begins_with("#"):
			continue
		
		if line.begins_with("mtl "):
			var values = line.split(" ", false)
			var material = PTMaterial.new()
			material.albedo = Vector3(float(values[2]), 
									  float(values[3]), 
									  float(values[4]))
			material.roughness = float(values[5])
			material.metallic = float(values[6])
			material.opacity = float(values[7])
			material.IOR = float(values[8])
			material.refraction_depth = int(values[9])
			
			mtl_index[values[1]] = mtl_list.size()
			mtl_list.append(material)
		
		if line.begins_with("sphere"):
			var numbers = line.split_floats(" ", false).slice(1)
			var center = array2vec(numbers.slice(0, 3))
			var material_index = mtl_index[line.split(" ", false)[-1]]
			var material = mtl_list[material_index]
			var sphere = PTSphere.new(center, numbers[3], material, material_index)
			
			sphere.object_index = sphere_list.size()
			sphere_list.append(sphere)
		
		elif line.begins_with("plane"):
			var numbers = line.split_floats(" ", false).slice(1)
			var normal = array2vec(numbers.slice(0, 3))
			var material_index = mtl_index[line.split(" ", false)[-1]]
			var material = mtl_list[material_index]
			var plane = PTPlane.new(normal, numbers[3], material, material_index)
			
			plane.object_index = plane_list.size()
			plane_list.append(plane)
	
	return [objects_dict, mtl_list]















