@tool
class_name PTScene
extends Node

"""This class is to hold PTObjects, PTMaterials, PTCamera and PTBVH for a scene.

It's responsibility is to keep track of objects and materials, as well as any
changes to them or the BVH. The camera is self sufficient.

"""

# Enum for different custom 3D object types
const ObjectType = PTObject.ObjectType

# Semi-Temp
enum CameraSetting {none, top_down, corner, book_ex, center, left, right, middle}

var camera_settings_values := {
	CameraSetting.top_down : [Vector3(0, 8, -15), Vector3(0,0,-6), 106.],
	CameraSetting.corner : [Vector3(-11, 3, -11), Vector3(0,0,0), 106.],
	CameraSetting.book_ex : [Vector3(13, 2, 3), Vector3(0,0,0), 20 * 16 / 9.],
	CameraSetting.center : [Vector3(0, 0, 1), Vector3(0,0,0), 106.],
	CameraSetting.left : [Vector3(0, 0, 1), Vector3(-1,0,1), 106.],
	CameraSetting.right : [Vector3(0, 0, 1), Vector3(1,0,1), 106.],
	CameraSetting.middle : [Vector3(13, 2, 3), Vector3(0,0,0), 20 * 16 / 9.]
}

## Overrides starting camera values with predefined sets of values
@export var starting_camera := CameraSetting.none

@export var default_bvh := PTBVHTree.BVHType.X_SORTED

@export var create_random_scene_ := false:
	set(value):
		create_random_scene_ = value
		#create_random_scene(0)
		#print("Created random scene")

# Object lists
var spheres : Array[PTSphere]
var planes : Array[PTPlane]
var triangles : Array[PTTriangle]

# Simple dict to choose the right list. get_object_array is preferred
var objects := {
	ObjectType.SPHERE : spheres,
	ObjectType.PLANE : planes,
	ObjectType.TRIANGLE : triangles,
}

var materials : Array[PTMaterial] = [null]
# Inverse of materials
var material_to_index := {null : 0}
var material_ref_count := {null : 0}

## Whenever a material is removed, to not require massive buffer updates, a hole
##  is created. New materials will prioritize filling these holes.
var materials_holes : Array[int]

var textures : Array[PTTexture] = [null]
# Convert a texture into an id used by shader
var texture_to_texture_id := {null : 0}
var texture_ref_count := {null : 0}

# Current BVH that would be used by the Renderer
var bvh : PTBVHTree
# Array of created and unused BVHs
var cached_bvhs : Array[PTBVHTree]

# Whether any objects either moved, got added or removed.
#  Camera is controlled seperately
var scene_changed := false

var camera : PTCamera

var object_count : int = 0


# Flags for update buffering
var added_object := false # Whether an object (or material) was added this frame

# added_types is indexed by ObjectType. NOT_OBJECT is ignored. Specifies what
#  objects was added if added_object is true
var added_types : Array[bool]

# Flags for update buffering
var material_added := false
var material_removed := false
var procedural_texture_added := false
var procedural_texture_removed := false

# Mainly for editor tree. Nodes need to be kept for a little longer after exit_tree
#  to verify if they were deleted or just the scenes were swapped.
var objects_to_remove : Array[PTObject]


func _init() -> void:
	# plus one is for sampled textures
	added_types.resize(ObjectType.MAX + 1)


func _ready() -> void:
	if not Engine.is_editor_hint():
		get_size()

		if camera == null:
			for child in get_children():
				if child is PTCamera:
					camera = child as PTCamera
					break

		if starting_camera != CameraSetting.none:
			set_camera_setting(starting_camera)

	# Scene will probably trigger this when objects add themselves to the scene
	#  Set to false to skip trigger
	added_object = false
	added_types.fill(false)
	material_added = false
	procedural_texture_added = false

	PTRendererAuto.add_scene(self)


func get_object_array(type : ObjectType) -> Array:
	match type:
		ObjectType.SPHERE:
			return spheres
		ObjectType.PLANE:
			return planes
		ObjectType.TRIANGLE:
			return triangles

	return []


## Returns material index of added material. used_by_object refers to whether or
## not the function should increment the materials ref count
func _add_material(material : PTMaterial, used_by_object := false) -> int:
	# Check for object reference in array
	var material_index : int = materials.find(material)
	if material_index == -1:
		if materials_holes:
			material_index = materials_holes.pop_back() # UNSTATIC
			materials[material_index] = material
		else:
			# Add to list if not alreadt in it
			material_index = materials.size()
			materials.append(material)
		material_to_index[material] = material_index # UNSTATIC
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
		material_to_index.erase(material)
		material.disconnect("material_changed", update_material)

		material_removed = true


