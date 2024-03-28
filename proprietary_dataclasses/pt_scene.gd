@tool
extends Node

"""THis class is to hold PTObjects, PTMaterials and PTBVH for a scene

It should be able to save and load from a file

It should interface well with with the rendering class, being able to easily swap
two scenes.

"""

class_name PTScene

# objects is a dictionary with OBJECT_TYPEs as keys. The values are arrays of
#  PTObjects 
# TODO make into a class?
var objects

@export_file var scene_import

# materials should hold no duplicate materials
var materials : Array[PTMaterial]

# A BVHTree object is required although it can be empty
var BVHTree : PTBVHTree

# Whether anything in the scene, objects, camera, either moved, got added or removed
var scene_changed := false

var camera : PTCamera

static var OBJECT_TYPE = PTObject.OBJECT_TYPE
# Enum of different possible BVH algorithms
enum BVH_TYPE {DEFAULT}

# Temp
enum camera_setting {top_down, corner, book_ex, center}
var camera_settings_values = {
	camera_setting.top_down : [Vector3(0, 8, -15), Vector3(0,0,-6), 106.],
	camera_setting.corner : [Vector3(-11, 3, -11), Vector3(0,0,0), 106.],
	camera_setting.book_ex : [Vector3(13, 2, 3), Vector3(0,0,0), 20 * 16 / 9.],
	camera_setting.center : [Vector3(0, 0, 1), Vector3(0,0,0), 106.]
}

func _init(
	object_dict_ = {}, 
	materials_ : Array[PTMaterial] = [], 
	camera_ : PTCamera = null
	):
	
	# Create objects dict if one was not passed
	if object_dict_:
		objects = object_dict_
	else:
		var sphere_list : Array[PTObject] = []
		var plane_list : Array[PTObject] = []
		objects = {
			OBJECT_TYPE.SPHERE : sphere_list,
			OBJECT_TYPE.PLANE : plane_list
		}
	
	materials = materials_
	
	camera = camera_
	
	# TODO should be removed
	BVHTree = PTBVHTree.new()

func _ready():
	if scene_import:
		import(scene_import)
	else:
		create_random_scene(0)
	
	if camera == null:
		for child in get_children():
			if child is PTCamera:
				camera = child
				break
	
	#if camera == null:
		#camera = PTCamera.new()
	
	if not Engine.is_editor_hint():
		set_camera_setting(camera_setting.center)
	else:
		set_camera_setting(camera_setting.corner)
	
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
	var out = _load_scene(path)
	
	return PTScene.new(out[0], out[1])
	

func import(path : String):
	var out = _load_scene(path)
	
	objects = out[0]
	materials = out[1]


static func _load_scene(path : String):
	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	
	var mtl_index = {}
	var mtl_list : Array[PTMaterial] = []
	var sphere_list : Array[PTObject] = []
	var plane_list : Array[PTObject] = []
	var objects_dict = {
		OBJECT_TYPE.SPHERE : sphere_list,
		OBJECT_TYPE.PLANE : plane_list
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


func create_BVH(max_children = 2, type : BVH_TYPE = BVH_TYPE.DEFAULT):
	match type:
		BVH_TYPE.DEFAULT:
			BVHTree = PTBVHTree.new(max_children)
			BVHTree.create_BVH(self)

func set_camera_setting(cam : camera_setting):
	if camera:
		var temp = camera_settings_values[cam]
		
		camera.camera_pos = temp[0]
		
		camera.look_at(temp[1])
		
		camera.hfov = temp[2]
		camera.set_viewport_size()
	else:
		# TODO make warning
		pass


func create_random_scene(seed):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	
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
			
			material.albedo = color
			var new_sphere = PTSphere.new(center, radius, material, 0)
			add_object(new_sphere)
	















