@tool
class_name PTObject
extends MeshInstance3D

"""Base class for all visual objects"""

# TODO Add support for lines and add abilitiy to visualize traced rays

# Tied to object_type enum in shader
enum ObjectType {NOT_OBJECT = 0, SPHERE = 1, PLANE = 2, MESH = 3}

@export var material : PTMaterial

# Indices relevant to _scene
var object_index : int
var material_index : int

# The scene this object is part of
var _scene : PTScene


func _enter_tree():
	# Find scene when entering tree if scene is not set
	if not _scene:
		var parent = get_parent()
		if parent is PTScene:
			_scene = parent
			parent.add_object(self)


func _get_property_list():
	# TODO Overriding previous classes export might be possible in godot 4.3
	var properties = []
	properties.append({
		"name": "mesh",
		"type": TYPE_RID,
		"usage": PROPERTY_USAGE_NO_EDITOR,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": "Don't change the mesh"
	})
	
	return properties
	

static func vector_to_array(vector : Vector3):
	return [vector.x, vector.y, vector.z]


static func aabb_to_byte_array(aabb : AABB) -> PackedByteArray:
	var new_aabb = aabb.abs()
	var arr = vector_to_array(aabb.position) + [0] + vector_to_array(aabb.end) + [0]
	return PackedFloat32Array(arr).to_byte_array()


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


func get_global_aabb():
	"""Returns the objects aabb in world coordinates"""
	return global_transform * get_aabb()

