@tool
class_name PTRenderer
extends Node

"""This node is a Singleton with the responsibility of rendering the current scene.

PTScenes will add themselves to this Singleton. The user can ask PTRenderer
to swap scenes.

"""

const WindowGui := preload("res://ui_scenes/render_window_gui/render_window_gui.tscn")

# NOTE: CPU control over gpu invocations has not been added.
#	These are merely for reference
const compute_invocation_width : int = 8
const compute_invocation_height : int = 8
const compute_invocation_depth : int = 1

## General override for stopping rendering. When enabled no work will be pushed to the
##  GPU and the screen will be white.
@export var is_rendering_disabled := false:
	set(value):
		is_rendering_disabled = value
		_set_canvas_visibility()

## Override for stopping rendering. Specifically for when no scene is present.
var no_scene_is_active := true:
	set(value):
		no_scene_is_active = value
		_set_canvas_visibility()

var no_camera_is_active := true:
	set(value):
		no_camera_is_active = value
		_set_canvas_visibility()

func _set_canvas_visibility() -> void:
	if canvas:
		var is_rendering := (not is_rendering_disabled and not no_scene_is_active
				and not no_camera_is_active)
		var mat : ShaderMaterial = canvas.mesh.surface_get_material(0)
		mat.set_shader_parameter("is_rendering", is_rendering)
		canvas.visible = is_rendering

var wd : PTWorkDispatcher # Current PTWorkDispatcher for the current scene
## Uses same indexing as scenes
var wds : Array[PTWorkDispatcher] # An array of WorkDispatchers for each scene

var scene : PTScene # The scene currently in use
## Uses same indexing as wds
var scenes : Array[PTScene] # An array of scenes. Primarily used by plugin

# A dicitionary that keeps track of multiple PTScenes within one Godot scene.
# Only used by plugin, for runtime scene tracker see scene_to_scene_index
var root_node_to_scene := {
	## Example:
	# root_node : {
	#	"last_index" : 1 # This is an index to this sublist, ptscene1
	#	"scenes" : [ptscene0, ptscene1] # Array of PTScenes within root_node scene
	# }
}

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
var bvh_max_children : int = 8

# TODO Make render settings node similar to WorldEnvironment
var render_width := 1920
var render_height := 1080

var samples_per_pixel : int = 1 # DEPRECATED REMOVE
@export var max_default_depth : int = 8
@export var max_refraction_bounces : int = 8

# Whether anything was rendered in the last render_window call. Only used by plugin
var was_rendered := false

var startup_time : int = 0

# Array of scenes that wants one or more of their objects to be removed from buffers.
# NOTE: Scenes add themselves.
var scenes_to_remove_objects : Array[PTScene]

var screenshot_folder := "res://renders/temps/" + Time.get_date_string_from_system() + "/"


func _init() -> void:
	print("Renderer init time: ", (Time.get_ticks_usec()) / 1000., "ms ")


