extends CheckBox

@onready var parent : PTRenderWindow = get_parent()


func _ready():
	%PanelContainer.visible = false
	
	%UseBVHButton.button_pressed = parent.use_bvh
	%ShowBVHDepthButton.button_pressed = parent.show_bvh_depth


func _toggled(toggled_on):
	%PanelContainer.visible = toggled_on


func _on_use_bvh_button_toggled(toggled_on):
	parent.use_bvh = toggled_on


func _on_show_bvh_depth_button_toggled(toggled_on):
	parent.show_bvh_depth = toggled_on
