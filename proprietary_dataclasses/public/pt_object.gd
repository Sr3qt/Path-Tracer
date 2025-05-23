@tool
class_name PTObject
extends MeshInstance3D

## Base class for all visual objects

# TODO 2: Optimize by making PTObject inherit Node3D and spawning meshinstance in editor

# TODO 3: Add support for lines and add abilitiy to visualize traced rays

# TODO 1: Remove primitive nodes, make all PTObjects hold a PTPrimitive resource which is just data.
# PTObjectContainers can hold PTObjects and PTPtimitives. The primitves are what is loaded into buffers.
# This way you can programatically instantiate many primitives without node overhang as well as meshes are better.


const EPSILON = 1e-6
const AABB_PADDING := Vector3(EPSILON, EPSILON, EPSILON)

## Number of bits spared for object type in object_id. DON'T CHANGE
const OBJECT_TYPE_NUM_BITS = 8

## How many nodes will be checked when searching for an ancestor
const MAX_SEARCH_DEPTH = 30

# NOTE: This is helpful list of places to update when you add a new object type
#	- This enum obviously
#	- Remember to update type_of here and add a get_type function to the new object
#	- PTObjectContainer, variables and methods
#	- PTWorkDispatcher, create_buffers needs a create_[object]_buffer also
#		expand_object_buffer needs an entry
#	- PTBVHTree needs the object_type in its objects_to_exclude list if the object
#		has an undefined bounding box
# Tied to object_type enum in shader
enum ObjectType {
	NOT_OBJECT = 0,
	SPHERE = 1,
	PLANE = 2,
	TRIANGLE = 3,
	MAX = 4
}

signal object_changed(object : PTObject)

signal deleted(object : PTObject)

signal material_changed(
	object : PTObject,
	prev_material : PTMaterial,
	new_material : PTMaterial
)

signal texture_changed(
	object : PTObject,
	prev_texture : PTTextureAbstract,
	new_texture : PTTextureAbstract
)

@export var material : PTMaterial = null:
	set(value):
		# NOTE: If material is cleared (not reset) it returns <Object#null> instead
		#  of null, breaking the system. This will make sure it is just null.
		if not is_instance_valid(value):
			value = null

		var prev_value := material
		material = value
		material_changed.emit(self, prev_value, material)
@export var texture : PTTextureAbstract:
	set(value):
		print("texture swapped")
		texture_changed.emit(self, texture, value)
		texture = value

# The scene this object is part of.
var _scene : PTScene
## NOTE: If object has _mesh, then _mesh owns object, else _scene owns obejct
var _mesh : PTMesh

## Whether this object is a part of a mesh
var is_meshlet : bool:
	get:
		return is_instance_valid(_mesh)

var transform_before : Transform3D

# TODO 3: Make test to ensure an object has implemented all necessary functions

func _enter_tree() -> void:
	# Find scene when entering tree if scene is not set
	if not is_instance_valid(_scene) and not is_instance_valid(_mesh):
		var temp := PTObject.find_scene_or_mesh_ancestor(self)
		_scene = temp[0] # UNSTATIC
		_mesh = temp[1] # UNSTATIC
		if _scene:
			if _scene.is_node_ready():
				#_scene.queue_add_object(self)
				#if PTRendererAuto.is_debug:
					#print("Object queue adds itself to scene. object: ", self, " ", _scene)
				_scene.add_object(self)
			else:
				_scene.add_object(self)
				#_scene.queue_add_object(self)
		if _mesh:
			#if PTRendererAuto.is_debug and _mesh.is_node_ready():
				#print("Object adds itself to mesh. object: ", self, " ", _mesh)
			_mesh.add_object(self)

	# TODO 3: Only objects withouth a mesh needs this
	if not is_meshlet:
		transform_before = Transform3D(global_transform)
		set_notify_transform(true)
		set_notify_local_transform(false)
	else:
		transform_before = Transform3D(transform)
		set_notify_transform(false)
		set_notify_local_transform(true)


func _exit_tree() -> void:
	# NOTE: This is only for the user deleting objects in the editor scene tree.
	#  Otherwise, an object should explicitly be removed with a function call.
	if Engine.is_editor_hint():
		var selection := EditorInterface.get_selection()
		# This narrows down which objects are actually deleted vs. scene changed
		if self in selection.get_selected_nodes():
			if PTRendererAuto.is_debug:
				print("Object queued for deletion. ", self)
			deleted.emit(self)


