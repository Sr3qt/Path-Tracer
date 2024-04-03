@tool
extends Node

class_name PTRenderer

# TODO This class probably fits well as a singleton, research how to do that
"""This node should be the root node of a scene with PTScene object added as a child.

This node has the responsibility to take render settings and pass them to 
a the correct PTWorkDispatcher, wich will actually make the gpu render an image.

"""

# Override for stopping rendering
@export var disable_rendering := false

# Whether this instance was created by a plugin script or not
var _is_plugin_instance = false
var root_node # Since the scene will become a subtree in the plugin, root_node
			  #  is a convenient pointer to the relative root node 

# Realtime PTWorkDispatcher
var rtwd : PTWorkDispatcher = null
#var nrtwd : PTWorkDispatcher

# Array of sub-windows
var windows : Array[PTDebugWindow] = []

# The mesh to draw to
var canvas : MeshInstance3D = null

var normal_camera : Camera3D = null

# A scene with objects and a camera node
var scene : PTScene

# GLSL files in shaders/procedural_textures folder
var procedural_textures = ["checker_board.comp"]

var proc_textures = {
	# The key is the name used in scene file, the first value is the shader name
	#  and the last value is the index used in the shader
	&"checker_board" : ["checker_board.comp", 1]
	
	}

var render_width := 1920
var render_height := 1080

var samples_per_pixel = 1
var max_default_depth = 8
var max_refraction_bounces = 8 

# Controls the degree of the bvh tree passed to the gpu. 
# NOTE: Currently no support for dynamically changing it. TODO
const bvh_max_children := 8

# NOTE: CPU control over gpu invocations has not been added. 
#	These are merely for reference
const compute_invocation_width := 8
const compute_invocation_height := 8
const compute_invocation_depth := 1


func _ready():
	if _is_plugin_instance:
		print("Plugin renderer _ready start")
		print(self)
	
	if not rtwd:
		rtwd = PTWorkDispatcher.new(self)
	
	if not Engine.is_editor_hint():
		# Apparently very import check for get_window (Otherwise the editor bugs out)
		get_window().position = Vector2(250, 400)

		# Find camera and canvas in children 
		for child in get_children():
			if child is Camera3D: # TODO more secure way of identifying camera and canvas
				normal_camera = child
			if child is MeshInstance3D:
				canvas = child

	# Only allow runtime and plugin instances to create child nodes
	if _is_plugin_instance or not Engine.is_editor_hint():
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
			
			# Create a canvas to which rendered images will be drawn
			canvas = MeshInstance3D.new()
			canvas.mesh = QuadMesh.new()
			canvas.mesh.size = Vector2(2, 2)
			canvas.mesh.surface_set_material(0, mat)
			add_child(canvas)
	
		scene = get_node("PTScene") # Is this the best way to get Scene node?

		scene.create_BVH(bvh_max_children)

		rtwd.set_scene(scene)

		load_shader()

		rtwd.create_buffers()
		
		#var x = ceil(1920. / 16.)
		var x = ceil(1920. / 8.)
		var y = ceil(1080. / 8.)
		
		var window1 = PTDebugWindow.new(x, y)
		var window2 = PTDebugWindow.new(x, y, 1, 1920 / 2)
		window2.show_bvh_depth = true
		#window1.show_bvh_depth = true
		
		window1.sample_all_textures = true
		
		add_window(window1)
		#add_window(window2)
	

func _process(delta):
	
	# Runtime and plugin requires different checks for window focus
	var runtime = (rtwd.is_rendering and get_window().has_focus() and 
					not Engine.is_editor_hint())
	var plugin = (_is_plugin_instance and (root_node and root_node.visible) and
					Engine.is_editor_hint())
					
	var common = ((scene and scene.camera.camera_changed) and not disable_rendering)
	
	if (runtime or plugin) and common:
		# TODO Make flag to allow for either multi sampling or not to save resources
		scene.camera.camera_changed = false
		
		if not Engine.is_editor_hint():
			scene.camera.camera_changed = true
		
		
		for window in windows:
			rtwd.create_compute_list(window)
		
		var mat = canvas.mesh.surface_get_material(0)
		mat.set_shader_parameter("is_rendering", true)
	#else:
		#var mat = canvas.mesh.surface_get_material(0)
		#mat.set_shader_parameter("is_rendering", false)


func _input(event):
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_X and not event.is_echo():
			# For some reason the editor can never get here
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
	

func add_window(window : PTDebugWindow):
	windows.append(window)
	
	# TODO add collision check with other windows and change their size accordingly

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
	#xxxxxxxxxxxxxxxxxxxxx
	var folder_path = "res://renders/temps/" + Time.get_date_string_from_system()
	
	# Make folder for today if it doesnt exist
	if not DirAccess.dir_exists_absolute(folder_path):
		DirAccess.make_dir_absolute(folder_path)
	
	new_image.save_png(folder_path + "/temp-" +
	Time.get_datetime_string_from_system().replace(":", "-") + ".png")

# TODO probably move to control node script
class PTDebugWindow:
	"""Class for showing gui and passing render flags for a smaller portion of 
	the render window"""
	
	# Defualt render flags
	var flags := 0
	# Whether a bvh tree should be used or 
	#  if every object should be checked for ray hit
	var use_bvh := true:
		set(value):
			flags = flags ^ (RenderFlagsBits.USE_BVH * int(value))
			use_bvh = value
	# If a bvh heat map of of most expensive traversals are shown
	var show_bvh_depth := false:
		set(value):
			flags = flags ^ (RenderFlagsBits.SHOW_BVH_DEPTH * int(value))
			show_bvh_depth = value
	# Whether the shader can make assume nothing has changed since last frame or not
	var scene_changed := true:
		set(value):
			flags = flags ^ (RenderFlagsBits.SCENE_CHANGED * int(value))
			scene_changed = value
	# Whether every object who is hit should sample their texture or not
	var sample_all_textures := false:
		set(value):
			flags = flags ^ (RenderFlagsBits.SAMPLE_ALL_TEXTURES * int(value))
			sample_all_textures = value
	
	# work_group_height and width are used for size calculations.
	#  depth is passed to work dispatcher, but no support for depth > 1 exist yet
	var work_group_width : int
	var work_group_height : int
	var work_group_depth := 1
	
	var x_offset := 0
	var y_offset := 0
	
	enum RenderFlagsBits {
		USE_BVH = 1,
		SHOW_BVH_DEPTH = 2,
		SCENE_CHANGED = 4,
		SAMPLE_ALL_TEXTURES = 8
	}
	
	
	func _init(group_x := 1, group_y := 1, group_z := 1, offset_x := 0, offset_y := 0):
		_set_flags()
		
		work_group_width = group_x
		work_group_height = group_y
		work_group_depth = group_z
		
		x_offset = offset_x
		y_offset = offset_y
	
	
	func _set_flags():
		"""Used once for init"""
		flags = (
			RenderFlagsBits.USE_BVH * int(use_bvh) +
			RenderFlagsBits.SHOW_BVH_DEPTH * int(show_bvh_depth) +
			RenderFlagsBits.SCENE_CHANGED * int(scene_changed) +
			RenderFlagsBits.SAMPLE_ALL_TEXTURES * int(sample_all_textures)
		)
	
	
	func flags_to_byte_array():
		var flag_array = PackedInt32Array([flags])
		return flag_array.to_byte_array()
