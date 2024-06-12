@tool
class_name PTScene
extends Node

## This class is to hold PTObjects, PTMaterials, PTCamera and PTBVH for a scene.
##
## It's responsibility is to keep track of objects and materials, as well as any
## changes to them or the BVH. The camera is self sufficient.
##
## TODO Make option to only render an object/mesh and its reflections
##
## TODO Make a mesh be able to only exist in one place in memory when multiple
##  sub_scenes are using it.
## TODO ALSO make bvh nodes only appear once
##
## TODO Make scenes and meshes able to convert to static. Their objects will only
##  exist as buffers and cannot be updated. For performance optimization
##
## WE ARE PIVOTING AWAY FROM SUB SCENES AND TO ACTUAL MESH OBJECTS
##
## Nested meshes use their ancestors tranform to calculate their own global transform
##
## Changing type of scene to mesh should be easy and vice versa
##
## NOTE: Identify packedScrne Mesh instances by using scene_file_path. from docs:
## "The original scene's file path, if the node has been instantiated from a PackedScene file.
## Only scene root nodes contains this."

# Enum for different custom 3D object types
const ObjectType = PTObject.ObjectType

# Semi-Temp
enum CameraSetting {none, top_down, corner, book_ex, center, left, right, middle, cornell}

var camera_settings_values := {
	CameraSetting.top_down : [Vector3(0, 8, -15), Vector3(0,0,-6), 106.],
	CameraSetting.corner : [Vector3(-11, 3, -11), Vector3(0,0,0), 106.],
	CameraSetting.book_ex : [Vector3(13, 2, 3), Vector3(0,0,0), 20 * 16 / 9.],
	CameraSetting.center : [Vector3(0, 0, 1), Vector3(0,0,0), 106.],
	CameraSetting.left : [Vector3(0, 0, 1), Vector3(-1,0,1), 106.],
	CameraSetting.right : [Vector3(0, 0, 1), Vector3(1,0,1), 106.],
	CameraSetting.middle : [Vector3(7, 2, -3), Vector3(0,0,0), 30 * 16 / 9.],
	CameraSetting.cornell : [Vector3(-1, 0.5, 0.5), Vector3(1,0.5,0.5), 106.0],
}

## Overrides starting camera values with predefined sets of values
@export var starting_camera := CameraSetting.none

@export var default_bvh := PTBVHTree.BVHType.X_SORTED
# NOTE: Support for changing bvh_order will be added later
#@export var bvh_order := 8

@export var create_random_scene_ := false:
	set(value):
		create_random_scene_ = value
		#create_random_scene(0)
		#print("Created random scene")

# Objects owned by the scene and objects owned by meshes
var objects : PTObjectContainer

var meshes : Array[PTMesh]

## NOTE: Because of refraction tracking in the shader, a material index is reserved
## for the IOR of air. Currently index 0 is reserved.
var materials : Array[PTMaterial] = [null]
# Inverse of materials
var _material_to_index := {null : 0}
var material_ref_count := {null : 0}

## Whenever a material is removed, to not require massive buffer updates, a hole
##  is created. New materials will prioritize filling these holes.
var materials_holes : Array[int]

var textures : Array[PTTexture] = [null]
# Convert a texture into an id used by shader
var _texture_to_texture_id := {null : 0}
var texture_ref_count := {null : 0}

# Current BVH that would be used by the Renderer
var bvh : PTBVHTree
# Array of created and unused BVHs
var cached_bvhs : Array[PTBVHTree]

# Whether any objects either moved, got added or removed.
#  Camera is controlled seperately
var scene_changed := false

## Current active camera.
var camera : PTCamera:
	set(value):
		if is_instance_valid(camera):
			camera._is_active = false
		if is_instance_valid(value):
			value._is_active = true
		camera = value
## Cameras that the scene can switch between
var cameras : Array[PTCamera]

# Flags for update buffering
var added_object := false # Whether an object was added this frame

