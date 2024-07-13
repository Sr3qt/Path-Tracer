@tool
class_name PTRenderer
extends Node

## This node is a Singleton with the responsibility of rendering the current scene.
##
## PTScenes will add themselves to this Singleton. The user can ask PTRenderer
## to swap scenes.

# TODO WOuld be cool to have custom icons (@icons)

const WindowGui := preload("res://ui_scenes/render_window_gui/render_window_gui.tscn")

# NOTE: CPU control over gpu invocations has not been added.
#	These are merely for reference
const compute_invocation_width : int = 8
const compute_invocation_height : int = 8
const compute_invocation_depth : int = 1

const _MAX_OWNER_SEARCH_DEPTH = 30

## Whether the plugin should print internal debug messages
var is_debug := true

## General override for stopping rendering. When enabled no work will be pushed to the
##  GPU and the screen will be white.
@export var is_rendering_disabled := false:
	set(value):
		is_rendering_disabled = value
		_set_canvas_visibility()

## Override for stopping rendering. Specifically for when no scene is present.
var has_active_scene := false:
	set(value):
		has_active_scene = value
		_set_canvas_visibility()

var has_active_camera := true:
	set(value):
		has_active_camera = value
		_set_canvas_visibility()

func _set_canvas_visibility() -> void:
	if canvas:
		var is_rendering := (not is_rendering_disabled and has_active_scene
				and has_active_camera)
		var mat := canvas.mesh.surface_get_material(0) as ShaderMaterial
		mat.set_shader_parameter("is_rendering", is_rendering)
		canvas.visible = is_rendering

var wd : PTWorkDispatcher # Current PTWorkDispatcher for the current scene
## Uses same indexing as scenes
var wds : Array[PTWorkDispatcher] # An array of WorkDispatchers for each scene

var scene : PTScene # The scene currently in use
## Uses same indexing as wds
var scenes : Array[PTScene] # An array of scenes. Primarily used by plugin
var scenes_to_remove : Array[PTScene]

# Two dicitionary that keeps track of multiple PTScenes within one Godot scene.
# Only used by plugin, for runtime scene tracker see scene_to_scene_index
var _root_node_to_scenes := {}
var _root_node_to_last_index := {} # TODO add to main control
var _scene_to_root_node := {}

# PTScene as key and scene_index pointing to the same scene in scenes
var scene_to_scene_index := {}

# Array of sub-windows
var windows : Array[PTRenderWindow] = []

# The mesh to draw to
var canvas : MeshInstance3D

# The camera used by the editor in 3D main panel. Only used by plugin
var editor_camera : Camera3D
# Used to transfer editor camera attributes to gpu
var _pt_editor_camera : PTCamera

# Whether the _pt_editor_camera will follow editor_camera. Only used by plugin
var is_camera_linked := true:
	set(value):
		if editor_camera:
			editor_camera.set_cull_mask_value(20, value)
		is_camera_linked = value

# TODO remove and replace with ptscene variable
# Controls the degree of the bvh tree passed to the gpu.
var bvh_order : int = 8

# TODO Make render settings node similar to WorldEnvironment
var render_width := 1920
var render_height := 1080

var samples_per_pixel : int = 1 # DEPRECATED REMOVE
@export var max_default_depth : int = 8
@export var max_refraction_bounces : int = 8

# Whether anything was rendered in the last render_window call. Only used by plugin
var was_rendered := false

# Whether a scene was changed in the editor dock. Only used by plugin
var _has_scenes_swapped := false

var _startup_time : int = 0
# Whether all scenes have been initiated. Only in Editor. Only toggled by plugin.gd
var _is_init := false

# Array of scenes that wants one or more of their objects to be removed from buffers.
# NOTE: Scenes add themselves.
var scenes_to_remove_objects : Array[PTScene]

var screenshot_folder := "res://renders/temps/" + Time.get_date_string_from_system() + "/"


func _init() -> void:
	# NOTE: Only triggers when not Engine.is_editor_hint()
	print("PTRenderer init time: ", (Time.get_ticks_usec()) / 1000., "ms ")