func _ready() -> void:
	startup_time = Time.get_ticks_usec()

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
	# TODO Fix stutter issue
	if startup_time:
		print()
		print("Total startup time")
		print((Time.get_ticks_usec()) / 1000., "ms ")
		#print((Time.get_ticks_usec() - startup_time) / 1000., "ms ")
		startup_time = 0
	was_rendered = false

	_object_queue_remove()

	# If editor camera moved, copy the data to scene.camera
	if Engine.is_editor_hint() and editor_camera and is_camera_linked:
		if (not (editor_camera.position == _pt_editor_camera.position and
				editor_camera.transform == _pt_editor_camera.transform)):
			copy_camera(editor_camera, _pt_editor_camera)

	## Decides if any rendering will be done at all
	# Runtime and plugin requires different checks for window focus
	var runtime := (get_window().has_focus() and not Engine.is_editor_hint())
	var plugin := (Engine.is_editor_hint())

	var common := (not is_rendering_disabled and not no_scene_is_active and
			not no_camera_is_active)

	if (runtime or plugin) and common:
		## Double check everything with warnings
		if not scene:
			# TODO Add path to where warning came from ?
			raise_error("No scene has been set.\n" +
					"Rendering is therefore temporarily disabled.")
			no_scene_is_active = true

		elif not scene.camera and not Engine.is_editor_hint():
			# TODO ADD Reporting node configuration warnings
			# https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html
			raise_error("No camera has been set in current scene.\n" +
					"Rendering is therefore temporarily disabled.")
			no_camera_is_active = true

		common = (not is_rendering_disabled and not no_scene_is_active and
				not no_camera_is_active)
		if common:
			# If no warnings are raised, this will render
			for window in windows:
				render_window(window)

			# NOTE: For some reason this is neccessary for smooth performance in editor
			if Engine.is_editor_hint() and was_rendered:
				var mat := canvas.mesh.surface_get_material(0) as ShaderMaterial
				mat.set_shader_parameter("is_rendering", true)

	# Re-create buffers if asked for
	for _scene in scenes:
		if _scene and _scene.added_object:
			remake_buffers(_scene)

			if _scene.procedural_texture_added:
				var _scene_wd : PTWorkDispatcher = wds[scene_to_scene_index[_scene]]
				_scene_wd.load_shader(load_shader(_scene))
				print("Reloaded shader")
				_scene.procedural_texture_added = false

			_scene.added_object = false

	# Reset frame values
	if scene:
		scene.scene_changed = false
		if scene.camera:
			scene.camera.camera_changed = false

	if Engine.is_editor_hint():
		_pt_editor_camera.camera_changed = false


# TODO Remove input event?
func _input(event : InputEvent) -> void:
	if not Engine.is_editor_hint():
		if event is InputEventKey:
			if ((event as InputEventKey).pressed and
				(event as InputEventKey).keycode == KEY_X and
				not event.is_echo()):
				take_screenshot()

	# TODO MAke able to take images with long render time with loading bar
	#  Long term goal, maybe


func _exit_tree() -> void:
	for _wd in wds:
		_wd.free_RIDs()


## It is plugin_control_root's responsibility to call this function
func _set_plugin_camera(cam : PTCamera) -> void:
	if not canvas:
		canvas = create_canvas()

	no_camera_is_active = false
	_pt_editor_camera = cam
	_pt_editor_camera.add_child(canvas)


func raise_error(msg : String) -> void:
	var prepend := "PT"
	if Engine.is_editor_hint():
		prepend += " Plugin"

	msg = prepend + ": " + msg

	push_error(msg)


# TODO Move to a preprocessor script ?
func load_shader(ptscene : PTScene) -> RDShaderSource:
	var file := FileAccess.open("res://shaders/ray_tracer.comp",
		FileAccess.READ_WRITE)
	var res := file.get_as_text()
	file.close()

	# Do changes
	# Change BVH tree degree
	res = res.replace("const int max_children = 2;",
	"const int max_children = %s;" % bvh_max_children)

	# Insert procedural texture functions
	const DEFUALT_FUNCTION_NAME = "procedural_texture"
	const BASE_FUNCTION_NAME = "_procedural_texture_function"

	var i : int = 1
	var function_definitons := ""
	var function_calls := ""
	for _texture in ptscene.textures:
		if not _texture is PTProceduralTexture:
			continue
		var texture := _texture as PTProceduralTexture
		var path : String = texture.texture_path
		var tex_file := FileAccess.open(path, FileAccess.READ_WRITE)
		if not tex_file:
			push_error("PT: No procedural texture file found: " +
					texture.texture_path + " in " + path)
		var text := tex_file.get_as_text()

		var function_index : int = text.find(DEFUALT_FUNCTION_NAME)
		if function_index == -1:
			push_error("PT: No procedural texture function found in file: " +
					texture.texture_path + " in " + path)

		text = text.replace(DEFUALT_FUNCTION_NAME, BASE_FUNCTION_NAME + str(i))

		function_calls += (
			"else if (function == %s) {\n" % i + "		return " +
			BASE_FUNCTION_NAME + str(i) + "(pos);\n	}\n	"
		)

		function_definitons += text
		i += 1

	# Inserts function definitions
	res = res.replace("//procedural_texture_function_definition_hook",
			function_definitons)

	# Inserts function calls
	res = res.replace("//procedural_texture_function_call_hook", function_calls)

	# Set shader
	var shader := RDShaderSource.new()
	shader.source_compute = res

	return shader


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


