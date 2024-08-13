@tool
class_name PTMesh
extends Node3D

## A simple class to hold PTObjects with their own transform and BVH
##
## PTMeshes in same PTScene can be instantiated and save memory. * COMING SOON *

@export var bvh_type := PTBVHTree.BVHType.X_SORTED
@export var bvh_order : int = 8
@export var group_mesh_instance := true

@export_group("Overrides")
@export var default_material : PTMaterial
@export var override_material : PTMaterial

signal transform_changed(mesh : PTMesh)

signal deleted(mesh : PTMesh)

var objects : PTObjectContainer

var bvh : PTBVHTree

# The scene this object is part of. This object might also be a part of a mesh.
var scene : PTScene
# var _mesh : PTMesh # TODO DEPRECATED

#var surface_mesh : ArrayMesh
var mesh : Mesh

var transform_before : Transform3D

# TODO Be able to see and edit meshes while they are instatiated
# TODO Grimchild mesh has a loose triangle when rotated.
# This traingle is actually only seen when looking through th red spheres aabb

# TODO Actually just make more like objects. They talk only with their scene.
# They have no responsibility for nested meshes. Nested meshes in bvh is just a mesh.
# mess*


func _init() -> void:
	objects = PTObjectContainer.new()


func _enter_tree() -> void:
	# Find scene or mesh when entering tree if scene is not set
	if not is_instance_valid(scene) :
		scene = PTObject.find_scene_ancestor(self)

	transform_before = Transform3D(global_transform)
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

	for child in get_children():
		if child is MeshInstance3D:

			if PTRendererAuto.is_debug:
				print("PT: Importing mesh child")
				print(child)

			mesh = (child as MeshInstance3D).mesh

			for triangle in objects.mesh_to_pttriangles(mesh):
				add_object(triangle)
				add_child(triangle)

	# Find imported mesh, if it exists
	var skeleton := get_node_or_null("Armature/Skeleton3D")
	if PTRendererAuto.is_debug:
		print("\nPT: Looking for mesh...")
	if skeleton:
		if PTRendererAuto.is_debug:
			print("PT: Found mesh")
		var temp : MeshInstance3D = skeleton.get_child(0)
		mesh = temp.mesh

		for triangle in objects.mesh_to_pttriangles(mesh):
			add_object(triangle)
			add_child(triangle)

	var function_name : String = PTBVHTree.enum_to_dict[bvh_type] # UNSTATIC
	bvh = PTBVHTree.create_bvh_with_function_name(objects, bvh_order, function_name, self)

	if scene:
		if PTRendererAuto.is_debug:
			print("Mesh adds itself to scene. mesh: ", self, " ", scene)
		scene.add_mesh(self)


func _notification(what : int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			if scene and global_transform != transform_before:
				transform_changed.emit(self)
				transform_before = Transform3D(global_transform)


func add_object(object : PTObject) -> void:
	#if PTRendererAuto.is_debug:
		#print("Adding object to mesh")
	object._scene = scene
	object._mesh = self
	objects.add_object(object)
	if is_node_ready():
		if is_instance_valid(scene) and scene.has_mesh(self):
			scene.add_object(object)

		if bvh:
			bvh.add_object(object)


# Incomplete
## This function should only be called by the user.
## Removes object from mesh and scene immidietaly
func remove_object(object : PTObject) -> void:
	if object._mesh != self:
		push_error("PT: Cannot remove object -", object, "- from mesh -", self,
		"- as it is not a part of the mesh.")
		return

	print("Object removed from mesh")
	objects.remove_object(object)
	object._mesh = null

	# object._scene and scene should be equivelant
	scene.remove_object(object)

	if is_node_ready():
		bvh.remove_object(object)


## Returns the mesh's global transform in a byte array
func to_byte_array() -> PackedByteArray:
	return PTUtils.transform3d_smuggle_to_byte_array(
		global_transform.affine_inverse(), Vector4(0, 0, 0, 1))