## Called by plugin.gd after PTRenderer has setup everything
func _post_init() -> void:
	print()
	print("Loading PT plugin config (lie)")
	print("Total Editor Startup Time: ", (Time.get_ticks_usec()) / 1000., " ms")
	print()
	print("reeeeeeee")
	# TODO REport bug where bottom of output is not shown to exist. Only when show duplicate is toggled on specifically
	#  Might be connected to the _set_window_layout not triggering correctly.
	#  ACtually it can't be, because the time printed is correct.
	PTRendererAuto._is_init = true
	PTRendererAuto.scenes_to_remove.clear()
	for ptscene in scenes:
		ptscene._to_add.clear()
		ptscene._to_remove.clear()


func _ready() -> void:
	print()
	print("PTRenderer ready time: ", (Time.get_ticks_usec()) / 1000., "ms ")
	_startup_time = Time.get_ticks_usec()

	# REMOVE in final
	if not Engine.is_editor_hint():
		# Apparently very import check for get_window (Otherwise the editor bugs out)
		get_window().position -= Vector2i(450, 100)

	if not canvas:
		canvas = create_canvas()

	# If the Renderer is running in the editor, a single camera is used
	#  instead of using each scene's camera
	if Engine.is_editor_hint():
		# NOTE: The editor stores the editor_camera's transforms and copies them
		#  on input event. Therefore moving the camera in the plugin dock
		#  can only move the camera until an input in the editor is detected.
		#  This is why moving in the dock was removed, preferring to just use
		#  the editors camera.

		# Get Editor Camera
		editor_camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()

		# Unlink camera if rendering is disabled
		is_camera_linked = is_camera_linked and not is_rendering_disabled

		# Show canvas to editor camera if is_camera_linked
		editor_camera.set_cull_mask_value(20, is_camera_linked)

	if not Engine.is_editor_hint():
		var x := ceili(1920. / 8.)
		var y := ceili(1080. / 8.)

		var better_window := WindowGui.instantiate() as PTRenderWindow
		better_window.max_samples = 300
		better_window.stop_rendering_on_max_samples = false

		better_window.work_group_width = x
		better_window.work_group_height = y

		add_window(better_window)


func _process(_delta : float) -> void:
	# NOTE: Stutter issue was caused by having a timer on screen on separate
	#  monitor with different resolution on windows. lol
	was_rendered = false

	_remove_queued_scenes()
	_object_queue_remove()

	#if not Engine.is_editor_hint():
	#_re_index_scenes()

	# Make sure the rendering scene has up to date bvh buffer
	if scene and scene.bvh:
		update_bvh_nodes(scene)

	# If editor camera moved, copy the data to scene.camera
	if Engine.is_editor_hint() and editor_camera and is_camera_linked:
		if (not (editor_camera.position == _pt_editor_camera.position and
				editor_camera.transform == _pt_editor_camera.transform)):
			_pt_editor_camera.copy_camera(editor_camera)

	## Decides if any rendering will be done at all
	# Runtime and plugin requires different checks for window focus
	var runtime := (get_window().has_focus() and not Engine.is_editor_hint())
	var plugin := (Engine.is_editor_hint())

	var common := (not is_rendering_disabled and has_active_scene and
			has_active_camera)

	if (runtime or plugin) and common:
		# Double check camera is there
		if not is_instance_valid(scene.camera) and not Engine.is_editor_hint():
			# TODO ADD Reporting node configuration warnings
			# https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html
			push_error("No camera has been set in current scene.\n" +
					"Rendering is therefore temporarily disabled.")
			has_active_camera = false

		if has_active_camera:
			# If no warnings are raised, this will render
			for window in windows:
				render_window(window)

			# NOTE: For some reason this is neccessary for smooth performance in editor
			if Engine.is_editor_hint() and was_rendered:
				var mat := canvas.mesh.surface_get_material(0) as ShaderMaterial
				mat.set_shader_parameter("is_rendering", true)

	_update_scenes()


func _exit_tree() -> void:
	for _wd in wds:
		_wd.free_rids()


## It is plugin_control_root's responsibility to call this function
func _set_plugin_camera(cam : PTCamera) -> void:
	if not canvas:
		canvas = create_canvas()

	has_active_camera = true
	_pt_editor_camera = cam
	_pt_editor_camera.add_child(canvas)


## Although PTRenderer can store multiple PTRenderWindows, there is currently
##  no plan to support multiple windows simultaniously.
func add_window(window : PTRenderWindow) -> void:
	windows.append(window)

	if not Engine.is_editor_hint():
		add_child(window)