func _notification(what : int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			if _scene and global_transform != transform_before:
				object_changed.emit(self)
				transform_before = Transform3D(global_transform)

		NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
			if _scene and transform != transform_before:
				object_changed.emit(self)
				transform_before = Transform3D(transform)


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_NONE


static func get_object_byte_size() -> int:
	return 0


static func find_scene_ancestor(start_node : Node) -> PTScene:
	var counter : int = 0
	var current_node : Node = start_node.get_parent()
	while counter < MAX_SEARCH_DEPTH and current_node:
		if current_node is PTScene:
			return (current_node as PTScene)
		counter += 1
		current_node = current_node.get_parent()

	return null


## Returns mesh or scene ancestor, whichever is found first.
## The first item of the returned array is PTScene or null, and
## the second is PTMesh or null. Can return both as null.
static func find_scene_or_mesh_ancestor(start_node : Node) -> Array:
	var counter : int = 0
	var current_node : Node = start_node.get_parent()
	while counter < MAX_SEARCH_DEPTH and current_node:
		if current_node is PTScene:
			return [(current_node as PTScene), null]
		if current_node is PTMesh:
			return [null, (current_node as PTMesh)]
		counter += 1
		current_node = current_node.get_parent()

	return [null, null]


## Turn an array of bools indexed by ObjectType, into an array of ObjectType
static func bool_to_object_type_array(booleans : Array[bool]) -> Array[ObjectType]:
	var buffers : Array[ObjectType] = []
	for type : int in ObjectType.values(): # UNSTATIC
		if type == ObjectType.NOT_OBJECT or type == ObjectType.MAX:
			continue

		if booleans[type]:
			buffers.append(type)
	return buffers


## Based on an index ana an object type, create the object_id that would be used by the shader
static func make_object_id(index : int, type : ObjectType) -> int:
	return index + (type << (32 - OBJECT_TYPE_NUM_BITS))


static func get_object_type_from_id(object_id : int) -> ObjectType:
	return object_id >> (32 - OBJECT_TYPE_NUM_BITS) as ObjectType


static func get_object_index_from_id(object_id : int) -> int:
	var int_limit := 2147483647
	return (int_limit >> OBJECT_TYPE_NUM_BITS) & object_id


## Get ObjectType of Variant, can return NOT_OBJECT
static func type_of(object : Variant) -> ObjectType:
	if object is PTSphere:
		return ObjectType.SPHERE
	elif object is PTPlane:
		return ObjectType.PLANE
	elif object is PTTriangle:
		return ObjectType.TRIANGLE
	else:
		return ObjectType.NOT_OBJECT


static func empty_object_bytes(type : ObjectType) -> PackedByteArray:
	match type:
		ObjectType.SPHERE:
			return PTUtils.empty_byte_array(PTSphere.get_object_byte_size())
		ObjectType.PLANE:
			return PTUtils.empty_byte_array(PTPlane.get_object_byte_size())
		ObjectType.TRIANGLE:
			return PTUtils.empty_byte_array(PTTriangle.get_object_byte_size())
		_:
			push_error("PT: Object type does not support 'empty_object_bytes' ",
					"static function in PTObject.")

	return PackedByteArray([])


func has_scene() -> bool:
	return _scene != null and is_instance_valid(_scene)


func get_object_id() -> int:
	assert(has_scene(), "cannot get object_id of object without valid scene.")
	return PTObject.make_object_id(_scene.get_object_index(self), get_type())


## Every PTObject defines this function with their own ObjectType.
## PTObject returns MAX.
func get_type() -> ObjectType:
	return ObjectType.MAX


func get_type_name() -> String:
	return ObjectType.find_key(get_type())


## NOTE: This was planned as a feature for objects with potential to be added to
## a BVH. As of now there is not intention of implementing that idea
func has_aabb() -> bool:
	return true


func _get_aabb() -> AABB:
	return get_aabb()

## Returns the objects aabb in world coordinates
func get_global_aabb() -> AABB:
	return global_transform * _get_aabb()


## Return the aabb used by the BVH
func get_bvh_aabb() -> AABB:
	if is_meshlet:
		return transform * _get_aabb()
	return global_transform * _get_aabb()


func _get_property_byte_array() -> PackedByteArray:
	var actual_material := material
	if is_meshlet and _mesh.override_material:
		actual_material = _mesh.override_material
	elif is_meshlet and _mesh.default_material and not material:
		actual_material = _mesh.default_material

	var ints : Array[int] = [
		_scene.get_material_index(actual_material),
		_scene.get_texture_id(texture),
		0,
		0
	]

	return PackedInt32Array(ints).to_byte_array()


func to_byte_array() -> PackedByteArray:
	push_error("No 'to_byte_array' function set for object " + str(self) + ". \
	A default function will be used instead.")
	return PackedInt32Array([0,0,0,0,0,0,0,0]).to_byte_array()