func add_scene(new_ptscene : PTScene) -> void:
	"""Adds a scene to renderer"""

	# Maybe redundant check
	if new_ptscene == null:
		push_warning("PT: Tried to add null scene.")
		return

	# If in editor, add translation layer from ptscenes owner to ptscene
	if Engine.is_editor_hint():
		if not new_ptscene.owner:
			var max_count : int = 100
			var counter : int = 0
			var current_node : Node = new_ptscene.get_parent()
			while counter < max_count and current_node and not root_node_to_scene.has(current_node):
				current_node = current_node.get_parent()
				counter += 1

			if counter < max_count and current_node:
				# current_node is new_ptscene.owner
				print("owner found! ", current_node)
				@warning_ignore("unsafe_method_access")
				new_ptscene.owner = current_node
				root_node_to_scene[current_node]["scenes"].append(new_ptscene) # UNSTATIC
			else:
				# new_ptscene is the root node of an unseen scene
				root_node_to_scene[new_ptscene] = { # UNSTATIC
						"last_index" : 0,
						"scenes" : [new_ptscene]
				}
		# If root_node already has a ptscene associated with it
		elif root_node_to_scene.has(new_ptscene.owner):
				@warning_ignore("unsafe_method_access")
				root_node_to_scene[new_ptscene.owner]["scenes"].append(new_ptscene) # UNSTATIC
		else:
			# new_ptscene is a child of an unseen scene
			root_node_to_scene[new_ptscene.owner] = { # UNSTATIC
					"last_index" : 0,
					"scenes" : [new_ptscene]
			}

	scene_to_scene_index[new_ptscene] = scenes.size() # UNSTATIC
	scenes.append(new_ptscene)

	print()
	print((Time.get_ticks_usec()) / 1000., "ms ")
	print(new_ptscene.owner, " Root node")
	print(new_ptscene, " PTScene node")
	print()

	if new_ptscene.object_count > 0:
		var function_name : String = PTBVHTree.enum_to_dict[new_ptscene.default_bvh] # UNSTATIC
		new_ptscene.create_BVH(bvh_max_children, function_name)

	if not canvas:
		canvas = create_canvas()

	# Create new WD
	var new_wd := PTWorkDispatcher.new(self)
	new_wd.set_scene(new_ptscene)
	new_wd.load_shader(load_shader(new_ptscene))
	new_wd.create_buffers()

	wds.append(new_wd)

	# Set new_ptscene to scene if no scene was previously active and is in runtime
	if not Engine.is_editor_hint() and no_scene_is_active:
		change_scene(new_ptscene)


func _plugin_scene_closed(scene_path : String) -> void:
	for node : Node in root_node_to_scene.keys():
		if node.scene_file_path == scene_path:
			for _scene : PTScene in root_node_to_scene[node]["scenes"].duplicate():
				print("Closing scene: ")
				printraw(_scene)
				remove_scene(_scene)