func render_window(window : PTRenderWindow) -> void:
	"""Might render window according to flags if flags allow it"""

	# If camera moved or scene changed
	var camera_moved := ((scene and scene.camera and scene.camera.camera_changed) or
			(Engine.is_editor_hint() and _pt_editor_camera.camera_changed))

	var movement := camera_moved or scene.scene_changed

	# If rendering should stop when reached max samples
	var stop_multisampling := (
			window.stop_rendering_on_max_samples and
			(window.frame >= window.max_samples)
	)

	var multisample := (window.enable_multisampling and not stop_multisampling and
			not window._disable_multisample)

	# Adds the time of the last frame rendered
	if window.frame == window.max_samples and multisample and window.was_rendered:
		window.frame_times += (
				Time.get_ticks_usec() - window.max_sample_start_time
		) / 1_000_000.0

	# If window will not render return
	if not (movement or multisample or window.render_mode_changed):
		window.was_rendered = false
		return

	# RENDER
	window.scene_changed = movement

	# Adds the time taken since last frame render started
	if window.frame < window.max_samples and multisample and window.was_rendered:
		window.frame_times += (
				Time.get_ticks_usec() - window.max_sample_start_time
		) / 1_000_000.0

	# If frame is above limit or a scene/camera/flag change caused a reset
	if window.frame > window.max_samples or movement or window.render_mode_changed:
		window.frame = 0

	if window.frame == 0:
		window.frame_times = 0

	window.max_sample_start_time = Time.get_ticks_usec()

	# Create work for gpu
	wd.create_compute_list(window)

	window.frame += 1

	# Reset frame values
	window.scene_changed = false
	window.render_mode_changed = false

	window.was_rendered = true
	was_rendered = true


## Saves the last rendered image as a png.
## The defualt directory is "res://renders/temps/[date_for_today]/".
## The directory can be changed with the property "screenshot_folder"
func take_screenshot() -> void:
	if not wd:
		if Engine.is_editor_hint():
			push_warning("PT: No valid scene is selected for taking screenshot.")
			return
		push_warning("PT: No valid PTScene is selected for taking screenshot.")

	var image : PackedByteArray = wd.rd.texture_get_data(wd.image_buffer, 0)
	# Changing the renderer render size should always create a new buffer, so
	#  this code should always yield a correct result
	var new_image := Image.create_from_data(
		render_width,
		render_height,
		false,
		Image.FORMAT_RGBAF,
		image
	)

	var defualt_folder_path := (
			"res://renders/temps/" + Time.get_date_string_from_system() + "/"
	)

	if screenshot_folder == defualt_folder_path:
		# Make folder for today if it doesnt exist
		if not DirAccess.dir_exists_absolute(screenshot_folder):
			DirAccess.make_dir_recursive_absolute(screenshot_folder)

	new_image.save_png(screenshot_folder +
			Time.get_datetime_string_from_system().replace(":", "-") + ".png")

	print("PT: Picture taken :)")


func get_scene_wd(ptscene : PTScene) -> PTWorkDispatcher:
	return wds[scene_to_scene_index[ptscene]]


func has_scene(ptscene : PTScene) -> bool:
	return scenes.has(ptscene)


