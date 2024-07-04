@tool
class_name PTMesh
extends Node3D

## A simple class to hold PTObjects

@export var bvh_type := PTBVHTree.BVHType.X_SORTED
@export var bvh_order : int = 8
@export var group_mesh_instance := true

@export_group("Overrides")
@export var defualt_material : PTMaterial
@export var override_material : PTMaterial

signal transform_changed(mesh : PTMesh)

signal deleted(mesh : PTMesh)

var objects : PTObjectContainer

var bvh : PTBVHTree

# The scene this object is part of. This object might also be a part of a mesh.
var _scene : PTScene
var _mesh : PTMesh

#var surface_mesh : ArrayMesh
var mesh : Mesh

var transform_before : Transform3D

# TODO Be able to see and edit meshes while they are instatiated

# TODO Add mesh defualt material and texture, objects withouth any will use mesh's


func _init() -> void:
	objects = PTObjectContainer.new()


func _enter_tree() -> void:
	# Find scene or mesh when entering tree if scene is not set
	if not is_instance_valid(_scene) :
		var temp := PTObject.find_scene_or_mesh_ancestor(self)
		_mesh = temp[1] # UNSTATIC
		if is_instance_valid(_mesh):
			_scene = _mesh._scene
		else:
			_scene = temp[0] # UNSTATIC

	transform_before = Transform3D(transform)
	set_notify_transform(true)


func _exit_tree() -> void:
	# NOTE: This is only for the user deleting objects in the editor scene tree.
	#  Otherwise, an object should explicitly be removed with a function call.
	if Engine.is_editor_hint():
		var selection := EditorInterface.get_selection()
		# This narrows down which objects are actually deleted vs. scene changed
		if self in selection.get_selected_nodes():
			if PTRendererAuto.is_debug:
				print("Mesh queued for deletion. ", self)
			deleted.emit(self)


func _ready() -> void:

	# Find imported mesh, if it exists
	var skeleton = get_node_or_null("Armature/Skeleton3D")
	print("looking for bones")
	if skeleton:
		print("found skelton")
		var temp : MeshInstance3D = skeleton.get_child(0)
		mesh = temp.mesh

		#for triangle in objects.mesh_to_pttriangles(mesh):
			#_scene.add_child.call_deferred(triangle)

	var function_name : String = PTBVHTree.enum_to_dict[bvh_type] # UNSTATIC
	bvh = PTBVHTree.create_bvh_with_function_name(objects, bvh_order, function_name)

	if _mesh:
		if PTRendererAuto.is_debug:
			print("Mesh adds itself to other mesh. mesh: ", self, " other: ", _mesh)
		_mesh.add_mesh(self)
	elif _scene:
		if PTRendererAuto.is_debug:
			print("Mesh adds itself to scene. mesh: ", self, " ", _scene)
		_scene.add_mesh(self)


func _notification(what : int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			if _scene and transform != transform_before:
				transform_changed.emit(self)
				transform_before = Transform3D(transform)


func add_mesh(mesh : PTMesh) -> void:
	# TODO Decide if mesh bvhs are merged first before being merged to scene bvh
	# NOTE: DOn't merge bvh between meshes, only in scene
	if _scene:
		if not mesh._scene:
			mesh._scene = _scene
		_scene.add_mesh(mesh)
	else:
		print("Mesh should have valid scene but hasnt")

	objects.add_mesh(mesh)

	# TODO Adding mesh gives core/variant/variant_utility.cpp:1111 -
	# Warning: Child node <RefCounted#-9223369183218032947> does not have aabb


func remove_mesh(mesh : PTMesh) -> void:
	objects.remove_mesh(mesh)


func add_object(object : PTObject) -> void:
	#if PTRendererAuto.is_debug:
		#print("Adding object to mesh")
	objects.add_object(object)
	object._scene = _scene
	if is_node_ready():
		if is_instance_valid(_scene):
			_scene.add_object(object)

		if bvh:
			bvh.add_object(object)


# Incomplete
## This function should only be called by the user.
## Removes object from mesh and scene immidietaly
func remove_object(object : PTObject) -> void:
	# TODO Add checks to see if object is a part of container yoo are removing it from
	if object._mesh != self:
		push_error("PT: Cannot remove object -", object, "- from mesh -", self,
		"- as it is not a part of the mesh.")
		return

	print("Object removed from mesh")
	objects.remove_object(object)
	object._mesh = null

	# object._scene and _scene should be equivelant
	_scene.remove_object(object)

	if is_node_ready():
		bvh.remove_object(object)