# added_types is indexed by ObjectType. NOT_OBJECT and MAX is ignored. Specifies what
#  objects was added if added_object is true
var added_types : Array[bool]

# Flags for update buffering
var material_added := false
var material_removed := false
var procedural_texture_added := false
var procedural_texture_removed := false

## Contains objects and meshes to add before rendering starts
var _to_add : PTObjectContainer
var _to_remove : PTObjectContainer

# Mainly for editor tree. Nodes need to be kept for a little longer after exit_tree
#  to verify if they were deleted or just the scenes were swapped.
var objects_to_remove : Array[PTObject]
var meshes_to_remove : Array[PTMesh]

var _init_time : int
var _enter_tree_time : int

# TODO Add method for scene to free all objects


func _init() -> void:
	_init_time = Time.get_ticks_usec()
	added_types.resize(ObjectType.MAX)
	objects = PTObjectContainer.new()
	_to_add = PTObjectContainer.new()
	_to_remove = PTObjectContainer.new()


func _enter_tree() -> void:
	_enter_tree_time = Time.get_ticks_usec()
	if is_node_ready() and not PTRendererAuto.has_scene(self):
		if PTRendererAuto.is_debug:
			print(self)
			print("added scene on scenes enter_tree")
		request_ready()


func _ready() -> void:
	if not Engine.is_editor_hint():
		get_size()

		if starting_camera != CameraSetting.none:
			set_camera_setting(starting_camera)

	# Scene will probably trigger this when objects add themselves to the scene
	#  Set to false to skip trigger
	added_object = false
	added_types.fill(false)
	material_added = false
	procedural_texture_added = false

	PTRendererAuto.add_scene(self)


func _exit_tree() -> void:
	# NOTE: This is only for the user deleting scenes in the editor scene tree.
	#  Otherwise, a scene should explicitly be removed with a function call.
	if Engine.is_editor_hint():
		PTRendererAuto.add_scene_to_remove(self)


func get_object_index(object : PTObject) -> int:
	return objects._object_to_object_index[object] # UNSTATIC


func get_material_index(material : PTMaterial) -> int:
	return _material_to_index[material] # UNSTATIC


func get_texture_id(texture : PTTexture) -> int:
	return _texture_to_texture_id[texture] # UNSTATIC


func add_camera(f_camera : PTCamera) -> void:
	cameras.append(f_camera)
	if cameras.size() == 1:
		camera = f_camera


func remove_camera(f_camera : PTCamera) -> void:
	cameras.erase(f_camera)


func set_active_camera(f_camera : PTCamera) -> void:
	if cameras.has(f_camera):
		camera = f_camera
	else:
		push_warning(
			"PT: Camera has not been registered to scene. \n%s\n%s" % [f_camera, self]
		)


## Called when the current active camera wants to change
func _change_camera() -> void:
	if cameras.size() <= 1:
		camera = null
	else:
		if cameras[0] == camera:
			camera = cameras[1]
		else:
			camera = cameras[0]


func add_mesh(mesh : PTMesh) -> void:
	#Add objects
	meshes.append(mesh)
	# NOTE: Should scene also add any sub-meshes that have not already been added?

	#var new_added_types := objects.merge(mesh.objects)
#
	## Update object update flags
	#for i in range(new_added_types.size()):
		#added_types[i] = added_types[i] or new_added_types[i]
	#if mesh.objects.object_count != 0:
		#added_object = true

	if bvh:
		if bvh.order < mesh.bvh.order:
			push_error("PT: BVH order ", bvh.order, " of scene does not ",
			"allow for BVH order ", mesh.bvh.order, " of mesh.")
			return
		elif bvh.order > mesh.bvh.order:
			# TODO Add editor warning for mismatched bvh orders
			push_warning("PT: BVH order of mesh is ", mesh.bvh.order, ", ",
			"while BVH order of scene is ", bvh.order, ".\n Mesh BVH order ",
			"will be changed to ", bvh.order, ".")
			mesh.bvh.order = bvh.order

		bvh.merge_with(mesh.bvh)

	print("Binding signals for objects in mesh")
	print(mesh.objects.get_object_lists())
	# Bind signals
	for _objects : Array in mesh.objects.get_object_lists(): # UNSTATIC
		for object : PTObject in _objects: # UNSTATIC
			add_object(object)

	mesh.transform_changed.connect(_update_mesh)
	mesh.deleted.connect(remove_mesh)

	scene_changed = true


