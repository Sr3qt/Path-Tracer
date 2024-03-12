extends Node

class_name PTMaterial

# Similar to GPU material, temporary
var albedo : Vector3 # Stored as linear color values from 0 to 1
var roughness
var metallic
var opacity
var IOR


func get_rgb():
	"""Returns albedo as rgb values from 0 to 255 in srgb space"""
