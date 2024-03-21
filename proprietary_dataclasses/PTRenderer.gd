@tool
extends Node


class_name PTRenderer

"""This node should be the root node of a scene with PTScene object added as a child.

This node has the responsibility to take render settings and pass them to 
a the correct PTWorkDispatcher, wich will actually make the gpu render an image.


TODO: Add way to change certain values in shader programatically, like 
BVH max child count or image buffer being readonly.
"""

@export var run_as_tool := false

# Whether this instance was created by a plugin script or not
var is_plugin_instance = false

# Realtime PTWorkDispatcher
var rtwd : PTWorkDispatcher = null
#var nrtwd : PTWorkDispatcher

# The mesh to draw to
var canvas : MeshInstance3D = null

var normal_camera : Camera3D = null

var render_height := 1920
var render_width := 1080

# A scene with objects and a camera node
var scene : PTScene

var bvh_max_children := 8

# Render Flags
# TODO: Make flag object which can be instantiated and keeps track of its own flags
var flags := 0
var use_bvh := true
var show_bvh_depth := !false
var scene_changed := true

enum RenderFlagsBits {
	USE_BVH = 1,
	SHOW_BVH_DEPTH = 2,
	SCENE_CHANGED = 4}

func _enter_tree():
	if not Engine.is_editor_hint():
		pass


func _ready():
	if get_parent() is Control:
		is_plugin_instance = true
	
	print("PTRENDER readyh")
	print(self)
	if is_plugin_instance:
		print("THere can only be one")
	
	if not rtwd:
		rtwd = PTWorkDispatcher.new(self)
		
	
	# Apparently very import check (Otherwise the editor bugs out)
	if not Engine.is_editor_hint():
		get_window().position = Vector2(1250, 400)
	
	# Set initial flags
	flags = (
		RenderFlagsBits.USE_BVH * int(use_bvh) +
		RenderFlagsBits.SHOW_BVH_DEPTH * int(show_bvh_depth) +
		RenderFlagsBits.SCENE_CHANGED * int(scene_changed)
	)

	# Find camera and canvas in children 
	for child in get_children():
		if child is Camera3D: # TODO more secure way of identifying camera and canvas
			normal_camera = child
		if child is MeshInstance3D:
			canvas = child

	# Only allow runtime and plugin instances to create child nodes
	if is_plugin_instance or not Engine.is_editor_hint():
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
	
	if not Engine.is_editor_hint():
			

		scene = get_node("PTScene") # Is this the best way to get Scene node?

		scene.create_BVH(bvh_max_children)

		rtwd.set_scene(scene)

		load_shader()

		rtwd.create_buffers()
	

func _process(delta):
	#rtwd._process(delta)
	
	if rtwd.is_rendering and get_window().has_focus() and not Engine.is_editor_hint():
		# TEMP
		var x = ceil(1920. / 16.)
		var y = ceil(1080. / 8.)
		
		show_bvh_depth = false
		create_compute_list(x, y, 1, 0, 0)
		
		show_bvh_depth = true
		create_compute_list(x, y, 1, 1920 / 2, 0)
		
		#rtwd.create_compute_list()
		var mat = canvas.mesh.surface_get_material(0)
		mat.set_shader_parameter("is_rendering", true)
	#else:
		#var mat = canvas.mesh.surface_get_material(0)
		#mat.set_shader_parameter("is_rendering", false)


func create_compute_list(x := 0, y := 0, z := 0, x_offset := 0, y_offset := 0):
	"""Wrapper function for rtwd.create_compute_list"""
	set_flags()
	rtwd.create_compute_list(x, y, z, x_offset, y_offset)

func load_shader():
	var file := FileAccess.open("res://shaders/ray_tracer.comp", 
	FileAccess.READ_WRITE)
	var text = file.get_as_text()
	file.close()
	
	# Do changes
	text = text.replace("const int max_children = 2;", 
	"const int max_children = %s;" % bvh_max_children)

	# Set shader
	var shader = RDShaderSource.new()
	shader.source_compute = text
	
	rtwd.load_shader(shader)
	

func set_flags():
	""""""
	flags = (
		RenderFlagsBits.USE_BVH * int(use_bvh) +
		RenderFlagsBits.SHOW_BVH_DEPTH * int(show_bvh_depth) +
		RenderFlagsBits.SCENE_CHANGED * int(scene_changed)
	)
	

func flags_to_byte_array():
	var flag_array = PackedInt32Array([use_bvh, show_bvh_depth, scene_changed])
	return flag_array.to_byte_array()


class PTDebugWindow:
	"""Class for showing gui and passing render flags for a smaller portion of 
	the render window"""
	
	# Render Flags
	var flags := 0
	var use_bvh := true
	var show_bvh_depth := false
	var scene_changed := true
	
	var work_group_width : int
	var work_group_height : int
	
	var x_offset : int
	var y_offset : int
	
	func _init():
		set_flags()
		
	func set_flags():
		""""""
		flags = (
			RenderFlagsBits.USE_BVH * int(use_bvh) +
			RenderFlagsBits.SHOW_BVH_DEPTH * int(show_bvh_depth) +
			RenderFlagsBits.SCENE_CHANGED * int(scene_changed)
		)
	
