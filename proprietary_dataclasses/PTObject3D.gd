extends Node

# Base class for all visual objects
class_name PTObject

var material : PTMaterial
var aabb : PTAABB


# The scene this object is part of
var _scene : PTScene
# Indices relevant to _scene
var object_index : int
var material_index : int

# Tied to object_type enum in shader
enum OBJECT_TYPE {NOT_OBJECT = 0, SPHERE = 1, PLANE = 2, MESH = 3}


func get_material() -> PTMaterial:
	"""Returns the material of the object if it has one"""
	if material:
		return material
	if _scene:
		return _scene.materials[material_index]
	return null

static func get_obj_type(object):
	"""Returns the relevant enum for given object"""
	if object is PTSphere:
		return OBJECT_TYPE.SPHERE
	else:
		return OBJECT_TYPE.NOT_OBJECT
	