func remove_mesh(mesh : PTMesh) -> void:
	print("removing mesh ", mesh)
	print(meshes_to_remove)
	print(objects_to_remove)
	# TODO Remove mesh and objects from scene and bvh, as well as buffers
	meshes.erase(mesh)

	for object : PTObject in objects_to_remove.duplicate():
		if object._mesh == mesh:
			objects_to_remove.erase(object)


	for _objects : Array in mesh.objects.get_object_lists(): # UNSTATIC
		for object : PTObject in _objects: # UNSTATIC
			remove_object(object)

	mesh.transform_changed.disconnect(_update_mesh)
	mesh.deleted.disconnect(remove_mesh)

	if bvh:
		bvh.remove_subtree(mesh.bvh.root_node)


@warning_ignore("unused_parameter")
func _update_mesh(mesh : PTMesh) -> void:
	# TODO Update mesh and sub-meshes transform in buffer, update bvh aabbs
	pass


## Returns material index of added material. used_by_object refers to whether or
## not the function should increment the materials ref count
func _add_material(material : PTMaterial, used_by_object := false) -> int:
	# Check for object reference in array
	var material_index : int = materials.find(material)
	if material_index == -1:
		if not materials_holes.is_empty():
			material_index = materials_holes.pop_back() # UNSTATIC
			materials[material_index] = material
		else:
			# Add to list if not alreadt in it
			material_index = materials.size()
			materials.append(material)
		_material_to_index[material] = material_index # UNSTATIC
		material.connect("material_changed", update_material)

		material_added = true

	if used_by_object:
		if material_ref_count.has(material):
			material_ref_count[material] += 1 # UNSTATIC
		else:
			material_ref_count[material] = 1 # UNSTATIC

	return material_index


## NOTE: Removing a material might mean having to update every objects material index.
##  Currently though, it doesn't immediately remove the material from materials,
##  only allows them to be replaced later on.
func _remove_material(material : PTMaterial) -> void:
	if material:
		var material_index : int = materials.find(material)
		if material_index == -1:
			push_warning("Tried to remove material that was already removed from materials")
			return
		if material_ref_count[material] >= 1:
			push_warning("Material: ", material, " is used by one or more objects")

		materials[material_index] = null
		materials_holes.append(material_index)
		_material_to_index.erase(material)
		material.disconnect("material_changed", update_material)

		material_removed = true


func _material_changed(
		object : PTObject,
		prev_material : PTMaterial,
		new_material : PTMaterial
	) -> void:

	# If material is swapped there is no need to update whole materials buffer
	var prev_material_added := material_added
	var prev_material_removed := material_removed

	var prev_material_index : int = _material_to_index[prev_material] # UNSTATIC

	if prev_material == new_material:
		push_warning("PT: Changed material to the same material. Unexpected event.")

	material_ref_count[prev_material] -= 1 # UNSTATIC
	if material_ref_count[prev_material] <= 0: # UNSTATIC
		_remove_material(prev_material)

	# If material index changed the object has to be updated
	if _add_material(new_material, true) != prev_material_index:
		PTRendererAuto.update_object(self, object)
	else:
		material_added = prev_material_added
		material_removed = prev_material_removed

	# We can buffer update new_material in the same spot as prev_material
	if new_material:
		PTRendererAuto.update_material(self, new_material)

	scene_changed = true


func update_material(material : PTMaterial)  -> void:
	PTRendererAuto.update_material(self, material)

	scene_changed = true