func add_scene(new_ptscene : PTScene) -> void:
	"""Adds a scene to renderer"""

	# Maybe redundant check
	if new_ptscene == null:
		push_warning("PT: Tried to add null scene.")
		return

	# If in editor, add translation layer from ptscenes owner to ptscene
	if Engine.is_editor_hint():
		if not new_ptscene.owner:
			# Here new_ptscene is either a root node or has just been instantiated
			#  in the editor tree.
			# Find root node of PTScene
			var counter : int = 0
			var current_node : Node = new_ptscene.get_parent()
			while (counter < _MAX_OWNER_SEARCH_DEPTH and
					current_node and
					not _root_node_to_scenes.has(current_node)
				):
				current_node = current_node.get_parent()
				counter += 1

			# If search for the new_ptscenes owner found it
			if counter < _MAX_OWNER_SEARCH_DEPTH and current_node:
				# current_node is new_ptscene.owner
				if is_debug:
					print("owner found! ", current_node)
				# NOTE: We set owner since the editor doesn't set it before saving scene
				new_ptscene.owner = current_node

				@warning_ignore("unsafe_method_access")
				_root_node_to_scenes[current_node].append(new_ptscene) # UNSTATIC
				_scene_to_root_node[new_ptscene] = current_node # UNSTATIC

			# Here new_ptscene is the root node of a scene,
			# register it if not already registered
			# NOTE: Child nodes will always register before root node
			else:
				if _root_node_to_scenes.has(new_ptscene):
					@warning_ignore("unsafe_method_access")
					_root_node_to_scenes[new_ptscene].append(new_ptscene) # UNSTATIC
				else:
					var temp_array : Array[PTScene] = [new_ptscene]
					_root_node_to_scenes[new_ptscene] = temp_array # UNSTATIC
					_root_node_to_last_index[new_ptscene] = 0 # UNSTATIC
				_scene_to_root_node[new_ptscene] = new_ptscene # UNSTATIC

		# If root_node already has a ptscene associated with it
		elif _root_node_to_scenes.has(new_ptscene.owner):
			@warning_ignore("unsafe_method_access")
			_root_node_to_scenes[new_ptscene.owner].append(new_ptscene) # UNSTATIC
			_scene_to_root_node[new_ptscene] = new_ptscene.owner # UNSTATIC
		else:
			# new_ptscene is a child of an unseen scene
			var temp_array : Array[PTScene] = [new_ptscene]
			_root_node_to_scenes[new_ptscene.owner] = temp_array # UNSTATIC
			_root_node_to_last_index[new_ptscene.owner] = 0 # UNSTATIC
			_scene_to_root_node[new_ptscene] = new_ptscene.owner # UNSTATIC

	scene_to_scene_index[new_ptscene] = scenes.size() # UNSTATIC
	scenes.append(new_ptscene)

	if is_debug:
		print()
		print(new_ptscene.owner, " Root node, ", new_ptscene, " PTScene node")

	if new_ptscene.get_size() > 0:
		var function_name : String = PTBVHTree.enum_to_dict[new_ptscene.default_bvh] # UNSTATIC
		new_ptscene.create_BVH(bvh_order, function_name)
	else:
		new_ptscene.bvh = PTBVHTree.new(bvh_order)

	if not canvas:
		canvas = create_canvas()

	# Create new WD
	var new_wd := PTWorkDispatcher.new(self)
	new_wd.set_scene(new_ptscene)
	new_wd.load_shader(PTUtils.load_shader(new_ptscene))
	new_wd.create_buffers()

	wds.append(new_wd)

	# Set new_ptscene to scene if no scene was previously active and is in runtime
	if not Engine.is_editor_hint() and not has_active_scene:
		change_scene(new_ptscene)

	if is_debug:
		if new_ptscene.get_size() == 0:
			print("Added empty scene")
			return

		print("PTScene ready time: ",
				(Time.get_ticks_usec() - new_ptscene._enter_tree_time) / 1000.0, " ms")
		if not _is_init:
			print("Total PTScene setup time: ",
					(Time.get_ticks_usec() - new_ptscene._init_time) / 1000.0, " ms")
			print((Time.get_ticks_usec()) / 1000., " ms")


func remove_scene(ptscene : PTScene) -> void:
	if not scenes.has(ptscene):
		push_warning("PT: Cannot remove PTScene that is not registered in scenes.\n",
			"scenes: ", scenes, "\nPTScene to remove: ", ptscene)

	print("Closing scene: ", ptscene)
	# Remove all references to ptscene
	var index := scenes.find(ptscene)
	if index != -1:
		var _scene_wd := wds[index]
		scenes.remove_at(index)
		wds.remove_at(index)

	# if running in editor, cleanup _root_node_to_scenes and _root_node_to_last_index
	if Engine.is_editor_hint():
		# If ptscene was a root_node, remove it from the keys
		_root_node_to_scenes.erase(ptscene)
		_root_node_to_last_index.erase(ptscene)
		_scene_to_root_node.erase(ptscene)
		# If ptscene is a reference under any other root nodes
		for root_node : Node in _root_node_to_scenes.keys(): # UNSTATIC
			# NOTE: Because child PTScenes add themselves first to _root_node_to_scenes,
			# they should also be the first to removed when closing a scene.
			# Just in case they are not we check to see if root_node is a valid index
			if not _root_node_to_scenes.has(root_node):
				push_warning("PT: Root node PTScene was deleted before descendant PTScene")
				continue
			var temp_scenes : Array[PTScene] = _root_node_to_scenes[root_node]# UNSTATIC
			var temp_scenes_size := temp_scenes.size()
			var _index : int = temp_scenes.find(ptscene)
			if _index == -1:
				continue

			temp_scenes.remove_at(_index)

			# Remove keys if the root's scenes are empty
			if temp_scenes.is_empty():
				_root_node_to_scenes.erase(root_node)
				_root_node_to_last_index.erase(root_node)
			# If last_index is out of range, redefine it within range
			elif _root_node_to_last_index[root_node] >= temp_scenes_size: # UNSTATIC
				_root_node_to_last_index[root_node] = temp_scenes_size - 1 # UNSTATIC

	scene_to_scene_index.erase(ptscene)
	scenes_to_remove_objects.erase(ptscene)

	# Reindex scenes
	var i : int = 0
	for pt_scene in scenes:
		scene_to_scene_index[pt_scene] = i # UNSTATIC
		i += 1

	if ptscene == scene:
		scene = null
		wd = null
		has_active_scene = false


