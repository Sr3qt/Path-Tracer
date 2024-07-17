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
	for i in range(0, mesh_array[ArrayMesh.ARRAY_INDEX].size(), 3):
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
			_set_object_index(new_object_array[i], last_index + i) # UNSTATIC

		assert(get_object_array(type).size() == last_index + new_object_array.size())

	object_count += other.object_count
	return added_types


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


## Adds and removes objects given in the least computationally intensive way.
## Called by scene at maximum once a frame.
func _rebalance_objects(
		added_objects : PTObjectContainer,
		removed_objects : PTObjectContainer
	) -> Array[int]: # MIGHT HAVE RETURN VALUE LATER; CHANGED INDICES OR SMTHN

	# This is called only by a PTScene. We can assume all removed objects are in
	# this instance and all new objects are not in this object.
	# There is still a chance an object has been freed.

	var previous_size = size()
	var object_ids_to_update : Array[int] = []

	for mesh in removed_objects.meshes:
		meshes.erase(mesh)

	for mesh in added_objects.meshes:
		meshes.append(mesh)

	var index_sort := func(x : PTObject, y: PTObject) -> bool:
		return get_object_index(x) > get_object_index(y)

	# Remove objects
	for type : ObjectType in ObjectType.values(): # UNSTATIC
		if (type == ObjectType.NOT_OBJECT or type == ObjectType.MAX):
			continue

		if not added_objects.has_type(type) and not removed_objects.has_type(type):
			continue

		var object_array : Array = get_object_array(type)
		var new_object_array := added_objects.get_object_array(type)
		var removed_object_array := removed_objects.get_object_array(type)
		var new_object_index := new_object_array.size() - 1

		# Sorts objects according to descending index
		removed_object_array.sort_custom(index_sort)
		for object : PTObject in removed_object_array: # UNSTATIC
			var index := get_object_index(object)
			_object_to_object_index.erase(object)

			object_ids_to_update.append(PTObject.make_object_id(index, type))

			# Removed object is at the back of object_array
			if index == object_array.size() - 1:
				object_array.pop_back()
				object_count -= 1
				continue

			if not new_object_array.is_empty() and new_object_index >= 0:
				var new_object : PTObject = new_object_array[new_object_index] # UNSTATIC
				assert(is_instance_valid(new_object),
						"PT: Cannot add freed or null object to PTObjectContainer. " +
						str(new_object))
				object_array[index] = new_object # UNSTATIC
				_set_object_index(new_object, index)
				new_object_index -= 1
			else:
				# Object is removed in the middle of object_array and no new
				# object can take its place. Move the last index to fill in
				var last_object : PTObject = object_array.pop_back() # UNSTATIC
				object_ids_to_update.append(PTObject.make_object_id(object_array.size(), type))
				_set_object_index(last_object, index)
				object_array[index] = last_object
				object_count -= 1

		# If there are more objects added than removed, append them.
		if not new_object_array.is_empty() and new_object_index >= 0:
			if PTRendererAuto.is_debug:
				print("Adding excessive objects to object container")
			while new_object_index >= 0:
				var object : PTObject = new_object_array[new_object_index] # UNSTATIC
				_set_object_index(object, object_array.size())
				object_ids_to_update.append(PTObject.make_object_id(object_array.size(), type))
				object_array.append(object)

				object_count += 1
				new_object_index -= 1

	assert(previous_size + added_objects.size() - removed_objects.size() == count(),
			"PT: Number of objects in != number of objects out.")

	return object_ids_to_update