func _material_changed(
		object : PTObject,
		prev_material : PTMaterial,
		new_material : PTMaterial
	) -> void:

	print("materila canhjfn")
	# If material is swapped there is no need to update whole materials buffer
	var prev_material_added := material_added
	var prev_material_removed := material_removed

	var prev_material_index : int = material_to_index[prev_material] # UNSTATIC

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

		texture_to_texture_id[texture] = texture.get_texture_id(texture_index) # UNSTATIC
		# TODO add texture updatiung buffer/ shader
		#object.material.connect("material_changed", update_material)

		if texture is PTProceduralTexture:
			procedural_texture_added = true
		else:
			# Sampled texture
			#added_types[PTObject.ObjectType.MAX] = true
			pass
	return texture.get_texture_id(texture_index) if texture else 0


func _texture_changed(
		object : PTObject,
		prev_texture : PTTexture,
		new_texture : PTTexture
	) -> void:

	if prev_texture == new_texture:
		push_warning("Changed material to the same material. Unexpected event.")

	#PTRendererAuto.remove_material()


func update_object(object : PTObject) -> void:
	## Called by an object when its properties changed
	# Send request to update bvh if object is in it
	if bvh and PTBVHTree.objects_to_include.has(object.get_type()):
		bvh.update_aabb(object)

	# Send request to update buffer
	PTRendererAuto.update_object(self, object)

	scene_changed = true


func add_object(object : PTObject) -> void:
	"""Adds an object to """
	var type := object.get_type()
	var object_array : Array = get_object_array(type)
	object.object_index = object_array.size()
	object_array.append(object)

	if not object.get_parent():
		print("Added child")
		add_child(object)

	# Increment counters
	object_count += 1

	added_object = true
	added_types[type] = true

	scene_changed = true

	_add_material(object.material, true)
	_add_texture(object.texture)

	object.connect("material_changed", _material_changed)
	object.connect("texture_changed", _texture_changed)

	# Add object to bvh
	if bvh:
		bvh.add_object(object)

	# If object is added after scene ready, update buffer
	if is_node_ready():
		update_object(object)


func queue_remove_object(object : PTObject) -> void:
	if not object in objects_to_remove:
		objects_to_remove.append(object)
	PTRendererAuto.add_scene_to_remove_objects(self)


## Checks if any objects queued for removal are invalid. Returns false if
##  no objects are valid, else true.
func check_objects_for_removal() -> bool:
	# Don't remove nodes that are still in the editor tree from buffers
	if Engine.is_editor_hint():
		var i : int = 0
		for object in objects_to_remove:
			if object.is_inside_tree():
				objects_to_remove.remove_at(i)
				i -= 1
			i += 1

	return not objects_to_remove.is_empty()


## Removes an object from the scene and tree. The object is not deleted.
func remove_object(object : PTObject) -> void:
	var type := object.get_type()
	var object_array : Array = get_object_array(type)
	object_array.remove_at(object.object_index)

	# Update object_index of every object
	for i in range(object_array.size()):
		object_array[i].object_index = i # UNSTATIC

	# Only remove from tree if not in editor. Else it can potentially prevent
	#  an object from being saved to scene on editor quit.
	if object.is_inside_tree() and not Engine.is_editor_hint():
		remove_child(object)
	object._scene = null

	# TODO Remove from texture list if object was their last user


	object.disconnect("material_changed", _material_changed)
	object.disconnect("texture_changed", _texture_changed)

	if bvh:
		bvh.remove_object(object)

	# Send request to update buffer
	PTRendererAuto.remove_object(self, object)

	scene_changed = true
	object_count -= 1


## Removes objects that are queued for removal
func remove_objects() -> void:
	for object in objects_to_remove:
		remove_object(object)
	objects_to_remove.clear()


static func array2vec(a : Array[float]) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func get_size() -> int:
	"""Calculates the number of primitives stored in the scene"""
	object_count = 0

	for _objects : Array in objects.values(): # UNSTATIC
		object_count += _objects.size()

	return object_count


func create_BVH(max_children : int, function_name : String) -> void:
	# TODO add check to reuse BVH if it is in cached_bvhs

	if bvh:
		cached_bvhs.append(bvh)

	bvh = PTBVHTree.create_bvh_with_function_name(self, max_children, function_name)


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








