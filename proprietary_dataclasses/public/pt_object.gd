@tool
class_name PTObject
extends MeshInstance3D

"""Base class for all visual objects"""

# TODO Add support for lines and add abilitiy to visualize traced rays
# TODO Add meshes
# TODO Add instancing only to meshes?

const EPSILON = 1e-6
const AABB_PADDING := Vector3(EPSILON, EPSILON, EPSILON)

# Tied to object_type enum in shader
enum ObjectType {
	NOT_OBJECT = 0,
	SPHERE = 1,
	PLANE = 2,
	TRIANGLE = 3,
	MESH = 4,
	MAX = 5
}

signal material_changed(
	object : PTObject,
	prev_material : PTMaterial,
	new_material : PTMaterial
)

signal texture_changed(
	object : PTObject,
	prev_texture : PTTexture,
	new_texture : PTTexture
)

@export var material : PTMaterial = null:
	set(value):
		# NOTE: If material is cleared (not reset) it returns <Object#null> instead
		#  of null, breaking the system. This will make sure it is just null.
		if not is_instance_valid(value):
			value = null

		var prev_value := material
		material = value
		emit_signal("material_changed", self, prev_value, material)
@export var texture : PTTexture:
	set(value):
		print("texture swapped")
		emit_signal("texture_changed", self, texture, value)
		texture = value

# The scene this object is part of
var _scene : PTScene

var transform_before : Transform3D


func _enter_tree() -> void:
	# Find scene when entering tree if scene is not set
	if not is_instance_valid(_scene):
		_scene = find_scene_ancestor()
		if _scene:
			_scene.add_object(self)

	transform_before = Transform3D(transform)
	set_notify_transform(true)


func _exit_tree() -> void:
	# NOTE: This is only for the user deleting objects in the editor scene tree.
	#  Otherwise, an object should explicitly be removed with a function call.
	if Engine.is_editor_hint():
		var selection := EditorInterface.get_selection()
		# This narrows down which objects are actually deleted vs. scene changed
		if self in selection.get_selected_nodes():
			_scene.queue_remove_object(self)
	#else:
		# I'm not sure if this is how runtime should be handled. Objects that the
		#  user wants removed should be explicitly told so. If the whole scene is
		#  removed and not deleted, we should do nothing. If the whole scene is
		#  removed and deleted, all child nodes and buffers should be deleted anyways.
		#  So no point in removing an object here.
		#_scene.queue_remove_object(self)


func _notification(what : int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			if _scene and transform != transform_before:
				_scene.update_object(self)
				transform_before = Transform3D(transform)


func _get_property_list() -> Array:
	# TODO Overriding previous classes export might be possible in godot 4.3
	var properties := []
	properties.append({
		"name": "mesh",
		"type": TYPE_RID,
		"usage": PROPERTY_USAGE_NO_EDITOR,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": "Don't change the mesh"
	})

	return properties


static func vector_to_array(vector : Vector3) -> Array[float]:
	return [vector.x, vector.y, vector.z]


static func aabb_to_byte_array(aabb : AABB) -> PackedByteArray:
	var new_aabb := aabb.abs()
	var arr := (vector_to_array(new_aabb.position - AABB_PADDING) + [0.0] +
			vector_to_array(new_aabb.end + AABB_PADDING) + [0.0])
	return PackedFloat32Array(arr).to_byte_array()


func find_scene_ancestor() -> PTScene:
	var max_depth : int = 20
	var counter : int = 0
	var current_node : Node = get_parent()
	while counter < max_depth and current_node:
		if current_node is PTScene:
			return (current_node as PTScene)
		counter += 1
		current_node = current_node.get_parent()

	return null


func get_type() -> ObjectType:
	"""Returns the PTObject sub type"""
	if self is PTSphere:
		return ObjectType.SPHERE
	elif self is PTPlane:
		return ObjectType.PLANE
	elif self is PTTriangle:
		return ObjectType.TRIANGLE
	else:
		return ObjectType.NOT_OBJECT


func get_global_aabb() -> AABB:
	"""Returns the objects aabb in world coordinates"""
	return global_transform * get_aabb()


func _get_property_byte_array() -> PackedByteArray:
	var floats : Array[int] = [
		_scene.get_material_index(material),
		_scene.get_texture_id(texture),
		0,
		0
	]

	return PackedInt32Array(floats).to_byte_array()


func to_byte_array() -> PackedByteArray:
	push_warning("No 'to_byte_array' function set for object " + str(self) + ". \
	A default function will be used instead.")
	return PackedInt32Array([0,0,0,0,0,0,0,0]).to_byte_array()

