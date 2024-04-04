@tool
extends CheckBox

""" Controls all gui button connections """

@onready var parent : PTRenderWindow = get_parent()

var bvh_types_array

var is_plugin_instance


func _ready():
	if not Engine.is_editor_hint() or is_plugin_instance:
		%PanelContainer.visible = false
		
		# Set default value for buttons
		%UseBVHButton.button_pressed = parent.use_bvh
		%ShowBVHDepthButton.button_pressed = parent.show_bvh_depth
		
		# Initialize bvh dropdown menu
		bvh_types_array = PTBVHTree.BVHType.keys()
		var temp : PTOptionButton = %BVHType
		bvh_types_array[0] += " (Default)"
		for i in range(bvh_types_array.size()):
			var text = bvh_types_array[i]
			#text = text.replacen("_", " ")
			#text = text.to_pascal_case()
			temp.add_item(text.capitalize(), i)
			
		#temp.selected = 0
	

func _toggled(toggled_on):
	%PanelContainer.visible = toggled_on


func _on_use_bvh_button_toggled(toggled_on):
	parent.use_bvh = toggled_on
	
	%ShowBVHDepthButton.set_disable(not toggled_on)


func _on_show_bvh_depth_button_toggled(toggled_on):
	parent.show_bvh_depth = toggled_on


func _on_bvh_type_item_selected(index):
	pass # Replace with function body.
