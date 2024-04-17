@tool
class_name PTRenderer
extends Node

# TODO This class probably fits well as a singleton, research how to do that
"""This node should be the root node of a scene with PTScene object added as a child.

This node has the responsibility to take render settings and pass them to 
a the correct PTWorkDispatcher, wich will actually make the gpu render an image.

"""

const WindowGui = preload("res://ui_scenes/render_window_gui/render_window_gui.tscn")

# NOTE: CPU control over gpu invocations has not been added. 
#	These are merely for reference
const compute_invocation_width : int = 8
const compute_invocation_height : int = 8
const compute_invocation_depth : int = 1

## Override for stopping rendering. When enabled no work will be pushed to the 
##  GPU the screen will be white.
@export var is_rendering_disabled := false:
	set(value):
		if canvas:
			var mat = canvas.mesh.surface_get_material(0)
			mat.set_shader_parameter("is_rendering", not value)
		is_rendering_disabled = value

## The BVH type created on startup
@export var default_bvh : PTBVHTree.BVHType = PTBVHTree.BVHType.X_SORTED

# Since the scene will become a subtree in the plugin, 
#  root_node is a convenient pointer to the relative root node 
var root_node 

# Realtime PTWorkDispatcher
var rtwd : PTWorkDispatcher
# TODO Have a PTWorkDispatcher for every scene that can be rendered,
#  especially thinking about plugin being able to render current scene
#var nrtwd : PTWorkDispatcher

# Array of sub-windows
var windows : Array[PTRenderWindow] = []

# The mesh to draw to
var canvas : MeshInstance3D

var normal_camera : Camera3D

# A scene with objects and a camera node
var scene : PTScene

# Controls the degree of the bvh tree passed to the gpu. 
var bvh_max_children : int = 8

# GLSL files in shaders/procedural_textures folder
var procedural_textures = ["checker_board.comp"]

var proc_textures = {
	# The key is the name used in scene file, the first value is the shader name
	#  and the last value is the index used in the shader
	&"checker_board" : ["checker_board.comp", 1]
	
	}

var render_width := 1920
var render_height := 1080

var samples_per_pixel = 1 # Deprecated
var max_default_depth = 8
var max_refraction_bounces = 8 

# Whether this instance was created by a plugin script or not. Only used by plugin
var _is_plugin_instance := false

# If mouse is hovering over the render window. Only used by plugin
var _mouse_hover_window := false

# Whether anything was rendered in the last render_window call. Only used by plugin
var _was_rendered := false


func _ready():
	if _is_plugin_instance:
		print("Plugin renderer _ready start")
		print(self)
	
	if not Engine.is_editor_hint():
		# Apparently very import check for get_window (Otherwise the editor bugs out)
		get_window().position -= Vector2i(450, 100)

		# Might not be needed
		# Find camera and canvas in children 
		for child in get_children():
			if child is Camera3D: # TODO more secure way of identifying camera and canvas
				normal_camera = child
			if child is MeshInstance3D:
				canvas = child

	# Only allow runtime and plugin instances to create child nodes
	if not Engine.is_editor_hint() or _is_plugin_instance:
		if not rtwd:
			rtwd = PTWorkDispatcher.new(self)
		
		if not normal_camera:
			# Create godot camera to observe canvas
			normal_camera = Camera3D.new()
			normal_camera.position += Vector3(0,0,1)
			add_child(normal_camera)

		if not canvas:
			# Prepare canvas shader
			var mat = ShaderMaterial.new()
			mat.shader = load("res://shaders/canvas.gdshader")
			mat.set_shader_parameter("image_buffer", Texture2DRD.new())
			mat.set_shader_parameter("is_rendering", not is_rendering_disabled)
			
			# Create a canvas to which rendered images will be drawn
			canvas = MeshInstance3D.new()
			canvas.mesh = QuadMesh.new()
			canvas.mesh.size = Vector2(2, 2)
			canvas.mesh.surface_set_material(0, mat)
			add_child(canvas)
	
		scene = get_node("PTScene") # Is this the best way to get Scene node?
		
		var function_name = PTBVHTree.enum_to_dict[default_bvh]
		scene.create_BVH(bvh_max_children, function_name)

		rtwd.set_scene(scene)

		load_shader()

		rtwd.create_buffers()
		
		# TODO Add support for multiple PTRenderWindows on screen
		#  as well as support for a seperate bvh for each of them.
		
		#var x = ceil(1920. / 16.)
		var x = ceili(1920. / 8.)
		var y = ceili(1080. / 8.)
		
		var better_window = WindowGui.instantiate()
		
		if not Engine.is_editor_hint():
			better_window.max_samples = 256
		
		better_window.work_group_width = x
		better_window.work_group_height = y
		
		add_window(better_window)


