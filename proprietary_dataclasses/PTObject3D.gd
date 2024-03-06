extends Node

# Base class for all visual objects
class_name PTObject

var material : PTMaterial
var material_index : int
var aabb : PTAABB

# Tied to object_type enum in shader
enum OBJECT_TYPE {NOT_OBJECT = 0, SPHERE = 1, PLANE = 2, MESH = 3}

static func array2vec(a):
	return Vector3(a[0], a[1], a[2])

static func read_PTobject_file(path : String):
	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	
	var mtl_list = []
	var sphere_list = []
	var temp = OBJECT_TYPE.SPHERE
	var objects = {temp : sphere_list}
	for line in text.split("\n", false):
		if line.begins_with("#"):
			continue
		
		var numbers = line.split_floats(" ", false).slice(1)
		if line.begins_with("mtl "):
			mtl_list.append(PTMaterial.new())
		
		if line.begins_with("sphere"):
			var center = array2vec(numbers.slice(0, 3))
			sphere_list.append(PTSphere.new(center, numbers[3], mtl_list[int(numbers[4])], 
			# Temp
			int(numbers[4])))
	
	return [mtl_list, objects]
	
