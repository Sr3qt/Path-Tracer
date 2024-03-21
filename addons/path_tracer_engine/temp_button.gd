#@tool
extends Button


func _enter_tree():
	
	print("Button enterd trre")

func _exit_tree():
	print("Button erxit trre")


func _ready():
	
	print("Button is ready")
	pressed.connect(_on_print_hello_pressed)

func _on_print_hello_pressed():
	print("Hello from the main screen plugin!")