func _process(delta):
	_was_rendered = false
	
	## Decides if any rendering will be done at all
	# Runtime and plugin requires different checks for window focus
	var runtime = (get_window().has_focus() and not Engine.is_editor_hint())
	var plugin = (_is_plugin_instance and (root_node and root_node.visible) and
					Engine.is_editor_hint())
	
	var common = not is_rendering_disabled
	
	if (runtime or plugin) and common:
		for window in windows:
			render_window(window)
		
		# Reset frame values
		scene.scene_changed = false
		scene.camera.camera_changed = false
		
		# NOTE: For some reason this is neccessary for smooth performance in editor
		if Engine.is_editor_hint() and (_mouse_hover_window or _was_rendered):
			var mat = canvas.mesh.surface_get_material(0)
			mat.set_shader_parameter("is_rendering", true)


func _input(event):
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_X and not event.is_echo():
			# TODO For some reason the editor can never get here
			save_framebuffer(rtwd)
	
	# Taken from work_dispatcher, TODO implement picture taking functionality
	## TODO: Make loading bar
	## TODO: MAke able to take images with long render time
	## Takes picture
	#if Input.is_key_pressed(KEY_X) and not is_taking_picture:
		## Make last changes to camera settings
		#samples_per_pixel = 80
		#max_default_depth = 16
		#max_refraction_bounces = 16
		#rd.buffer_update(LOD_buffer, 0, _lod_byte_array().size(), _lod_byte_array())
		#
		### Currently disabled
		##is_taking_picture = true
		##is_rendering = false
		#_image_render_start = Time.get_ticks_msec()
		#
	## Don't send work when window is not focused
	#if get_window() != null: # For some reason get_window can return null
		#if get_window().has_focus() and is_rendering:
			#create_compute_list()
		#
	#if is_taking_picture:
		#render_image()

func _exit_tree():
	if not Engine.is_editor_hint():
		
		var image = rtwd.rd.texture_get_data(rtwd.image_buffer, 0)
		# Changing the renderer render size should always create a new buffer, so
		#  this code should always yield a correct result
		var new_image = Image.create_from_data(
			render_width, 
			render_height, 
			false,
			Image.FORMAT_RGBAF, 
			image
		)
		new_image.save_png("temps/temp.png")
		
		rtwd.free_RIDs()
	
	if _is_plugin_instance:
		rtwd.free_RIDs()


func load_shader():
	var file := FileAccess.open("res://shaders/ray_tracer.comp", 
		FileAccess.READ_WRITE)
	var res = file.get_as_text()
	file.close()
	
	# Do changes
	# Change BVH tree degree
	res = res.replace("const int max_children = 2;", 
	"const int max_children = %s;" % bvh_max_children)

	# Insert procedural texture functions
	var default_function_name = "procedural_texture"
	var base_function_name = "procedural_texture_function"
	
	var i = 1
	var function_definitons = ""
	var function_calls = ""
	for filename in procedural_textures:
		var path = "res://shaders/procedural_textures/" + filename
		var tex_file := FileAccess.open(path, FileAccess.READ_WRITE)
		var text = tex_file.get_as_text()
		
		var function_index = text.find(default_function_name)
		if function_index == -1:
			# TODO add warning
			print("No procedural texture found in file: " + filename)
		
		text = text.replace(default_function_name, base_function_name + str(i))
		
		function_calls += (
			"else if (function == %s) {\n" % i + "		return " +
			base_function_name + str(i) + "(pos);\n	}\n	"
		)
		
		function_definitons += text
	
	# Inserts function definitions
	res = res.replace("//procedural_texture_function_definition_hook", function_definitons)
	
	# Inserts function calls
	res = res.replace("//procedural_texture_function_call_hook", function_calls)
	
	# Set shader
	var shader = RDShaderSource.new()
	shader.source_compute = res
	
	rtwd.load_shader(shader)
	

