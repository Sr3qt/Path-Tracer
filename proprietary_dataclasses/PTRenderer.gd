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
var canvas

# A scene with objects and a camera node
var scene : PTScene


func _enter_tree():
	rtwd = PTWorkDispatcher.new(self)


func _ready():
	
	get_window().position = Vector2(1250, 400)
	
	## TODO: Make canvas programatically
	canvas = get_node("Canvas")
	scene = get_node("PTScene") # Is this the best way to get Scene node?
	
	rtwd.set_scene(scene)
	
	rtwd.create_buffers()


func _process(delta):
	rtwd._process(delta)
	
	if rtwd.is_rendering:
		rtwd.create_compute_list()