func remove_scene(ptscene : PTScene) -> void:
	# Remove all references to ptscene
	var index := scenes.find(ptscene)
	if index != -1:
		var _scene_wd := wds[index] # Remove var eventually
		scenes.remove_at(index)
		wds.remove_at(index)
		_scene_wd.queue_free()

	# if running in editor, try to cleanup root_node_to_scene
	print(root_node_to_scene)
	if Engine.is_editor_hint() and not root_node_to_scene.erase(ptscene):
		# TODO Remove scene from root_node_to_scene when scene is deleted
		# If ptscene is a reference under any other root nodes
		for key : Node in root_node_to_scene.keys():
			var value = root_node_to_scene[key]
			var _index : int = value["scenes"].find(ptscene)
			if _index == -1:
				continue

			value["scenes"].remove_at(_index)

			if value["scenes"].is_empty():
				root_node_to_scene.erase(key)
			elif value["last_index"] == _index:
				root_node_to_scene[key]["last_index"] = 0
	print(root_node_to_scene)

	scene_to_scene_index.erase(ptscene)
	scenes_to_remove_objects.erase(ptscene)

	if ptscene == scene:
		scene = null
		wd = null
		no_scene_is_active = true


## Wrapper function for the plugin to change scenes
func _plugin_change_scene(scene_root : Node) -> void:
	if scene_root == null or not root_node_to_scene.has(scene_root):
		# scene_root is a new empty node or a root without a PTScene in the scene
		scene = null
		wd = null
		no_scene_is_active = true
		return

	var temp_dict : Dictionary = root_node_to_scene[scene_root]  # UNSTATIC

	var scene_to_change : PTScene = temp_dict["scenes"][temp_dict["last_index"]]  # UNSTATIC

	change_scene(scene_to_change)


func change_scene(new_scene : PTScene) -> void:

	# Remove (and later add) canvas from camera in runtime
	if not Engine.is_editor_hint():
		if scene and scene.camera:
			scene.camera.remove_child(canvas)

	var scene_index : int = scene_to_scene_index[new_scene]  # UNSTATIC
	scene = scenes[scene_index]
	wd = wds[scene_index]
	# Change buffer displayed on canvas
	wd.texture.texture_rd_rid = wd.image_buffer

	no_scene_is_active = false

	if not Engine.is_editor_hint():
		if scene.camera:
			no_camera_is_active = false
			scene.camera.add_child(canvas)

	# TODO Update GUI values


func add_scene_to_remove_objects(ptscene : PTScene) -> void:
	if not ptscene in scenes_to_remove_objects:
		scenes_to_remove_objects.append(ptscene)


## Removes objects from any queue in scenes
func _object_queue_remove() -> void:
	for _scene in scenes_to_remove_objects:
		if not _scene: # If scene is null; idk can prob remove
			push_warning("Help; Scene is no longer valid for deletion.")
			continue
		if _scene.is_inside_tree() and _scene.check_objects_for_removal():
			print("PT: Removing object(s) that was deleted by the user.")
			_scene.remove_objects()
		else:
			_scene.objects_to_remove.clear()
			print("PT: Scene was changed, or the editor just started," +
					"so no object removal will occur.")

	scenes_to_remove_objects.clear()


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


func create_bvh(_max_children : int, function_name : String) -> void:
	# TODO Rework shader to work with different bvh orders without reloading
	#var _start = Time.get_ticks_usec()

	# TODO Add support so that all objects in scene can be rendered by bvh
	#  THis is a bug because the shader has a fixed stack size and cannot always
	#  accommodate for every object count and bvh order
	var prev_max : int = bvh_max_children
	bvh_max_children = _max_children

	scene.create_BVH(bvh_max_children, function_name)
	scene.scene_changed = true

	if prev_max != bvh_max_children:
		load_shader(scene)

	# NOTE: Removing and adding buffer seem to be as fast as trying to update it
	wd.rd.free_rid(wd.BVH_buffer)

	wd.create_bvh_buffer()

	var BVH_uniforms : Array[RDUniform] = wd.uniforms.get_set_uniforms(wd.BVH_SET_INDEX)
	wd.BVH_set = wd.rd.uniform_set_create(BVH_uniforms, wd.shader,
			wd.BVH_SET_INDEX)

	#print((Time.get_ticks_usec() - _start) / 1000.)


