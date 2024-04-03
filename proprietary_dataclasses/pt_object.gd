class_name PTObject
extends Node
# Can potentially be Refcounted

"""Base class for all visual objects"""

# Tied to object_type enum in shader
enum ObjectType {NOT_OBJECT = 0, SPHERE = 1, PLANE = 2, MESH = 3}

var material : PTMaterial
var aabb : PTAABB

# Indices relevant to _scene
var object_index : int
var material_index : int

# The scene this object is part of
var _scene : PTScene

static func vec2array(vector : Vector3):
	return [vector.x, vector.y, vector.z]


func get_material() -> PTMaterial:
	"""Returns the material of the object if it has one"""
	if material:
		return material
	if _scene:
		return _scene.materials[material_index]
	return null


func get_type():
	"""Returns the PTObject sub type"""
	if self is PTSphere:
		return ObjectType.SPHERE
	elif self is PTPlane:
		return ObjectType.PLANE
	else:
		return ObjectType.NOT_OBJECT
