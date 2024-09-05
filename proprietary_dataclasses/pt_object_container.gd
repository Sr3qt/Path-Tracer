@tool
class_name PTObjectContainer
extends RefCounted

## Class to hold PTObjects and meshes
##
## Policy: A PTOC cannot hold objects that are inside of one of the meshes it holds.
## It can still hold meshlets, however the mesh cannot also be present.
## A PTMesh cannot be inside its own container.
## Additionally it can hold no duplicate objects with the same reference.

# Enum for different custom 3D object types
const ObjectType = PTObject.ObjectType

## So far only three classes are allowed to hold PTOC: PTScene, PTBVHTree and PTMesh.
var owner : Variant:
	set(value):
		assert((value is PTScene or value is PTBVHTree or value is PTMesh or value == null))
		owner = value

var meshes : Array[PTMesh]

# Object lists
# NOTE: Don't know if arrays should be PTObject for easier typing with get_obejct_array
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
	assert(type != ObjectType.NOT_OBJECT,
			"PT: Array for ObjectType: 'NOT_OBJECT' does not exist.")
	assert(type != ObjectType.MAX,
			"PT: Array for ObjectType: 'MAX' does not exist")

	match type:
		ObjectType.SPHERE:
			return spheres
		ObjectType.PLANE:
			return planes
		ObjectType.TRIANGLE:
			return triangles

	push_error("PT: PTMesh.get_object_array with argument: ", type, ", is not supported.")
	return []


## Recount every object, return the number of objects and meshes
func count() -> int:
	object_count = 0
	for object_array : Array in get_object_lists(): # UNSTATIC
		object_count += object_array.size()
	return object_count + meshes.size()


## Return current object_count
func size() -> int:
	return object_count + meshes.size()


func is_empty() -> bool:
	return object_count == 0 and meshes.size() == 0


func clear() -> void:
	meshes.clear()
	for object_array : Array in get_object_lists(): # UNSTATIC
		object_array.clear()
	_object_to_object_index.clear()
	object_count = 0


## Similar to clear, but also immidietaly frees all objects and meshes
func clean() -> void:
	for mesh in meshes:
		mesh.free()
	meshes.clear()
	for object_array : Array in get_object_lists(): # UNSTATIC
		for object : PTObject in object_array:
			object.free()
		object_array.clear()
	_object_to_object_index.clear()
	object_count = 0


func has(object : PTObject) -> bool:
	return get_object_array(object.get_type()).has(object)


## Returns whether the given type has a non-empty field
func has_type(type : ObjectType) -> bool:
	return get_object_array(type).size() != 0


func get_object_lists() -> Array:
	return objects.values()


func get_object_index(object : PTObject) -> int:
	return _object_to_object_index[object] # UNSTATIC


func _set_object_index(object : PTObject, index : int) -> void:
	_object_to_object_index[object] = index # UNSTATIC


func get_mesh_index(mesh : PTMesh) -> int:
	return meshes.find(mesh)


func add_object(object : PTObject) -> void:
	var type := object.get_type()
	var object_array : Array = get_object_array(type)
	_set_object_index(object, object_array.size())
	object_array.append(object)

	object_count += 1


func remove_object(object : PTObject) -> void:
	assert(object in _object_to_object_index,
			"Object already removed from container")
	var type := object.get_type()
	var object_array : Array = get_object_array(type)
	var index : int = get_object_index(object)
	object_array.remove_at(index)
	_object_to_object_index.erase(object)

	# TODO Moving last object to removed index might be fine, in which case i also
	# need to update one bvhnode
	# Re-index every object
	for i in range(object_array.size()):
		@warning_ignore("unsafe_cast")
		_set_object_index(object_array[i] as PTObject, i) # UNSTATIC

	object_count -= 1


func add_mesh(mesh : PTMesh) -> void:
	meshes.append(mesh)


func remove_mesh(mesh : PTMesh) -> void:
	meshes.erase(mesh)


func mesh_to_pttriangles(f_mesh : Mesh) -> Array[PTTriangle]:

	var new_traingles : Array[PTTriangle] = []
	#var surface_mesh = ArrayMesh.new()
	#surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, f_mesh.surface_get_arrays(0))
	var mesh_array := f_mesh.surface_get_arrays(0)

	@warning_ignore("unsafe_method_access")
	var index_count : int = mesh_array[ArrayMesh.ARRAY_INDEX].size()
	for i in range(0, index_count, 3):
		var index1 : int = mesh_array[ArrayMesh.ARRAY_INDEX][i]
		var index2 : int = mesh_array[ArrayMesh.ARRAY_INDEX][i + 1]
		var index3 : int = mesh_array[ArrayMesh.ARRAY_INDEX][i + 2]

		var vertices : PackedVector3Array = mesh_array[ArrayMesh.ARRAY_VERTEX]
		var new_tri := PTTriangle.new(vertices[index1], vertices[index2], vertices[index3])

		if mesh_array[ArrayMesh.ARRAY_TEX_UV] != null:
			var uvs : PackedVector2Array = mesh_array[ArrayMesh.ARRAY_TEX_UV]
			new_tri.set_uvs(uvs[index1], uvs[index2], uvs[index3])

		new_traingles.append(new_tri)

	return new_traingles


## Add another PTObjectContainer's objects to this object
## Returns a bool array, indexed by ObjectType, of which objects were added.
func merge(other : PTObjectContainer) -> Array[bool]:
	meshes.append_array(other.meshes)
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
			@warning_ignore("unsafe_call_argument")
			_set_object_index(new_object_array[i], last_index + i) # UNSTATIC

		assert(get_object_array(type).size() == last_index + new_object_array.size())

	object_count += other.object_count
	return added_types


# TODO Move to test_helper_object_contianer
## Checks if any object is a part of any mesh.
func check_no_object_is_meshlet() -> bool:
	for type : ObjectType in ObjectType.values():
		if (type == ObjectType.NOT_OBJECT or type == ObjectType.MAX):
			continue
		for object : PTObject in self.get_object_array(type):
			if object.is_meshlet:
				return false
	return true


## Checks if any objects are being shared by other container
func check_no_object_shared_with_container(other : PTObjectContainer) -> bool:
	for mesh in self.meshes:
		if mesh in other.meshes:
			return true
	for type : ObjectType in ObjectType.values():
		if (type == ObjectType.NOT_OBJECT or type == ObjectType.MAX):
			continue
		var object_array := other.get_object_array(type)
		for object : PTObject in self.get_object_array(type):
			if object in object_array:
				return false
	return true


## Check if all objects in this container is also in other
func check_all_objects_shared_with_container(other : PTObjectContainer) -> bool:
	for type : ObjectType in ObjectType.values():
		if (type == ObjectType.NOT_OBJECT or type == ObjectType.MAX):
			continue
		var object_array := other.get_object_array(type)
		for object : PTObject in self.get_object_array(type):
			if not object in object_array:
				return false
	return true
