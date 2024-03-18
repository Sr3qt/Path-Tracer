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
	mat.shader = load("res://canvas.gdshader")
	mat.set_shader_parameter("image_buffer", Texture2DRD.new())
	#mat.set_shader_parameter("preview_image_buffer", ImageTexture.new())
	
	# Create a canvas to which rendered images will be drawn
	canvas = MeshInstance3D.new()
	canvas.mesh = QuadMesh.new()
	canvas.mesh.size = Vector2(2, 2)
	canvas.mesh.surface_set_material(0, mat)
	add_child(canvas)
	
	scene = get_node("PTScene") # Is this the best way to get Scene node?
	
	rtwd.set_scene(scene)
	
	rtwd.create_buffers()


func _process(delta):
	rtwd._process(delta)
	
	if rtwd.is_rendering:
		rtwd.create_compute_list()


func change_file():
	var file = FileAccess.open("res://ray_tracer.comp.glsl", FileAccess.READ_WRITE)
	
	