## Returns the texture id
func _add_texture(texture : PTTexture) -> int:
	# Add object texture to textures if applicable
	# Check for object reference in array
	var texture_index : int = textures.find(texture)
	if texture_index == -1:
		# Add to list if not already in it
		texture_index = textures.size()
		textures.append(texture)

		_texture_to_texture_id[texture] = texture.get_texture_id(texture_index) # UNSTATIC
		# TODO add texture updatiung buffer/ shader
		#object.material.connect("material_changed", update_material)

		if texture is PTProceduralTexture:
			procedural_texture_added = true
		else:
			# Sampled texture
			#added_types[PTObject.ObjectType.MAX] = true
			pass
	return texture.get_texture_id(texture_index) if texture else 0


@warning_ignore("unused_parameter")
func _texture_changed(
		object : PTObject,
		prev_texture : PTTexture,
		new_texture : PTTexture
	) -> void:

	if prev_texture == new_texture:
		push_warning("Changed material to the same material. Unexpected event.")

	#PTRendererAuto.remove_material()


func connect_object_signals(object : PTObject) -> void:
	object.connect("object_changed", update_object)
	object.connect("deleted", queue_remove_object)
	object.connect("material_changed", _material_changed)
	object.connect("texture_changed", _texture_changed)


func disconnect_object_signals(object : PTObject) -> void:
	object.disconnect("object_changed", update_object)
	object.disconnect("deleted", queue_remove_object)
	object.disconnect("material_changed", _material_changed)
	object.disconnect("texture_changed", _texture_changed)


## NOTE: Don't know if i should allow user to add object via code and not by adding
##  object to tree.
func add_object(object : PTObject) -> void:
	# IDK if this should be here or just return warning
	if not object.get_parent():
		print("Added child")
		object._scene = self # Setting _scene first is important
		add_child(object)

	var type := object.get_type()
	objects.add_object(object)

	# For making sure buffer fits
	added_object = true
	added_types[type] = true

	scene_changed = true

	# Connect signals
	_add_material(object.material, true)
	_add_texture(object.texture)

	connect_object_signals(object)

	# Add object to bvh
	if bvh and not object.is_meshlet and not object.get_type() in bvh.objects_to_exclude:
		bvh.add_object(object)

	# If object is added after scene ready, update buffer
	if is_node_ready():
		update_object(object)


## Internal function for removing objects in the re-indexing step and
## also part of the complete remove_object function
func _remove_object(object : PTObject) -> void:
	## This is TEMP
	objects.remove_object(object)

	# NOTE: Might be unneccessary
	# Only remove from tree if not in editor. Else it can potentially prevent
	#  an object from being saved to scene on editor quit.
	if object.is_inside_tree() and not Engine.is_editor_hint():
		remove_child(object)

	object._scene = null

	# TODO Remove from texture list if object was their last user

	disconnect_object_signals(object)


## Removes an object from the scene and tree immidietaly. The object is not deleted.
## Can be slow for many objects. Consider using queue_remove_object for mass deletion.
func remove_object(object : PTObject) -> void:
	print( "\nRemoving object from scene. ", object, " ", self)
	objects.remove_object(object)

	# NOTE: Might be unneccessary
	# Only remove from tree if not in editor. Else it can potentially prevent
	#  an object from being saved to scene on editor quit.
	if object.is_inside_tree() and not Engine.is_editor_hint():
		remove_child(object)

	object._scene = null

	# TODO Remove from texture list if object was their last user

	object.disconnect("object_changed", update_object)
	object.disconnect("deleted", queue_remove_object)
	object.disconnect("material_changed", _material_changed)
	object.disconnect("texture_changed", _texture_changed)

	if bvh and not object.get_type() in PTBVHTree.objects_to_exclude:
		bvh.remove_object(object)

	# Send request to update buffer
	# TODO MOVE out of funciton, to PTRenderer maybe
	PTRendererAuto.remove_object(self, object)

	#if object.is_meshlet and not object._mesh in meshes_to_remove:
		#object._mesh.remove_object(object)

	scene_changed = true