func change_scene(ptscene : PTScene) -> void:
	if not scene_to_scene_index.has(ptscene):
		push_warning("PT: Cannot switch to unregistered scene.")
		return

	# Remove (and later add) canvas from camera in runtime
	if not Engine.is_editor_hint():
		if scene and scene.camera:
			scene.camera.remove_child(canvas)

	var scene_index : int = scene_to_scene_index[ptscene]  # UNSTATIC
	scene = scenes[scene_index]
	wd = wds[scene_index]
	# Change buffer displayed on canvas
	wd.texture.texture_rd_rid = wd.image_buffer

	has_active_scene = true

	if not Engine.is_editor_hint():
		if scene.camera:
			has_active_camera = true
			scene.camera.add_child(canvas)

	# TODO Update GUI values


func add_scene_to_remove_objects(ptscene : PTScene) -> void:
	if not ptscene in scenes_to_remove_objects:
		scenes_to_remove_objects.append(ptscene)


func add_scene_to_remove(ptscene : PTScene) -> void:
	if not ptscene in scenes_to_remove:
		scenes_to_remove.append(ptscene)


func _remove_queued_scenes() -> void:
	if scenes_to_remove.is_empty():
		return

	if not _has_scenes_swapped:
		print("PT: Removing PTScene(s) that was deleted by the user.")
		for ptscene in scenes_to_remove:
			if not is_instance_valid(ptscene): # If scene is null; idk can prob remove
				push_warning("PT: Help; Scene is no longer valid for deletion.")
				continue
			remove_scene(ptscene)
	else:
		if is_debug:
			print("PT: Scene was changed, or the editor just started, " +
					"so no scene removal will occur.")

	scenes_to_remove.clear()


## Updates all scenes that have changed. Called at the end of _process
func _update_scenes() -> void:
	# Re-create buffers if asked for
	for ptscene in scenes:
		var scene_wd := get_scene_wd(ptscene)

		# Catch scene removal leaks
		if not is_instance_valid(ptscene):
			push_warning("PT: Bad garbage collection. Scene: ", ptscene,
					" is still in PRenderer.scenes and is invalid.")

			# NOTE: Cannot append freed object to typed array apparently
			#scenes_to_remove.append(ptscene)
			continue

		# Update BVHNodes in bvh buffer
		#if ptscene.bvh and not ptscene.bvh.updated_nodes.is_empty():
			#update_bvh_nodes(ptscene)

		# Just debug
		if (ptscene.material_added or ptscene.procedural_texture_added) and is_debug:
			print()
			print("Expanding object buffers for ", ptscene, ":")

		# Expands material buffer if required, skips set creation if
		#  object buffers also need updating.
		if ptscene.material_added:
			scene_wd.expand_material_buffer(0, not ptscene.added_object)
		if ptscene.added_object:
			var buffers := PTObject.bool_to_object_type_array(ptscene.added_types)
			scene_wd.expand_object_buffers(buffers)

		if ptscene.procedural_texture_added:
			scene_wd.load_shader(PTUtils.load_shader(ptscene))
			if is_debug:
				print("Reloaded shader")

		# Reset frame based flags
		# TODO Turn into public ptscene func
		ptscene.added_object = false
		ptscene.added_types.fill(false)

		ptscene.procedural_texture_added = false
		ptscene.procedural_texture_removed = false
		ptscene.material_added = false
		ptscene.material_removed = false
		ptscene.scene_changed = false

		if ptscene.camera:
			ptscene.camera.camera_changed = false

	if Engine.is_editor_hint():
		_pt_editor_camera.camera_changed = false
		_has_scenes_swapped = false


