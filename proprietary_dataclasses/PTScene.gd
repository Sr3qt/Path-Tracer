extends Node

"""THis class is to hold PTObjects, PTMaterials and PTBVH for a scene

It should be able to save and load from a file

It should interface well with with the rendering class, being able to easily swap
two scenes.

"""

class_name PTScene

# objects is a dictionary with OBJECT_TYPEs as keys. The values are arrays of
#  PTObjects
var objects

# materials should hold no duplicate materials
var materials : Array[PTMaterial]

var BVHTree : PTBVHTree

# Whether anything in the scene, objects, camera, either moved, got added or removed
var scene_changed := false

static var OBJECT_TYPE = PTObject.OBJECT_TYPE
# Enum of different possible BVH algorithms
enum BVH_TYPE {DEFAULT}

func _init(object_dict_, materials_):
	objects = object_dict_
	materials = materials_


# Only relevant for when the structure of the scene changes, 
#  i.e adding / removing objects
#func set_object_indices():
	#"""Sets every object's object index according to this scene's objects"""
#
#func set_material_index():
	#"""Sets every object's material index according to this scene's material list"""
	

#func add_object(object : PTObject):
	#var type =  

static func array2vec(a):
	return Vector3(a[0], a[1], a[2])


static func load_scene(path : String):
	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	
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
		
		var numbers = line.split_floats(" ", false).slice(1)
		if line.begins_with("mtl "):
			mtl_list.append(PTMaterial.new())
		
		if line.begins_with("sphere"):
			var center = array2vec(numbers.slice(0, 3))
			var material = mtl_list[int(numbers[4])]
			var sphere = PTSphere.new(center, numbers[3], material, 
			# Temp
			int(numbers[4]))
			
			sphere.object_index = sphere_list.size()
			sphere_list.append(sphere)
		
		elif line.begins_with("plane"):
			var normal = array2vec(numbers.slice(0, 3))
			var material = mtl_list[int(numbers[4])]
			var plane = PTPlane.new(normal, numbers[3], material, 
			# Temp
			int(numbers[4]))
			
			plane.object_index = plane_list.size()
			plane_list.append(plane)
	
	return PTScene.new(objects_dict, mtl_list)



func create_BVH(type : BVH_TYPE = BVH_TYPE.DEFAULT):
	match type:
		BVH_TYPE.DEFAULT:
			BVHTree = PTBVHTree.new()
			BVHTree.create_BVH_List(self)



