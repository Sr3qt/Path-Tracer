@tool
class_name PTObjectContainer
extends RefCounted

## Class to hold PTObjects

# Enum for different custom 3D object types
const ObjectType = PTObject.ObjectType

var meshes : Array[PTMesh]

# Object lists
var spheres : Array[PTSphere]
var planes : Array[PTPlane]
var triangles : Array[PTTriangle]

var object_count : int = 0

# Simple dict to help choose the right list
var objects := {
	ObjectType.SPHERE : spheres,
	ObjectType.PLANE : planes,
	ObjectType.TRIANGLE : triangles,
}

var _object_to_object_index := {}


func get_object_array(type : ObjectType) -> Array:
	match type:
		ObjectType.NOT_OBJECT:
			push_warning("PT: Array for ObjectType: 'NOT_OBJECT' does not exist.")
			return []
		ObjectType.SPHERE:
			return spheres
		ObjectType.PLANE:
			return planes
		ObjectType.TRIANGLE:
			return triangles
		ObjectType.MAX:
			push_warning("PT: Array for ObjectType: 'MAX' does not exist")
			return []

	push_error("PT: PTMesh.get_object_array with argument: ", type, ", is not supported.")
	return []


func get_object_lists() -> Array:
	return objects.values()


func get_object_index(object : PTObject) -> int:
	return _object_to_object_index[object] # UNSTATIC


## Returns whether the given type has a non-empty field
func has_type(type : ObjectType) -> bool:
	return get_object_array(type).size() != 0


# Complete
func add_object(object : PTObject) -> void:
	var type := object.get_type()
	var object_array : Array = get_object_array(type)
	_object_to_object_index[object] = object_array.size() # UNSTATIC
	object_array.append(object)

	object_count += 1


# Complete
func remove_object(object : PTObject) -> void:
	var type := object.get_type()
	var object_array : Array = get_object_array(type)
	var index : int = _object_to_object_index[object] # UNSTATIC
	object_array.remove_at(index)
	_object_to_object_index.erase(object)

	# TODO Moving last object to removed index might be fine
	# Re-index every object
	for i in range(object_array.size()):
		_object_to_object_index[object_array[i]] = i # UNSTATIC

	object_count -= 1


func add_mesh(mesh : PTMesh) -> void:
	meshes.append(mesh)


func remove_mesh(mesh : PTMesh) -> void:
	meshes.erase(mesh)


## Add other PTObjectContainers objects to this object
## Returns a bool array, indexed by ObjectType, of which objects were added.
func merge(other : PTObjectContainer) -> Array[bool]:
	var added_types : Array[bool] = []
	added_types.resize(ObjectType.MAX)
	added_types.fill(false)
	for type : int in ObjectType.values(): # UNSTATIC
		if (type == ObjectType.NOT_OBJECT or type == ObjectType.MAX):
			continue

		if not other.has_type(type):
			continue

		var object_array := get_object_array(type)
		var new_object_array := other.get_object_array(type)
		var last_index := object_array.size()
		object_array.append_array(new_object_array)
		added_types[type] = true

		for i in range(new_object_array.size()):
			_object_to_object_index[new_object_array[i]] = last_index + i # UNSTATIC

		assert(get_object_array(type).size() == last_index + new_object_array.size())

	return added_types