func update_material(_scene : PTScene, material : PTMaterial) -> void:
	# Find right wd based on _scene
	var scene_wd : PTWorkDispatcher = wds[scene_to_scene_index[_scene]]
	var buffer : RID = scene_wd.material_buffer

	var bytes : PackedByteArray = material.to_byte_array()
	var offset : int = _scene.material_to_index[material] * bytes.size() # UNSTATIC
	scene_wd.rd.buffer_update(
			buffer,
			offset,
			bytes.size(),
			bytes
	)


## NOTE: This function is not optimized for moving many objects at the same time
func update_object(_scene : PTScene, object : PTObject) -> void:
	"""Updates an individual object in the buffer"""

	# Find right wd based on _scene
	var scene_wd : PTWorkDispatcher = wds[scene_to_scene_index[_scene]]

	# Update object buffer
	var buffer : RID
	match object.get_type():
		PTObject.ObjectType.SPHERE:
			buffer = scene_wd.sphere_buffer

		PTObject.ObjectType.PLANE:
			buffer = scene_wd.plane_buffer

		PTObject.ObjectType.TRIANGLE:
			buffer = scene_wd.triangle_buffer

	var obj_bytes : PackedByteArray = object.to_byte_array()
	scene_wd.rd.buffer_update(
			buffer,
			object.object_index * obj_bytes.size(),
			obj_bytes.size(),
			obj_bytes
	)

	# return early if object cannot be in bvh
	if not PTBVHTree.objects_to_include.has(object.get_type()):
		return

	# Update BVH buffer if applicable
	if _scene.bvh:
		for node in _scene.bvh.updated_nodes:
			var bvh_bytes : PackedByteArray = node.to_byte_array()
			scene_wd.rd.buffer_update(
					scene_wd.BVH_buffer,
					node.index * bvh_bytes.size(),
					bvh_bytes.size(),
					bvh_bytes
			)

## NOTE: Optimizations can probably be made, i just remake buffers for simplicity
func remove_object(_scene : PTScene, object : PTObject) -> void:
	# Find right wd based on _scene
	var scene_wd : PTWorkDispatcher = wds[scene_to_scene_index[_scene]]

	# Update object buffer
	match object.get_type():
		PTObject.ObjectType.SPHERE:
			scene_wd.create_sphere_buffer()
		PTObject.ObjectType.PLANE:
			scene_wd.create_plane_buffer()
		PTObject.ObjectType.TRIANGLE:
			scene_wd.create_triangle_buffer()

	# Update bvh if possible
	if _scene.bvh:
		for node in _scene.bvh.updated_nodes:
			var bvh_bytes : PackedByteArray = node.to_byte_array()
			scene_wd.rd.buffer_update(
					scene_wd.BVH_buffer,
					node.index * bvh_bytes.size(),
					bvh_bytes.size(),
					bvh_bytes
			)

	# NOTE: A bit overkill, but dont care
	scene_wd.bind_sets()


func copy_camera(from : Camera3D, to : Camera3D) -> void:
	to.translate(to.position - from.position)

	to.transform = from.transform
	to.fov = from.fov

	if to is PTCamera:
		(to as PTCamera).set_viewport_size()


func remake_buffers(_scene : PTScene) -> void:
	var _wd : PTWorkDispatcher = wds[scene_to_scene_index[_scene]]
	var buffers : Array[PTObject.ObjectType] = []
	print()
	print("Expanding object buffers for ", _scene, ":")
	@warning_ignore("untyped_declaration")
	for type : int in PTObject.ObjectType.values():
		if _scene.added_types[type]:
			_scene.added_types[type] = false
			buffers.append(type)
	wd.expand_object_buffers(buffers)

	# Check for proceduaral texture updates
	#if _scene.added_types[PTObject.ObjectType.MAX + 1]:

	_scene.added_object = false