func update_object(object : PTObject) -> void:
	## Called by an object when its properties changed
	# Send request to update bvh if object is in it
	if bvh and not object.get_type() in PTBVHTree.objects_to_exclude:
		bvh.update_aabb(object)

	# Send request to update buffer
	PTRendererAuto.update_object(self, object)

	scene_changed = true


func queue_add_object(object : PTObject) -> void:
	if not _to_add.has(object):
		_to_add.add_object(object)


func queue_remove_object(object : PTObject) -> void:
	# TODO test if deleting mesh and object at the same time in editor causes bugs
	if not _to_remove.has(object):
		_to_remove.add_object(object)
	if not object in objects_to_remove and not object._mesh in meshes_to_remove:
		objects_to_remove.append(object)

	PTRendererAuto.add_scene_to_remove_objects(self)


## Checks if any objects queued for removal are invalid. Returns false if
##  no objects are valid, else true. Also checks meshes
func check_objects_for_removal() -> bool:
	# Don't remove nodes that are still in the editor tree from buffers
	if Engine.is_editor_hint():
		var offset : int = 0
		for i in range(objects_to_remove.size()):
			if objects_to_remove[i].is_inside_tree():
				objects_to_remove.remove_at(i + offset)
				offset -= 1
		offset = 0
		for i in range(meshes_to_remove.size()):
			if meshes_to_remove[i].is_inside_tree():
				meshes_to_remove.remove_at(i + offset)
				offset -= 1

	return not objects_to_remove.is_empty() or not meshes_to_remove.is_empty()


## Removes objects that are queued for removal
func remove_objects() -> void:
	for mesh in meshes_to_remove:
		remove_mesh(mesh)
	meshes_to_remove.clear()
	for object in objects_to_remove:
		remove_object(object)
	objects_to_remove.clear()


## Called after all have objects and meshes have been removed, added and updated.
## Almost definitely a result of premature optimization
func _re_index() -> void:

	# These variables will hold ALL objects that needs to be added/removed
	# The BVHTree only requires meshes and the scene's objects to reindex
	var unpacked_to_add := PTObjectContainer.new()
	var unpacked_to_remove := PTObjectContainer.new()
	# Add meshes objects to conatiners of objects to add/remove
	unpacked_to_add.merge(_to_add)
	for mesh in _to_add.meshes:
		unpacked_to_add.merge(mesh.objects)
	unpacked_to_remove.merge(_to_remove)
	for mesh in _to_remove.meshes:
		unpacked_to_remove.merge(mesh.objects)

	## Functions for assert check
	# Checks if any object is a part of a mesh in a given object container
	var no_object_part_of_mesh := func temp(object_container : PTObjectContainer) -> bool:
		for type : ObjectType in ObjectType.values():
			for object : PTObject in object_container.get_object_array(type):
				if object.is_meshlet:
					return false
		return true

	# Checks for any objects being shared by containers
	var no_object_part_of_container := func (object_container1 : PTObjectContainer,
	object_container2 : PTObjectContainer) -> bool:
		for mesh in object_container1.meshes:
			if mesh in object_container2.meshes:
				return true
		for type : ObjectType in ObjectType.values():
			var object_array := object_container2.get_object_array(type)
			for object : PTObject in object_container1.get_object_array(type):
				if object in object_array:
					return false
		return true

	var all_objects_part_of_container := func (object_container1 : PTObjectContainer,
	object_container2 : PTObjectContainer) -> bool:
		for type : ObjectType in ObjectType.values():
			var object_array := object_container2.get_object_array(type)
			for object : PTObject in object_container1.get_object_array(type):
				if not object in object_array:
					return false
		return true

	assert(no_object_part_of_mesh.callv([_to_add]),
		"PT - _re_index: Trying to add object that is part of mesh, " +
		"instead of adding mesh.")
	assert(no_object_part_of_mesh.callv([_to_remove]),
		"PT - _re_index: Trying to remove object that is part of mesh, " +
		"instead of removing mesh.")
	assert(no_object_part_of_container.callv([unpacked_to_add, objects]),
		"PT - _re_index: Trying to add object to scene that is already there.")
	assert(all_objects_part_of_container.callv([unpacked_to_remove, objects]),
		"PT - _re_index: Trying to remove object when it is not a part of the scene.")

	## Actual functions
	# Re-index objects
	objects._rebalance_objects(unpacked_to_add, unpacked_to_remove)

	# Re-index BVHNodes
	# TEMP Merge with bvh.updated_nodes
	var updated_node_indices := bvh._rebalance_objects(_to_add, _to_remove)

	# TODO Update object buffers
	# NOTE: IMPORTANT object types that are not in the bvh have to be nulled out

	# TODO Update BVHBuffer

	# TODO Reset values

	pass


