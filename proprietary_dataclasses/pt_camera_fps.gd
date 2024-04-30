@tool
class_name PTCameraFPS
extends PTCamera

"""Built-in camera with controls"""

@export var mouse_sensitivity_x := 10.0
@export var mouse_sensitivity_y := 10.0
@export var move_speed := 3.5

# For plugin, relative root node in plugin instance
var root_node 
var freeze := true # stops input movement


func _ready():
	super._ready()
	
	# DEPRECATED
	#var grandpa = get_parent().get_parent()
	#if grandpa is PTRenderer:
		#root_node = grandpa.root_node
	#
	#if root_node and Engine.is_editor_hint():
		#root_node.connect("gui_input", _input)
	

func _process(delta):
	var plugin = (Engine.is_editor_hint() and root_node and root_node.visible and
			not freeze)
	if not Engine.is_editor_hint() or plugin:
		# MOve to player ndoe
		if Input.is_key_pressed(KEY_W):
			self.position += ((-forward * Vector3(1,0,1)).normalized() * move_speed * delta)
		if Input.is_key_pressed(KEY_A):
			self.position += (-right * Vector3(1,0,1) * move_speed * delta)
		if Input.is_key_pressed(KEY_S):
			self.position += ((forward * Vector3(1,0,1)).normalized() * move_speed * delta)
		if Input.is_key_pressed(KEY_D):
			self.position += (right * Vector3(1,0,1) * move_speed * delta)


func _input(event):
	var plugin = ((root_node and root_node.button_pressed and Engine.is_editor_hint())
			or not Engine.is_editor_hint())
	if event is InputEventMouseMotion and event.button_mask & 1 and plugin:
		# modify accumulated mouse rotation
		var rot_x = event.relative.x * mouse_sensitivity_x / 1000.
		var rot_y = event.relative.y * mouse_sensitivity_y / 1000.
 
		# Old transform
		# NOTE: The new and old tranforms rotate in a different order and with negated
		#  values, still they both work correctly
		var _transform = (
				Transform3D()
				.rotated(Vector3.UP, rot_x)
				.rotated(right, rot_y))
		
		# Remember to translate to origin before rotating
		var prev_origin = transform.origin
		transform.origin = Vector3.ZERO
		
		self.transform = (
				transform
				.rotated(right, -rot_y)
				.rotated(Vector3.UP, -rot_x)
				.orthonormalized())
		transform.origin = prev_origin