func _plugin_scene_closed(scene_path : String) -> void:
	for node : Node in _root_node_to_scenes.keys(): # UNSTATIC
		if node.scene_file_path == scene_path:
			var temp_array : Array[PTScene] = _root_node_to_scenes[node] # UNSTATIC
			for ptscene : PTScene in temp_array.duplicate(): # UNSTATIC
				remove_scene(ptscene)


## Wrapper function for the plugin to change scenes
func _plugin_change_scene(scene_root : Node) -> void:
	_has_scenes_swapped = true
	if scene_root == null or not _root_node_to_scenes.has(scene_root):
		# scene_root is a new empty node or a root without a PTScene in the scene
		scene = null
		wd = null
		has_active_scene = false
		return

	var temp_scenes : Array[PTScene] = _root_node_to_scenes[scene_root] # UNSTATIC
	var scene_to_change : PTScene = temp_scenes[_root_node_to_last_index[scene_root]]

	change_scene(scene_to_change)


# TODO Can be made static, and moved elsewhere
func create_canvas() -> MeshInstance3D:
	# Create canvas that will display rendered image
	# Prepare canvas shader
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/canvas.gdshader")
	mat.set_shader_parameter("image_buffer", Texture2DRD.new())
	mat.set_shader_parameter("is_rendering", not is_rendering_disabled)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	mesh.surface_set_material(0, mat)

	# Create a canvas to which rendered images will be drawn
	@warning_ignore("shadowed_variable")
	var canvas := MeshInstance3D.new()
	canvas.position -= Vector3(0,0,1)
	canvas.set_layer_mask_value(20, true)
	canvas.set_layer_mask_value(1, false)
	canvas.mesh = mesh

	return canvas


func create_bvh(ptscene : PTScene, _order : int, function_name : String) -> void:
	# TODO Rework shader to work with different bvh orders without reloading
	if not is_instance_valid(scene):
		push_warning("PT: Cannot create bvh as there is no set scene.")
		return

	# TODO Add support so that all objects in scene can be rendered by bvh
	#  THis is a bug because the shader has a fixed stack size and cannot always
	#  accommodate for every object count and bvh order
	var prev_max : int = bvh_order
	bvh_order = _order

	ptscene.create_BVH(bvh_order, function_name)

	if prev_max != bvh_order:
		PTUtils.load_shader(ptscene)

	var scene_wd := get_scene_wd(ptscene)
	# NOTE: Removing and adding buffer seem to be as fast as trying to update it
	scene_wd.rd.free_rid(scene_wd.bvh_buffer)
	scene_wd.create_bvh_buffer()
	scene_wd.bind_set(scene_wd.BVH_SET_INDEX)


# CAN BE DEPRECATED
# We have function which takes in an array of indices that does the same
func update_bvh_nodes(ptscene : PTScene) -> void:
	if ptscene.bvh:
		for node in ptscene.bvh.updated_nodes:
			var scene_wd := get_scene_wd(ptscene)
			var bvh_bytes : PackedByteArray = node.to_byte_array()
			scene_wd.rd.buffer_update(
					scene_wd.bvh_buffer,
					ptscene.bvh.get_node_index(node)  * bvh_bytes.size(),
					bvh_bytes.size(),
					bvh_bytes
			)
	else:
		push_warning("PT: Cannot update BVH of scene with no BVH.")


## Will not update materials with index bigger than the scenes material buffer size
func update_material(ptscene : PTScene, material : PTMaterial) -> void:
	# Find right wd based on ptscene
	var scene_wd := get_scene_wd(ptscene)
	if scene_wd.material_buffer_size < ptscene.materials.size():
		push_error("PT: Cannot update material as index is out of range for buffer.")
		# If material is out of index do nothing
		return

	var buffer : RID = scene_wd.material_buffer
	var bytes : PackedByteArray = material.to_byte_array()
	var offset : int = ptscene.get_material_index(material) * bytes.size()
	scene_wd.rd.buffer_update(buffer, offset, bytes.size(), bytes)