func get_size() -> int:
	"""Calculates the number of primitives stored in the scene"""
	return objects.object_count


func create_BVH(order : int, function_name : String) -> void:
	# TODO add check to reuse BVH if it is in cached_bvhs

	if bvh:
		cached_bvhs.append(bvh)

	bvh = PTBVHTree.create_bvh_with_function_name(objects, order, function_name)


func set_camera_setting(cam : CameraSetting) -> void:
	if camera:
		var pos : Vector3 = camera_settings_values[cam][0] # UNSTATIC
		var look : Vector3 = camera_settings_values[cam][1] # UNSTATIC
		var fov : float = camera_settings_values[cam][2] # UNSTATIC

		camera.position = pos

		camera.look_at(look)

		camera.fov = fov / camera.aspect_ratio
		camera.set_viewport_size()
	else:
		push_warning("PT: Cannot set camera settings when no camera has been attached \
to the scene")


func create_random_scene(_seed : int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	# Ground
	var ground_mat := PTMaterial.new()
	ground_mat.albedo = Color(0.5, 0.5, 0.5)

	add_object(PTPlane.new(Vector3(0, 1, 0), -1., ground_mat))
	#add_object(PTSphere.new(Vector3(0, -1000, 0), 1000, ground_mat))

	# Glass
	var mat1 := PTMaterial.new()
	mat1.IOR = 1.5
	mat1.opacity = 0.
	add_object(PTSphere.new(Vector3(0, 1, 0), 1, mat1))

	# Diffuse
	var mat2 := PTMaterial.new()
	mat2.albedo = Color(0.4, 0.2, 0.1)
	add_object(PTSphere.new(Vector3(-4, 1, 0), 1, mat2))

	# Metallic
	var mat3 := PTMaterial.new()
	mat3.albedo = Color(0.7, 0.6, 0.5)
	mat3.metallic = 1.
	add_object(PTSphere.new(Vector3(4, 1, 0), 1, mat3))

	for i in range(22):
		for j in range(22):
			var center := Vector3((i - 11) + 0.9 * rng.randf(),
								 0.2,
								 (j - 11) + 0.9 * rng.randf())
			var radius := 0.2

			var choose_material := rng.randf()
			var material := PTMaterial.new()

			var color := Color(rng.randf(), rng.randf(), rng.randf())

			if choose_material < 0.8:
				pass
			elif choose_material < 0.95:
				# Metal
				color = Color(rng.randf_range(0.5, 1.),
								rng.randf_range(0.5, 1.),
								rng.randf_range(0.5, 1.))
				material.metallic = choose_material + 0.05
			else:
				# Glass
				color = Color(rng.randf_range(0.88, 1.),
								rng.randf_range(0.88, 1.),
								rng.randf_range(0.88, 1.))
				material.opacity = 0.
				material.IOR = 1.6

			material.albedo = color
			var new_sphere := PTSphere.new(center, radius, material)
			add_object(new_sphere)
