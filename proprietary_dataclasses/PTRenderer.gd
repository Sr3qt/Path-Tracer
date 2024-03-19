
extends Node


class_name PTRenderer

"""This node should be the root node of a scene with PTScene object added as a child.

This node has the responsibility to take render settings and pass them to 
a the correct PTWorkDispatcher, wich will actually make the gpu render an image.


TODO: Add way to change certain values in shader programatically, like 
BVH max child count or image buffer being readonly.
"""

# Realtime PTWorkDispatcher
var rtwd : PTWorkDispatcher
#var nrtwd : PTWorkDispatcher

# The mesh to draw to
var canvas : MeshInstance3D

# A scene with objects and a camera node
var scene : PTScene

var bvh_max_children := 8


# Render Flags
var use_bvh := true
var show_bvh_depth := !false # TODO FIX this

var scene_changed := true

func _enter_tree():
	rtwd = PTWorkDispatcher.new(self)


func _ready():
	
	get_window().position = Vector2(1250, 400)
	
	# Create godot camera to observe canvas
	var normal_camera = Camera3D.new()
	normal_camera.position += Vector3(0,0,1)
	add_child(normal_camera)
	
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
	


func _process(delta):
	rtwd._process(delta)
	
	if rtwd.is_rendering:
		rtwd.create_compute_list()
		var mat = canvas.mesh.surface_get_material(0)
		mat.set_shader_parameter("is_rendering", true)
	else:
		var mat = canvas.mesh.surface_get_material(0)
		mat.set_shader_parameter("is_rendering", false)


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
	


func flags_to_byte_array():
	var flag_array = PackedInt32Array([use_bvh, show_bvh_depth, scene_changed])
	return flag_array.to_byte_array()