## NOTE: This function is not optimized for moving many objects at the same time
func update_object(ptscene : PTScene, object : PTObject) -> void:
	"""Updates an individual object in the buffer"""

	# Find right wd based on ptscene
	var scene_wd := get_scene_wd(ptscene)

	# Update object buffer
	var buffer : RID = scene_wd.get_object_buffer(object.get_type())
	var bytes : PackedByteArray = object.to_byte_array()
	var offset : int = ptscene.get_object_index(object) * bytes.size()
	scene_wd.rd.buffer_update(buffer, offset, bytes.size(), bytes)

	# return early if object cannot be in bvh
	if object.get_type() in PTBVHTree.objects_to_exclude:
		return
	# TODO INvestigate if this function is complete


## NOTE: Optimizations can probably be made, i just remake buffers for simplicity
func remove_object(ptscene : PTScene, object : PTObject) -> void:
	# Find right wd based on ptscene
	var scene_wd := get_scene_wd(ptscene)

	# TODO just update object buffer nad no need to rebind uniform set
	scene_wd.create_object_buffer(object.get_type())

	scene_wd.bind_set(scene_wd.OBJECT_SET_INDEX)


## Removes objects from any queue in scenes
func _object_queue_remove() -> void:
	if scenes_to_remove_objects.is_empty() or _has_scenes_swapped:
		scenes_to_remove_objects.clear()
		return

	for ptscene in scenes_to_remove_objects:
		if not ptscene: # If scene is null; idk can prob remove
			push_warning("Help; Scene is no longer valid for deletion.")
			continue
		if ptscene.is_inside_tree() and ptscene.check_objects_for_removal():
			print("Removing objects from ", ptscene)
			ptscene.remove_objects()
		else:
			ptscene.objects_to_remove.clear()
			if is_debug:
				print("PT: Scene was changed, or the editor just started, " +
						"so no object removal will occur.")

	scenes_to_remove_objects.clear()


# TEMP FUCNTION
func _update(ptscene : PTScene, updated_object_ids : Array[int], updated_node_indices : Array[int]) -> void:
	var scene_wd := get_scene_wd(ptscene)

	scene_wd.check_object_buffer_size()
	if ptscene.bvh:
		print("excpanding bvh buffer")
		scene_wd.expand_bvh_buffer()

	_update_object_buffers(ptscene, updated_object_ids)
	_update_bvh_buffer(ptscene, updated_node_indices)


func _re_index_scenes() -> void:
	for ptscene in scenes:
		if ptscene._can_reindex:
			if is_debug:
				print("Re-indexing scene now. ", ptscene)
			ptscene._re_index()


func _update_object_buffers(ptscene : PTScene, updated_object_ids : Array[int]) -> void:
	var scene_wd := get_scene_wd(ptscene)

	for object_id in updated_object_ids:
		var type := PTObject.get_object_type_from_id(object_id)
		assert(type != PTObject.ObjectType.NOT_OBJECT,
				"Invalid object id type (NOT_OBJECT)")
		var index := PTObject.get_object_index_from_id(object_id)

		var buffer := scene_wd.get_object_buffer(type)

		var bytes : PackedByteArray
		# If index is out of range of objects, null out index
		if index >= ptscene.objects.get_object_array(type).size():
			bytes = PTObject.empty_object_bytes(type)
		else:
			@warning_ignore("unsafe_method_access")
			bytes = ptscene.objects.get_object_array(type)[index].to_byte_array()
		print(bytes)
		print(type)
		print(index)
		scene_wd.rd.buffer_update(buffer, index * bytes.size(), bytes.size(), bytes)


func _update_bvh_buffer(ptscene : PTScene, updated_node_indices : Array[int]) -> void:
	var scene_wd := get_scene_wd(ptscene)
	var buffer := scene_wd.bvh_buffer

	for node_index in updated_node_indices:

		var bytes : PackedByteArray
		# If index is out of range of objects, null out index
		if node_index >= ptscene.bvh.bvh_list.size():
			# Empy node
			bytes = PTObject.empty_byte_array(ptscene.bvh.node_byte_size())
		else:
			bytes = ptscene.bvh.bvh_list[node_index].to_byte_array()
		scene_wd.rd.buffer_update(buffer, node_index * bytes.size(), bytes.size(), bytes)