func add_window(window : PTRenderWindow):
	window._renderer = self
	windows.append(window)
	
	if not Engine.is_editor_hint():
		add_child(window)
	else:
		# This was the easiest way to give the window input events
		get_parent().get_parent().add_child.call_deferred(window)
	
	# TODO add collision check with other windows and change their size accordingly


func render_window(window : PTRenderWindow):
	"""Might render window according to flags if flags allow it"""
	
	# If camera moved or scene changed
	var movement = scene and (scene.camera.camera_changed or scene.scene_changed)
	
	# If rendering should stop when reached max samples
	var stop_multisampling = (
			window.stop_rendering_on_max_samples and
			(window.frame >= window.max_samples)
	)
	
	var multisample = (window.enable_multisampling and not stop_multisampling and
			not window._disable_multisample)
	
	# Adds the time of the last frame rendered
	if window.frame == window.max_samples and multisample and window._was_rendered:
		window.frame_times += (
				Time.get_ticks_usec() - window._max_sample_start_time
		) / 1_000_000.0
	
	if movement or multisample or window.render_mode_changed:
		window.scene_changed = movement
		
		# Adds the time taken since last frame render started
		if window.frame < window.max_samples and multisample and window._was_rendered:
			window.frame_times += (
					Time.get_ticks_usec() - window._max_sample_start_time
			) / 1_000_000.0
			
		# If frame is above limit or a scene/camera/flag change caused a reset
		if window.frame > window.max_samples or movement or window.render_mode_changed:
			window.frame = 0
		
		if window.frame == 0:
			window.frame_times = 0
		
		window._max_sample_start_time = Time.get_ticks_usec()
		
		#Render
		rtwd.create_compute_list(window)
		
		window.frame += 1
		
		# Reset frame values
		window.scene_changed = false
		window.render_mode_changed = false
		
		window._was_rendered = true
		_was_rendered = true
		
	else:
		window._was_rendered = false
		
		
		

func save_framebuffer(work_dispatcher : PTWorkDispatcher):
	if Engine.is_editor_hint():
		if (scene and not scene.camera.freeze):
			print("Taking pictures in the editor is not currently supported.")
		return
		
	var image = work_dispatcher.rd.texture_get_data(work_dispatcher.image_buffer, 0)
	# Changing the renderer render size should always create a new buffer, so
	#  this code should always yield a correct result
	var new_image = Image.create_from_data(
		render_width, 
		render_height, 
		false,
		Image.FORMAT_RGBAF, 
		image
	)
	
	var folder_path = "res://renders/temps/" + Time.get_date_string_from_system()
	
	# Make folder for today if it doesnt exist
	if not DirAccess.dir_exists_absolute(folder_path):
		DirAccess.make_dir_absolute(folder_path)
	
	new_image.save_png(folder_path + "/temp-" +
	Time.get_datetime_string_from_system().replace(":", "-") + ".png")


func create_bvh(_max_children : int, function_name : String):
	# TODO Rework shader to work with different bvh orders without reloading
	#var _start = Time.get_ticks_usec()
	
	# TODO Add support so that all objects in scene can be rendered by bvh
	#  THis is a bug because the shader has a fixed stack size and cannot always
	#  accommodate for every object count and bvh order
	var prev_max = bvh_max_children
	bvh_max_children = _max_children
	
	scene.create_BVH(bvh_max_children, function_name)
	scene.scene_changed = true
	
	if prev_max != bvh_max_children:
		load_shader()
	
	# NOTE: Removing and adding buffer seem to be as fast as trying to update it
	rtwd.rd.free_rid(rtwd.BVH_buffer)
	
	rtwd.create_bvh_buffer()
	
	var BVH_uniforms = rtwd.uniform_sets[rtwd.BVH_set_index].values()
	rtwd.BVH_set = rtwd.rd.uniform_set_create(BVH_uniforms, rtwd.shader, 
			rtwd.BVH_set_index)
			
	#print((Time.get_ticks_usec() - _start) / 1000.)
	

